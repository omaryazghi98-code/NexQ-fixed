import { load } from "@tauri-apps/plugin-store";

export type CustomAuthType = "none" | "bearer" | "api_key";

export interface CustomLlmConfig {
  baseUrl: string;
  authType: CustomAuthType;
}

const STORE_FILE = "config.json";

export async function getCustomLlmConfig(): Promise<CustomLlmConfig> {
  const store = await load(STORE_FILE, { autoSave: true, defaults: {} });
  return {
    baseUrl: (await store.get<string>("customLlmBaseUrl")) ?? "",
    authType: ((await store.get<string>("customLlmAuthType")) as CustomAuthType | null) ?? "none",
  };
}

export async function saveCustomLlmConfig(config: CustomLlmConfig): Promise<void> {
  const store = await load(STORE_FILE, { autoSave: true, defaults: {} });
  await store.set("customLlmBaseUrl", config.baseUrl.trim().replace(/\/+$/, ""));
  await store.set("customLlmAuthType", config.authType);
}
