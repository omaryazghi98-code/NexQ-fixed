//! Realtime LAN remote transport for the NexQ overlay.
//!
//! The LAN second screen is answer-focused: it receives the streaming AI
//! response shown by the Assist / What To Say panel and does not expose the
//! interview transcript. A separate /control page provides a touch-friendly
//! phone remote for scrolling the display.

use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        State, Json,
    },
    http::StatusCode,
    response::Html,
    routing::{get, post},
    Router,
};
use futures::StreamExt;
use serde::{Deserialize, Serialize};
use std::net::{IpAddr, UdpSocket};
use std::sync::{Arc, Mutex};
use tokio::sync::{broadcast, oneshot};

const DEFAULT_PORT: u16 = 17_321;
const CHANNEL_CAPACITY: usize = 256;

#[derive(Clone)]
struct ServerState {
    tx: broadcast::Sender<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct LanRemoteInfo {
    pub running: bool,
    pub port: u16,
    pub urls: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ControlMessage {
    #[serde(rename = "type")]
    kind: String,
    action: String,
    #[serde(default)]
    source: Option<String>,
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
            .route("/control", get(control_page))
            .route("/ws", get(websocket_handler))
            .route("/control", post(control_http_handler))
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
    let tx = state.tx.clone();
    ws.on_upgrade(move |socket| handle_socket(socket, tx.subscribe(), tx))
}

async fn control_http_handler(
    State(state): State<ServerState>,
    Json(mut message): Json<ControlMessage>,
) -> (StatusCode, Json<serde_json::Value>) {
    if message.kind != "control" || !is_supported_action(&message.action) {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"ok": false, "error": "invalid control command"})),
        );
    }

    message.source.get_or_insert_with(|| "http".to_string());
    let payload = match serde_json::to_string(&message) {
        Ok(payload) => payload,
        Err(error) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"ok": false, "error": error.to_string()})),
            )
        }
    };

    match state.tx.send(payload) {
        Ok(_) => (
            StatusCode::OK,
            Json(serde_json::json!({"ok": true})),
        ),
        Err(_) => (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(serde_json::json!({"ok": false, "error": "no remote display connected"})),
        ),
    }
}

fn is_supported_action(action: &str) -> bool {
    matches!(
        action,
        "top"
            | "bottom"
            | "up"
            | "down"
            | "page_up"
            | "page_down"
            | "scroll_up"
            | "scroll_down"
            | "pageUp"
            | "pageDown"
    )
}

async fn handle_socket(
    mut socket: WebSocket,
    mut rx: broadcast::Receiver<String>,
    tx: broadcast::Sender<String>,
) {
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
                    Some(Ok(Message::Text(text))) => {
                        if let Ok(mut value) = serde_json::from_str::<ControlMessage>(&text) {
                            if value.kind == "control" && is_supported_action(&value.action) {
                                value.source.get_or_insert_with(|| "websocket".to_string());
                                if let Ok(normalized) = serde_json::to_string(&value) {
                                    let _ = tx.send(normalized);
                                }
                            }
                        }
                    }
                    Some(Ok(Message::Ping(payload))) => {
                        let _ = socket.send(Message::Pong(payload)).await;
                    }
                    Some(Ok(_)) => {}
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
    Html(r#"<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover" />
<title>NexQ AI Remote</title>
<style>
  :root { color-scheme: dark; font-family: Inter, Segoe UI, sans-serif; --zoom:1; }
  * { box-sizing: border-box; }
  html, body { margin:0; min-height:100%; background:#07090c; color:#f5f7fa; }
  body { min-height:100vh; }
  header { position:sticky; top:0; z-index:10; padding:16px 22px; border-bottom:1px solid #20242a; background:rgba(7,9,12,.94); backdrop-filter:blur(14px); }
  .row { display:flex; align-items:center; gap:10px; }
  .dot { width:9px; height:9px; border-radius:50%; background:#555b63; }
  .dot.ok { background:#4ade80; box-shadow:0 0 14px rgba(74,222,128,.45); }
  .meta { color:#8d95a0; font-size:13px; }
  .tools { margin-left:auto; display:flex; align-items:center; gap:6px; }
  .tool { border:1px solid #2a3139; background:#0e1217; color:#dbe2ea; border-radius:8px; min-width:38px; height:34px; font-size:16px; cursor:pointer; }
  .tool:hover { background:#151b22; }
  .zoom-label { min-width:50px; text-align:center; color:#8d95a0; font-size:12px; }
  .link { color:#9fb7ff; text-decoration:none; font-size:12px; margin-left:8px; }
  main { width:min(1200px,100%); min-height:calc(100vh - 66px); margin:0 auto; padding:20px 28px 60px; display:flex; flex-direction:column; }
  .mode { align-self:flex-start; margin-bottom:8px; padding:7px 12px; border:1px solid #28313b; border-radius:999px; color:#aeb8c4; background:#0d1116; font-size:13px; font-weight:700; letter-spacing:.05em; text-transform:uppercase; }
  .answer { flex:1; }
  .answer-inner { width:100%; padding:6vh 3vw 8vh; }
  .answer-text { font-size:calc(clamp(32px, 5vw, 76px) * var(--zoom)); line-height:1.2; font-weight:650; letter-spacing:-.02em; white-space:pre-wrap; overflow-wrap:anywhere; }
  .cursor { display:inline-block; width:.08em; height:1em; margin-left:.12em; vertical-align:-.08em; background:#8ab4ff; animation:blink 1s steps(2,end) infinite; }
  .waiting { margin:16vh auto 0; color:#626b76; font-size:18px; text-align:center; }
  .hint { margin-top:20px; padding-top:18px; color:#4f5761; text-align:center; font-size:12px; }
  @keyframes blink { 50% { opacity:0; } }
  @media (max-width:700px) {
    header { padding:12px 14px; }
    main { padding:16px 14px 40px; }
    .answer-inner { padding:6vh 0 6vh; }
    .answer-text { font-size:calc(clamp(30px, 8vw, 52px) * var(--zoom)); }
    .link { display:none; }
  }
</style>
</head>
<body>
<header>
  <div class="row">
    <span id="dot" class="dot"></span>
    <strong>NexQ AI Remote</strong>
    <span id="status" class="meta">connecting…</span>
    <div class="tools">
      <button class="tool" onclick="changeZoom(-0.1)" aria-label="Zoom out">−</button>
      <span id="zoomLabel" class="zoom-label">100%</span>
      <button class="tool" onclick="changeZoom(0.1)" aria-label="Zoom in">+</button>
      <button class="tool" onclick="resetZoom()" aria-label="Reset zoom">↺</button>
      <a class="link" href="/control">Phone controller</a>
    </div>
  </div>
</header>
<main>
  <div id="mode" class="mode">Ready</div>
  <section class="answer" aria-live="polite" aria-label="NexQ AI response">
    <div class="answer-inner">
      <div id="waiting" class="waiting">Waiting for AI assistance…</div>
      <div id="answer" class="answer-text" hidden></div>
    </div>
  </section>
  <div class="hint">AI answer screen · Assist / What To Say · large readable text · <a class="link" href="/control">open phone controller</a></div>
</main>
<script>
const dot=document.getElementById('dot');
const status=document.getElementById('status');
const mode=document.getElementById('mode');
const waiting=document.getElementById('waiting');
const answer=document.getElementById('answer');
const root=document.documentElement;
let streamActive=false;
let zoom=Number(localStorage.getItem('nexq-remote-zoom')||'1');
function clamp(v,min,max){return Math.max(min,Math.min(max,v));}
function renderZoom(){zoom=clamp(zoom,0.5,1.2);root.style.setProperty('--zoom',zoom.toFixed(2));document.getElementById('zoomLabel').textContent=Math.round(zoom*100)+'%';localStorage.setItem('nexq-remote-zoom',String(zoom));}
function changeZoom(delta){zoom+=delta;renderZoom();}
function resetZoom(){zoom=1;renderZoom();}
renderZoom();
function modeLabel(value){const labels={Assist:'Assist',WhatToSay:'What To Say',Shorten:'Shorten',FollowUp:'Follow Up',Recap:'Recap',AskQuestion:'Ask Question',MeetingSummary:'Meeting Summary',ActionItemsExtraction:'Action Items',BookmarkSuggestions:'Suggestions'};return labels[value]||value||'AI Assist';}
function begin(){waiting.hidden=true;answer.hidden=false;answer.textContent='';}
function apply(msg){
  if(msg.type==='ai_start'){
    streamActive=true;
    mode.textContent=modeLabel((msg.payload||{}).mode);
    begin();
    const cursor=document.createElement('span');cursor.className='cursor';answer.appendChild(cursor);
    return;
  }
  if(msg.type==='ai_token'){
    const p=msg.payload||{};
    if(!streamActive){streamActive=true;begin();}
    const content=typeof p.content==='string'?p.content:'';
    const incoming=typeof p.token==='string'?p.token:'';
    if(content!==''||incoming!==''){
      answer.textContent=content || (answer.textContent + incoming);
      const cursor=document.createElement('span');cursor.className='cursor';answer.appendChild(cursor);
    }
    return;
  }
  if(msg.type==='ai_end'){
    streamActive=false;
    answer.querySelector('.cursor')?.remove();
    return;
  }
  if(msg.type==='control'){
    const action=(msg.action||msg.payload?.action||'');
    const normalized={scroll_up:'up',scroll_down:'down',pageUp:'page_up',pageDown:'page_down'}[action]||action;
    const amounts={up:-220,down:220,page_up:-window.innerHeight*0.82,page_down:window.innerHeight*0.82};
    if(normalized==='top') window.scrollTo({top:0,behavior:'smooth'});
    else if(normalized==='bottom') window.scrollTo({top:document.documentElement.scrollHeight,behavior:'smooth'});
    else if(amounts[normalized]) window.scrollBy({top:amounts[normalized],behavior:'smooth'});
  }
}
function connect(){
  const proto=location.protocol==='https:'?'wss':'ws';
  const ws=new WebSocket(`${proto}://${location.host}/ws?v=4`);
  ws.onopen=()=>{dot.classList.add('ok');status.textContent='connected';};
  ws.onclose=()=>{dot.classList.remove('ok');status.textContent='reconnecting…';setTimeout(connect,1200);};
  ws.onerror=()=>{dot.classList.remove('ok');status.textContent='connection error';};
  ws.onmessage=e=>{try{apply(JSON.parse(e.data));}catch{}};
}
connect();
</script>
</body>
</html>"#)
}

async fn control_page() -> Html<&'static str> {
    Html(r#"<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover" />
<meta name="apple-mobile-web-app-capable" content="yes" />
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent" />
<title>NexQ Phone Controller</title>
<style>
  :root { color-scheme:dark; font-family:Inter,Segoe UI,sans-serif; }
  * { box-sizing:border-box; }
  html,body { margin:0; min-height:100%; background:#07090c; color:#f5f7fa; }
  body { min-height:100vh; display:flex; flex-direction:column; touch-action:pan-y; overscroll-behavior:none; user-select:none; -webkit-user-select:none; -webkit-touch-callout:none; }
  header { padding:18px 18px 14px; border-bottom:1px solid #20242a; background:#0a0d11; }
  .row { display:flex; align-items:center; gap:10px; }
  .dot { width:9px; height:9px; border-radius:50%; background:#555b63; }
  .dot.ok { background:#4ade80; box-shadow:0 0 14px rgba(74,222,128,.45); }
  .meta { color:#8d95a0; font-size:13px; }
  main { flex:1; padding:18px; display:flex; flex-direction:column; justify-content:center; gap:12px; max-width:520px; width:100%; margin:0 auto; }
  .hint { color:#7d8793; font-size:13px; text-align:center; margin-bottom:6px; }
  .status { min-height:20px; color:#8d95a0; font-size:12px; text-align:center; }
  .grid { display:grid; grid-template-columns:1fr 1fr 1fr; gap:10px; }
  button { -webkit-appearance:none; appearance:none; min-height:74px; border:1px solid #2a3139; border-radius:16px; background:#11161c; color:#eef2f7; font-size:24px; font-weight:700; box-shadow:0 6px 20px rgba(0,0,0,.24); touch-action:manipulation; }
  button:active { transform:scale(.98); background:#1a212a; }
  .label { display:block; font-size:11px; color:#8d95a0; margin-top:5px; font-weight:500; }
  .wide { grid-column:span 3; min-height:62px; font-size:18px; }
  .back { color:#9fb7ff; text-decoration:none; text-align:center; font-size:13px; margin-top:8px; }
  .zone { border:1px dashed #2a3139; border-radius:18px; min-height:82px; display:flex; align-items:center; justify-content:center; color:#7d8793; font-size:13px; touch-action:none; }
</style>
</head>
<body>
<header><div class="row"><span id="dot" class="dot"></span><strong>NexQ Phone Controller</strong><span id="status" class="meta">connecting…</span></div></header>
<main>
  <div class="hint">Remote control for the AI answer screen.</div>
  <div id="commandStatus" class="status">Ready</div>
  <div class="grid">
    <button data-action="top">⇈<span class="label">TOP</span></button>
    <button data-action="page_up">▲<span class="label">PAGE UP</span></button>
    <button data-action="up">↑<span class="label">UP</span></button>
    <button data-action="down">↓<span class="label">DOWN</span></button>
    <button data-action="page_down">▼<span class="label">PAGE DOWN</span></button>
    <button data-action="bottom">⇊<span class="label">BOTTOM</span></button>
    <button class="wide" data-action="page_down">Scroll forward</button>
  </div>
  <div id="swipeZone" class="zone">Swipe here to scroll · up / down</div>
  <a class="back" href="/">← Back to AI display</a>
</main>
<script>
const dot=document.getElementById('dot');
const status=document.getElementById('status');
const commandStatus=document.getElementById('commandStatus');
const zone=document.getElementById('swipeZone');
let ws;
let wsReady=false;
function wsConnect(){
  const proto=location.protocol==='https:'?'wss':'ws';
  try{ws=new WebSocket(`${proto}://${location.host}/ws?v=4-control`);}catch{return;}
  ws.onopen=()=>{wsReady=true;dot.classList.add('ok');status.textContent='connected';};
  ws.onclose=()=>{wsReady=false;dot.classList.remove('ok');status.textContent='reconnecting…';setTimeout(wsConnect,1200);};
  ws.onerror=()=>{wsReady=false;};
}
async function send(action){
  commandStatus.textContent='Sending…';
  const payload=JSON.stringify({type:'control',action,source:'iphone'});
  let sent=false;
  try{
    const res=await fetch('/control',{method:'POST',headers:{'Content-Type':'application/json'},cache:'no-store',body:payload});
    sent=res.ok;
  }catch{}
  if(!sent && wsReady){
    try{ws.send(payload);sent=true;}catch{}
  }
  commandStatus.textContent=sent?'✓ '+action.replaceAll('_',' '):'⚠ Not delivered';
  if(navigator.vibrate) navigator.vibrate(10);
  setTimeout(()=>{if(commandStatus.textContent.includes(action.replaceAll('_',' ')))commandStatus.textContent='Ready';},900);
}
document.querySelectorAll('button[data-action]').forEach(button=>{
  button.addEventListener('click',()=>send(button.dataset.action),{passive:true});
  button.addEventListener('touchend',e=>{e.preventDefault();send(button.dataset.action);},{passive:false});
});
let startY=null,lastY=null;
zone.addEventListener('touchstart',e=>{if(e.touches.length!==1)return;startY=e.touches[0].clientY;lastY=startY;},{passive:true});
zone.addEventListener('touchmove',e=>{if(startY===null||e.touches.length!==1)return;const y=e.touches[0].clientY;const delta=y-lastY;if(Math.abs(delta)>=45){send(delta<0?'down':'up');lastY=y;}e.preventDefault();},{passive:false});
zone.addEventListener('touchend',()=>{startY=null;lastY=null;},{passive:true});
wsConnect();
</script>
</body>
</html>"#)
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