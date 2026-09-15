use tauri::State;

use crate::lan_remote::{self, LanRemoteInfo};
use crate::state::AppState;

#[tauri::command]
pub fn start_lan_remote(
    state: State<'_, AppState>,
    port: Option<u16>,
) -> Result<LanRemoteInfo, String> {
    let mut guard = state
        .lan_remote
        .lock()
        .map_err(|_| "LAN remote lock poisoned".to_string())?;
    guard.start(port)
}

#[tauri::command]
pub fn stop_lan_remote(state: State<'_, AppState>) -> Result<(), String> {
    let mut guard = state
        .lan_remote
        .lock()
        .map_err(|_| "LAN remote lock poisoned".to_string())?;
    guard.stop();
    Ok(())
}

#[tauri::command]
pub fn get_lan_remote_info(state: State<'_, AppState>) -> Result<LanRemoteInfo, String> {
    let guard = state
        .lan_remote
        .lock()
        .map_err(|_| "LAN remote lock poisoned".to_string())?;
    Ok(guard.info())
}

#[tauri::command]
pub fn lan_publish(kind: String, payload_json: String, state: State<'_, AppState>) -> Result<usize, String> {
    let payload: serde_json::Value = serde_json::from_str(&payload_json)
        .map_err(|e| format!("Invalid LAN payload JSON: {}", e))?;

    let envelope = serde_json::json!({
        "version": 1,
        "type": kind,
        "payload": payload,
    });

    lan_remote::publish_json(&state.lan_remote, envelope)
}
