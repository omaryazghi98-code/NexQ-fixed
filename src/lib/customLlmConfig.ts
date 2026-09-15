import { invoke } from "@tauri-apps/api/core";
import { load } from "@tauri-apps/plugin-store";

export type CustomAuthType = "none" | "bearer" | "api_key";

export interface CustomLlmConfig {
  baseUrl: string;
  authType: CustomAuthType;
}

export interface CustomLlmEndpointProfile extends CustomLlmConfig {
  id: string;
  label: string;
}

const STORE_FILE = "config.json";
const HISTORY_KEY = "customLlmEndpointHistory";
const PROFILES_KEY = "customLlmEndpointProfiles";
const LEGACY_BASE_URL_KEY = "customLlmBaseUrl";
const LEGACY_AUTH_TYPE_KEY = "customLlmAuthType";
const MAX_HISTORY = 25;
const HISTORY_UI_ID = "nexq-custom-endpoint-history";

function normalizeBaseUrl(value: string): string {
  return value.trim().replace(/\/+$/, "");
}

export function getCustomLlmProfileId(baseUrl: string): string {
  const value = normalizeBaseUrl(baseUrl);
  // Stable, non-secret FNV-1a hash. Used only as a keychain namespace.
  let hash = 2166136261;
  for (let i = 0; i < value.length; i += 1) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return `custom_profile_${(hash >>> 0).toString(16).padStart(8, "0")}`;
}

function endpointLabel(baseUrl: string): string {
  try {
    return new URL(baseUrl).host || baseUrl;
  } catch {
    return baseUrl;
  }
}

async function getStore() {
  return load(STORE_FILE, { autoSave: true, defaults: {} });
}

export async function getCustomLlmEndpointHistory(): Promise<string[]> {
  const store = await getStore();
  const saved = await store.get<unknown>(HISTORY_KEY);
  if (!Array.isArray(saved)) return [];
  return saved
    .filter((value): value is string => typeof value === "string" && value.trim().length > 0)
    .map(normalizeBaseUrl)
    .filter(Boolean)
    .slice(0, MAX_HISTORY);
}

export async function getCustomLlmEndpointProfiles(): Promise<CustomLlmEndpointProfile[]> {
  const store = await getStore();
  const savedProfiles = await store.get<unknown>(PROFILES_KEY);
  const profileMap = new Map<string, CustomLlmEndpointProfile>();

  if (Array.isArray(savedProfiles)) {
    for (const raw of savedProfiles) {
      if (!raw || typeof raw !== "object") continue;
      const item = raw as Record<string, unknown>;
      const baseUrl = typeof item.baseUrl === "string" ? normalizeBaseUrl(item.baseUrl) : "";
      if (!baseUrl) continue;
      const authType = item.authType === "bearer" || item.authType === "api_key" ? item.authType : "none";
      const id = getCustomLlmProfileId(baseUrl);
      profileMap.set(baseUrl, {
        id,
        baseUrl,
        authType,
        label: typeof item.label === "string" && item.label.trim() ? item.label.trim() : endpointLabel(baseUrl),
      });
    }
  }

  // Backward-compatible migration from the original URL-only history.
  const history = await getCustomLlmEndpointHistory();
  for (const baseUrl of history) {
    if (!profileMap.has(baseUrl)) {
      profileMap.set(baseUrl, {
        id: getCustomLlmProfileId(baseUrl),
        baseUrl,
        authType: "none",
        label: endpointLabel(baseUrl),
      });
    }
  }

  return [...profileMap.values()].slice(0, MAX_HISTORY);
}

async function saveProfiles(profiles: CustomLlmEndpointProfile[]): Promise<void> {
  const store = await getStore();
  await store.set(
    PROFILES_KEY,
    profiles.slice(0, MAX_HISTORY).map(({ id, baseUrl, authType, label }) => ({ id, baseUrl, authType, label }))
  );
  await store.set(HISTORY_KEY, profiles.slice(0, MAX_HISTORY).map((profile) => profile.baseUrl));
}

async function appendToHistory(baseUrl: string, authType: CustomAuthType): Promise<void> {
  const normalized = normalizeBaseUrl(baseUrl);
  if (!normalized) return;

  const profiles = await getCustomLlmEndpointProfiles();
  const existing = profiles.find((profile) => profile.baseUrl === normalized);
  const profile: CustomLlmEndpointProfile = {
    id: getCustomLlmProfileId(normalized),
    baseUrl: normalized,
    authType,
    label: existing?.label || endpointLabel(normalized),
  };
  const updated = [profile, ...profiles.filter((item) => item.baseUrl !== normalized)];
  await saveProfiles(updated);
}

async function getKeychainKey(provider: string): Promise<string | null> {
  try {
    return await invoke<string | null>("get_api_key", { provider });
  } catch {
    return null;
  }
}

async function storeKeychainKey(provider: string, key: string): Promise<void> {
  try {
    await invoke("store_api_key", { provider, key });
  } catch {
    // Credential storage is best-effort here; existing UI handling still reports failures.
  }
}

export async function getCustomLlmEndpointKey(baseUrl: string): Promise<string | null> {
  return getKeychainKey(getCustomLlmProfileId(baseUrl));
}

export async function selectCustomLlmEndpoint(baseUrl: string): Promise<CustomLlmConfig> {
  const store = await getStore();
  const normalized = normalizeBaseUrl(baseUrl);
  const profiles = await getCustomLlmEndpointProfiles();
  const profile = profiles.find((item) => item.baseUrl === normalized);
  const authType = profile?.authType ?? "none";

  await store.set(LEGACY_BASE_URL_KEY, normalized);
  await store.set(LEGACY_AUTH_TYPE_KEY, authType);

  const key = await getCustomLlmEndpointKey(normalized);
  if (key) {
    await storeKeychainKey("custom", key);
  }

  return { baseUrl: normalized, authType };
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
  const store = await getStore();
  const selectedBaseUrl = (await store.get<string>(LEGACY_BASE_URL_KEY)) ?? "";
  const selectedAuthType =
    ((await store.get<string>(LEGACY_AUTH_TYPE_KEY)) as CustomAuthType | null) ?? "none";

  if (selectedBaseUrl) {
    await appendToHistory(selectedBaseUrl, selectedAuthType);
  }

  await refreshHistoryUi().catch(() => {});

  return {
    baseUrl: normalizeBaseUrl(selectedBaseUrl),
    authType: selectedAuthType,
  };
}

export async function saveCustomLlmConfig(config: CustomLlmConfig): Promise<void> {
  const store = await getStore();
  const baseUrl = normalizeBaseUrl(config.baseUrl);

  // Keep the existing active Custom config behavior for compatibility.
  await store.set(LEGACY_BASE_URL_KEY, baseUrl);
  await store.set(LEGACY_AUTH_TYPE_KEY, config.authType);

  // New behavior: every distinct endpoint is retained as a named profile.
  await appendToHistory(baseUrl, config.authType);

  // Copy the currently stored Custom credential into an endpoint-specific
  // keychain entry so multiple endpoints can retain different secrets.
  const legacyKey = await getKeychainKey("custom");
  if (legacyKey && baseUrl) {
    await storeKeychainKey(getCustomLlmProfileId(baseUrl), legacyKey);
  }

  await refreshHistoryUi().catch(() => {});
}
