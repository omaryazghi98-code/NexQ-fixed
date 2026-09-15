import { invoke } from "@tauri-apps/api/core";
import type { IntelligenceMode } from "./types";

export interface LanRemoteInfo {
  running: boolean;
  port: number;
  urls: string[];
}

export async function startLanRemote(port?: number): Promise<LanRemoteInfo> {
  return invoke<LanRemoteInfo>("start_lan_remote", { port });
}

export async function stopLanRemote(): Promise<void> {
  return invoke("stop_lan_remote");
}

export async function getLanRemoteInfo(): Promise<LanRemoteInfo> {
  return invoke<LanRemoteInfo>("get_lan_remote_info");
}

export async function publishLanAiStart(mode: IntelligenceMode): Promise<void> {
  await invoke("lan_publish", {
    kind: "ai_start",
    payloadJson: JSON.stringify({ mode }),
  });
}

export async function publishLanAiToken(token: string, content: string): Promise<void> {
  await invoke("lan_publish", {
    kind: "ai_token",
    payloadJson: JSON.stringify({ token, content }),
  });
}

export async function publishLanAiEnd(): Promise<void> {
  await invoke("lan_publish", {
    kind: "ai_end",
    payloadJson: JSON.stringify({}),
  });
}
