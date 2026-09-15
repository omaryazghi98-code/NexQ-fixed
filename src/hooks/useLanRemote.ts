import { useEffect } from "react";
import {
  onStreamStart,
  onStreamToken,
  onStreamEnd,
} from "../lib/events";
import {
  publishLanAiStart,
  publishLanAiToken,
  publishLanAiEnd,
  startLanRemote,
} from "../lib/lanRemote";

/**
 * Starts the LAN second-screen server from the launcher and mirrors only the
 * live AI response stream. Transcript and translation events stay on the main
 * NexQ window.
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
          console.info(
            "[LAN Remote] Ready:",
            info.urls.join(", ") || `port ${info.port}`,
          );
        }
      } catch (error) {
        console.warn("[LAN Remote] Server unavailable:", error);
        return;
      }

      const startUnlisten = await onStreamStart((event) => {
        publishLanAiStart(event.mode).catch(() => {});
      });

      const tokenUnlisten = await onStreamToken((event) => {
        publishLanAiToken(event.token).catch(() => {});
      });

      const endUnlisten = await onStreamEnd(() => {
        publishLanAiEnd().catch(() => {});
      });

      if (!mounted) {
        startUnlisten();
        tokenUnlisten();
        endUnlisten();
        return;
      }

      unlisteners.push(startUnlisten, tokenUnlisten, endUnlisten);
    };

    setup().catch((error) =>
      console.warn("[LAN Remote] Setup failed:", error),
    );

    return () => {
      mounted = false;
      unlisteners.forEach((unlisten) => unlisten());
    };
  }, []);
}
