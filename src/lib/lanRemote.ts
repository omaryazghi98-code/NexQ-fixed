import { invoke } from "@tauri-apps/api/core";
import type { TranscriptSegment, TranslationResult } from "./types";

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

export async function publishLanTranscript(segment: TranscriptSegment): Promise<void> {
  await invoke("lan_publish", {
    kind: "transcript",
    payloadJson: JSON.stringify(segment),
  });
}

export async function publishLanTranslation(result: TranslationResult): Promise<void> {
  await invoke("lan_publish", {
    kind: "translation",
    payloadJson: JSON.stringify(result),
  });
}
