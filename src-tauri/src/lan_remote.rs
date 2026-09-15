//! Realtime LAN remote transport for the NexQ overlay.
//!
//! The LAN second screen is intentionally answer-focused: it receives the
//! same streaming AI response shown by the Assist / What To Say panel, but
//! does not expose the interview transcript.

use axum::{
    extract::{ws::{Message, WebSocket, WebSocketUpgrade}, State},
    response::Html,
    routing::get,
    Router,
};
use futures::StreamExt;
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
    task: Option<tauri::async_runtime::JoinHandle<()>>,
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
        self.task.is_some()
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
        let bound_port = std_listener
            .local_addr()
            .map_err(|e| format!("Failed to read LAN remote address: {}", e))?
            .port();

        let (tx, _rx) = broadcast::channel(CHANNEL_CAPACITY);
        let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();
        let app = Router::new()
            .route("/", get(remote_page))
            .route("/ws", get(websocket_handler))
            .with_state(ServerState { tx: tx.clone() });

        self.port = bound_port;
        self.tx = Some(tx);
        self.shutdown = Some(shutdown_tx);

        let task = tauri::async_runtime::spawn(async move {
            let listener = match tokio::net::TcpListener::from_std(std_listener) {
                Ok(listener) => listener,
                Err(e) => {
                    log::error!("Failed to initialize LAN remote listener: {}", e);
                    return;
                }
            };

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
                "message": "NexQ AI Remote connected"
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
<title>NexQ AI Remote</title>
<style>
  :root { color-scheme: dark; font-family: Inter, Segoe UI, sans-serif; }
  * { box-sizing: border-box; }
  html, body { margin: 0; min-height: 100%; background: #07090c; color: #f5f7fa; }
  body { min-height: 100vh; }
  header { position: sticky; top: 0; z-index: 2; padding: 18px 28px; border-bottom: 1px solid #20242a; background: rgba(7,9,12,.94); backdrop-filter: blur(14px); }
  .row { display:flex; align-items:center; gap:10px; }
  .dot { width:9px; height:9px; border-radius:50%; background:#555b63; }
  .dot.ok { background:#4ade80; box-shadow:0 0 14px rgba(74,222,128,.45); }
  .meta { color:#8d95a0; font-size:13px; }
  main { width:min(1200px, 100%); min-height:calc(100vh - 70px); margin:0 auto; padding:32px 28px 64px; display:flex; flex-direction:column; }
  .mode { align-self:flex-start; margin-bottom:18px; padding:7px 12px; border:1px solid #28313b; border-radius:999px; color:#aeb8c4; background:#0d1116; font-size:13px; font-weight:700; letter-spacing:.05em; text-transform:uppercase; }
  .answer { flex:1; display:flex; align-items:flex-start; justify-content:center; }
  .answer-inner { width:100%; padding:12vh 3vw 8vh; }
  .answer-text { font-size:clamp(32px, 5vw, 76px); line-height:1.2; font-weight:650; letter-spacing:-.02em; white-space:pre-wrap; overflow-wrap:anywhere; }
  .cursor { display:inline-block; width:.08em; height:1em; margin-left:.12em; vertical-align:-.08em; background:#8ab4ff; animation:blink 1s steps(2,end) infinite; }
  .waiting { margin:auto; color:#626b76; font-size:18px; text-align:center; }
  .hint { margin-top:auto; padding-top:24px; color:#4f5761; text-align:center; font-size:12px; }
  .error { color:#f0a7a7; }
  @keyframes blink { 50% { opacity:0; } }
  @media (max-width:700px) {
    header { padding:14px 16px; }
    main { padding:20px 16px 40px; }
    .answer-inner { padding:10vh 0 6vh; }
    .answer-text { font-size:clamp(30px, 8vw, 52px); }
  }
</style>
</head>
<body>
<header>
  <div class="row"><span id="dot" class="dot"></span><strong>NexQ AI Remote</strong><span id="status" class="meta">connecting…</span></div>
</header>
<main>
  <div id="mode" class="mode">Ready</div>
  <section class="answer" aria-live="polite" aria-label="NexQ AI response">
    <div class="answer-inner">
      <div id="waiting" class="waiting">Waiting for AI assistance…</div>
      <div id="answer" class="answer-text" hidden></div>
    </div>
  </section>
  <div id="hint" class="hint">AI answer screen · Assist / What To Say · large text</div>
</main>
<script>
const dot = document.getElementById('dot');
const status = document.getElementById('status');
const mode = document.getElementById('mode');
const waiting = document.getElementById('waiting');
const answer = document.getElementById('answer');
let streamActive = false;
function modeLabel(value){
  const labels={Assist:'Assist',WhatToSay:'What To Say',Shorten:'Shorten',FollowUp:'Follow Up',Recap:'Recap',AskQuestion:'Ask Question',MeetingSummary:'Meeting Summary',ActionItemsExtraction:'Action Items',BookmarkSuggestions:'Suggestions'};
  return labels[value] || value || 'AI Assist';
}
function show(text){
  waiting.hidden = !!text;
  answer.hidden = !text;
  answer.textContent = text || '';
}
function apply(msg){
  if(msg.type==='ai_start'){
    const p=msg.payload||{};
    streamActive=true;
    mode.textContent=modeLabel(p.mode);
    show('');
    answer.hidden=false;
    answer.textContent='';
    const cursor=document.createElement('span');
    cursor.className='cursor';
    answer.appendChild(cursor);
    return;
  }
  if(msg.type==='ai_token'){
    const p=msg.payload||{};
    if(!streamActive){ streamActive=true; show(''); answer.hidden=false; answer.textContent=''; }
    const cursor=answer.querySelector('.cursor');
    if(cursor) cursor.remove();
    answer.appendChild(document.createTextNode(p.token || ''));
    const nextCursor=document.createElement('span');
    nextCursor.className='cursor';
    answer.appendChild(nextCursor);
    return;
  }
  if(msg.type==='ai_end'){
    streamActive=false;
    const cursor=answer.querySelector('.cursor');
    if(cursor) cursor.remove();
    return;
  }
}
function connect(){
  const proto=location.protocol==='https:'?'wss':'ws';
  const ws=new WebSocket(`${proto}://${location.host}/ws?v=2`);
  ws.onopen=()=>{ dot.classList.add('ok'); status.textContent='connected'; };
  ws.onclose=()=>{ dot.classList.remove('ok'); status.textContent='reconnecting…'; setTimeout(connect,1200); };
  ws.onerror=()=>{ dot.classList.remove('ok'); status.textContent='connection error'; };
  ws.onmessage=e=>{ try{ apply(JSON.parse(e.data)); }catch{} };
}
connect();
</script>
</body>
</html>"#,
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
