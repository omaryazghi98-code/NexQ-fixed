import { load } from "@tauri-apps/plugin-store";

export type CustomAuthType = "none" | "bearer" | "api_key";

export interface CustomLlmConfig {
  baseUrl: string;
  authType: CustomAuthType;
}

const STORE_FILE = "config.json";
const HISTORY_KEY = "customLlmEndpointHistory";
const LEGACY_BASE_URL_KEY = "customLlmBaseUrl";
const LEGACY_AUTH_TYPE_KEY = "customLlmAuthType";
const MAX_HISTORY = 25;
const HISTORY_UI_ID = "nexq-custom-endpoint-history";

function normalizeBaseUrl(value: string): string {
  return value.trim().replace(/\/+$/, "");
}

export async function getCustomLlmEndpointHistory(): Promise<string[]> {
  const store = await load(STORE_FILE, { autoSave: true, defaults: {} });
  const saved = await store.get<unknown>(HISTORY_KEY);
  if (!Array.isArray(saved)) return [];
  return saved
    .filter((value): value is string => typeof value === "string" && value.trim().length > 0)
    .map(normalizeBaseUrl)
    .filter(Boolean)
    .slice(0, MAX_HISTORY);
}

async function saveHistory(urls: string[]): Promise<void> {
  const store = await load(STORE_FILE, { autoSave: true, defaults: {} });
  await store.set(HISTORY_KEY, urls.slice(0, MAX_HISTORY));
}

async function appendToHistory(baseUrl: string): Promise<void> {
  const normalized = normalizeBaseUrl(baseUrl);
  if (!normalized) return;

  const current = await getCustomLlmEndpointHistory();
  const updated = [normalized, ...current.filter((url) => url !== normalized)];
  await saveHistory(updated);
}

/**
 * Add a lightweight endpoint-history UI to the existing Custom Base URL input.
 * This intentionally uses a native <datalist> so it works with the current
 * React settings screen without taking over its controlled state.
 */
async function refreshHistoryUi(): Promise<void> {
  if (typeof document === "undefined") return;

  const input = document.querySelector<HTMLInputElement>(
    'input[placeholder="http://localhost:8080/v1"]'
  );
  if (!input) return;

  const history = await getCustomLlmEndpointHistory();
  let datalist = document.getElementById(HISTORY_UI_ID) as HTMLDataListElement | null;

  if (!datalist) {
    datalist = document.createElement("datalist");
    datalist.id = HISTORY_UI_ID;
    input.setAttribute("list", HISTORY_UI_ID);
    // The datalist is non-visual; the browser renders suggestions when the
    // user focuses the URL field. Keep React completely in control of the input.
    document.body.appendChild(datalist);
  }

  datalist.replaceChildren(
    ...history.map((url) => {
      const option = document.createElement("option");
      option.value = url;
      return option;
    })
  );
}

export async function getCustomLlmConfig(): Promise<CustomLlmConfig> {
  const store = await load(STORE_FILE, { autoSave: true, defaults: {} });
  const history = await getCustomLlmEndpointHistory();
  const selectedBaseUrl = (await store.get<string>(LEGACY_BASE_URL_KEY)) ?? "";
  const selectedAuthType =
    ((await store.get<string>(LEGACY_AUTH_TYPE_KEY)) as CustomAuthType | null) ?? "none";

  // Backward-compatible migration: preserve the old single endpoint and seed
  // the new history list with it.
  if (selectedBaseUrl && !history.includes(normalizeBaseUrl(selectedBaseUrl))) {
    await appendToHistory(selectedBaseUrl);
  }

  await refreshHistoryUi().catch(() => {});

  return {
    baseUrl: normalizeBaseUrl(selectedBaseUrl),
    authType: selectedAuthType,
  };
}

export async function saveCustomLlmConfig(config: CustomLlmConfig): Promise<void> {
  const store = await load(STORE_FILE, { autoSave: true, defaults: {} });
  const baseUrl = normalizeBaseUrl(config.baseUrl);

  // Keep the existing active Custom config behavior for compatibility.
  await store.set(LEGACY_BASE_URL_KEY, baseUrl);
  await store.set(LEGACY_AUTH_TYPE_KEY, config.authType);

  // New behavior: every distinct endpoint is retained in history instead of
  // being lost when another Custom endpoint is configured.
  await appendToHistory(baseUrl);
  await refreshHistoryUi().catch(() => {});
}
