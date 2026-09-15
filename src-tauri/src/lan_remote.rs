//! Realtime LAN remote transport for the NexQ overlay.
//!
//! The first iteration deliberately keeps the transport thin:
//! - NexQ publishes typed JSON envelopes from the existing transcript/translation events.
//! - A small HTTP page is served on the same port for a second-screen browser.
//! - WebSocket clients receive the same event stream in realtime.
//!
//! This module does not run STT or translation itself. It transports the results that
//! NexQ already produces, which keeps provider selection and latency-sensitive work
//! inside the existing pipeline.

use axum::{
    extract::{ws::{Message, WebSocket, WebSocketUpgrade}, State},
    response::Html,
    routing::get,
    Router,
};
use futures::{SinkExt, StreamExt};
use std::net::{IpAddr, UdpSocket};
use std::sync::{Arc, Mutex};
use tokio::sync::{broadcast, oneshot};

const DEFAULT_PORT: u16 = 17_321;
const CHANNEL_CAPACITY: usize = 256;

#[derive(Clone)]
struct ServerState {
    tx: broadcast::Sender<String>,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct LanRemoteInfo {
    pub running: bool,
    pub port: u16,
    pub urls: Vec<String>,
}

pub struct LanRemoteManager {
    port: u16,
    tx: Option<broadcast::Sender<String>>,
    shutdown: Option<oneshot::Sender<()>>,
    task: Option<tokio::task::JoinHandle<()>>,
}

impl Default for LanRemoteManager {
    fn default() -> Self {
        Self {
            port: DEFAULT_PORT,
            tx: None,
            shutdown: None,
            task: None,
        }
    }
}

impl LanRemoteManager {
    pub fn is_running(&self) -> bool {
        self.task.as_ref().is_some_and(|task| !task.is_finished())
    }

    pub fn info(&self) -> LanRemoteInfo {
        LanRemoteInfo {
            running: self.is_running(),
            port: self.port,
            urls: local_urls(self.port),
        }
    }

    pub fn start(&mut self, port: Option<u16>) -> Result<LanRemoteInfo, String> {
        if self.is_running() {
            return Ok(self.info());
        }

        let port = port.unwrap_or(DEFAULT_PORT);
        let std_listener = std::net::TcpListener::bind(("0.0.0.0", port))
            .map_err(|e| format!("Failed to bind LAN remote on port {}: {}", port, e))?;
        std_listener
            .set_nonblocking(true)
            .map_err(|e| format!("Failed to configure LAN remote listener: {}", e))?;
        let listener = tokio::net::TcpListener::from_std(std_listener)
            .map_err(|e| format!("Failed to initialize LAN remote listener: {}", e))?;

        let (tx, _rx) = broadcast::channel(CHANNEL_CAPACITY);
        let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();
        let app = Router::new()
            .route("/", get(remote_page))
            .route("/ws", get(websocket_handler))
            .with_state(ServerState { tx: tx.clone() });

        let bound_port = listener
            .local_addr()
            .map_err(|e| format!("Failed to read LAN remote address: {}", e))?
            .port();

        self.port = bound_port;
        self.tx = Some(tx);
        self.shutdown = Some(shutdown_tx);

        let task = tokio::spawn(async move {
            let result = axum::serve(listener, app)
                .with_graceful_shutdown(async move {
                    let _ = shutdown_rx.await;
                })
                .await;
            if let Err(e) = result {
                log::error!("LAN remote server stopped with error: {}", e);
            }
        });

        self.task = Some(task);
        log::info!("LAN remote server started on port {}", bound_port);
        Ok(self.info())
    }

    pub fn stop(&mut self) {
        if let Some(shutdown) = self.shutdown.take() {
            let _ = shutdown.send(());
        }
        if let Some(task) = self.task.take() {
            task.abort();
        }
        self.tx = None;
        log::info!("LAN remote server stopped");
    }

    pub fn publish(&self, message: String) -> Result<usize, String> {
        let tx = self
            .tx
            .as_ref()
            .ok_or_else(|| "LAN remote server is not running".to_string())?;
        tx.send(message)
            .map_err(|_| "No LAN remote clients are currently connected".to_string())
    }
}

async fn websocket_handler(
    ws: WebSocketUpgrade,
    State(state): State<ServerState>,
) -> impl axum::response::IntoResponse {
    ws.on_upgrade(move |socket| handle_socket(socket, state.tx.subscribe()))
}

async fn handle_socket(mut socket: WebSocket, mut rx: broadcast::Receiver<String>) {
    let _ = socket
        .send(Message::Text(
            serde_json::json!({
                "version": 1,
                "type": "hello",
                "source": "nexq",
                "message": "NexQ LAN remote connected"
            })
            .to_string()
            .into(),
        ))
        .await;

    loop {
        tokio::select! {
            inbound = socket.next() => {
                match inbound {
                    Some(Ok(Message::Close(_))) | None => break,
                    Some(Ok(_)) => {},
                    Some(Err(_)) => break,
                }
            }
            outbound = rx.recv() => {
                match outbound {
                    Ok(payload) => {
                        if socket.send(Message::Text(payload.into())).await.is_err() {
                            break;
                        }
                    }
                    Err(broadcast::error::RecvError::Lagged(skipped)) => {
                        log::warn!("LAN remote client lagged; skipped {} messages", skipped);
                    }
                    Err(broadcast::error::RecvError::Closed) => break,
                }
            }
        }
    }
}

async fn remote_page() -> Html<&'static str> {
    Html(
        r#"<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>NexQ Remote</title>
<style>
  :root { color-scheme: dark; font-family: Inter, Segoe UI, sans-serif; }
  * { box-sizing: border-box; }
  body { margin: 0; min-height: 100vh; background: #08090b; color: #f3f4f6; }
  header { position: sticky; top: 0; z-index: 2; padding: 16px 20px; border-bottom: 1px solid #202329; background: rgba(8,9,11,.94); backdrop-filter: blur(12px); }
  .row { display:flex; align-items:center; gap:10px; }
  .dot { width:9px; height:9px; border-radius:50%; background:#555; }
  .dot.ok { background:#4ade80; box-shadow: 0 0 12px rgba(74,222,128,.5); }
  .meta { color:#8f96a3; font-size:12px; }
  main { width:min(1100px, 100%); margin:0 auto; padding:18px 20px 48px; }
  .empty { padding:60px 16px; text-align:center; color:#757b86; }
  .seg { padding:14px 0; border-bottom:1px solid #17191d; }
  .seg.interim { opacity:.72; }
  .top { display:flex; gap:10px; align-items:baseline; }
  .speaker { font-size:12px; font-weight:700; color:#aab1bd; letter-spacing:.04em; text-transform:uppercase; }
  .time { font-size:11px; color:#555b66; }
  .src { margin-top:6px; font-size:18px; line-height:1.42; }
  .tr { margin-top:8px; font-size:20px; line-height:1.45; color:#fff; }
  .tr:empty { display:none; }
  .banner { padding:10px 12px; border:1px solid #292d35; border-radius:10px; color:#aeb5c1; background:#0d0f12; margin-bottom:16px; font-size:12px; }
</style>
</head>
<body>
<header>
  <div class="row"><span id="dot" class="dot"></span><strong>NexQ Remote</strong><span id="status" class="meta">connecting…</span></div>
</header>
<main>
  <div class="banner">LAN remote v1 · live transcript + translation. Keep this page on the second screen.</div>
  <div id="segments"><div class="empty">Waiting for NexQ…</div></div>
</main>
<script>
const segments = new Map();
const container = document.getElementById('segments');
const dot = document.getElementById('dot');
const status = document.getElementById('status');
function fmt(ms){ if(!Number.isFinite(ms)) return ''; const d=new Date(ms); return d.toLocaleTimeString([], {hour:'2-digit',minute:'2-digit',second:'2-digit'}); }
function render(seg){
  let el = segments.get(seg.id);
  if(!el){
    el=document.createElement('section'); el.className='seg'; el.dataset.id=seg.id;
    el.innerHTML='<div class="top"><span class="speaker"></span><span class="time"></span></div><div class="src"></div><div class="tr"></div>';
    segments.set(seg.id,el); container.querySelector('.empty')?.remove(); container.appendChild(el);
  }
  el.classList.toggle('interim', !seg.is_final);
  el.querySelector('.speaker').textContent=seg.speaker_id || seg.speaker || 'Speaker';
  el.querySelector('.time').textContent=fmt(seg.timestamp_ms);
  el.querySelector('.src').textContent=seg.text || '';
  if(seg.translated_text !== undefined) el.querySelector('.tr').textContent=seg.translated_text || '';
}
function apply(msg){
  if(msg.type==='transcript'){ render(msg.payload); return; }
  if(msg.type==='translation'){
    const p=msg.payload || {};
    let el=segments.get(p.segment_id);
    if(!el){ render({id:p.segment_id,text:p.original_text||'',timestamp_ms:Date.now(),is_final:true,speaker_id:'Speaker',translated_text:p.translated_text||''}); }
    else el.querySelector('.tr').textContent=p.translated_text || '';
  }
}
function connect(){
  const proto=location.protocol==='https:'?'wss':'ws';
  const ws=new WebSocket(`${proto}://${location.host}/ws?v=1`);
  ws.onopen=()=>{ dot.classList.add('ok'); status.textContent='connected'; };
  ws.onclose=()=>{ dot.classList.remove('ok'); status.textContent='reconnecting…'; setTimeout(connect,1200); };
  ws.onerror=()=>{ dot.classList.remove('ok'); status.textContent='connection error'; };
  ws.onmessage=e=>{ try{ apply(JSON.parse(e.data)); }catch{} };
}
connect();
</script>
</body></html>"#,
    )
}

/// Publish a JSON event to all connected LAN clients.
pub fn publish_json(
    manager: &Arc<Mutex<LanRemoteManager>>,
    value: serde_json::Value,
) -> Result<usize, String> {
    let payload = serde_json::to_string(&value).map_err(|e| e.to_string())?;
    manager
        .lock()
        .map_err(|_| "LAN remote lock poisoned".to_string())?
        .publish(payload)
}

fn local_urls(port: u16) -> Vec<String> {
    let mut urls = vec![];

    if let Ok(socket) = UdpSocket::bind(("0.0.0.0", 0)) {
        if socket.connect(("8.8.8.8", 80)).is_ok() {
            if let Ok(addr) = socket.local_addr() {
                if let IpAddr::V4(ip) = addr.ip() {
                    if !ip.is_loopback() {
                        urls.push(format!("http://{}:{}", ip, port));
                    }
                }
            }
        }
    }

    urls.push(format!("http://127.0.0.1:{}", port));
    urls.dedup();
    urls
}
