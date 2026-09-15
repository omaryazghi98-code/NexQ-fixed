import { useEffect } from "react";
import { onTranscriptUpdate, onTranslationResult } from "../lib/events";
import {
  publishLanTranscript,
  publishLanTranslation,
  startLanRemote,
} from "../lib/lanRemote";

/**
 * Starts the LAN remote server from the launcher webview and mirrors the
 * existing transcript/translation event streams to connected second screens.
 *
 * The launcher remains the single publisher so the hidden overlay webview does
 * not duplicate every event.
 */
export function useLanRemote() {
  useEffect(() => {
    let mounted = true;
    const unlisteners: Array<() => void> = [];

    const setup = async () => {
      const { getCurrentWebviewWindow } = await import("@tauri-apps/api/webviewWindow");
      const label = getCurrentWebviewWindow().label;
      if (label !== "launcher") return;

      try {
        const info = await startLanRemote();
        if (mounted) {
          console.info("[LAN Remote] Ready:", info.urls.join(", ") || `port ${info.port}`);
        }
      } catch (error) {
        console.warn("[LAN Remote] Server unavailable:", error);
        return;
      }

      const transcriptUnlisten = await onTranscriptUpdate(({ segment }) => {
        publishLanTranscript(segment).catch(() => {
          // No connected remote is normal; do not disturb the interview UI.
        });
      });

      const translationUnlisten = await onTranslationResult((result) => {
        publishLanTranslation(result).catch(() => {});
      });

      if (!mounted) {
        transcriptUnlisten();
        translationUnlisten();
        return;
      }

      unlisteners.push(transcriptUnlisten, translationUnlisten);
    };

    setup().catch((error) => console.warn("[LAN Remote] Setup failed:", error));

    return () => {
      mounted = false;
      unlisteners.forEach((unlisten) => unlisten());
    };
  }, []);
}
