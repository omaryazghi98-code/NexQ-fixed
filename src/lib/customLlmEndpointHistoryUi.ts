import {
  getCustomLlmEndpointKey,
  getCustomLlmEndpointProfiles,
  saveCustomLlmConfig,
  selectCustomLlmEndpoint,
} from "./customLlmConfig";
import { storeApiKey } from "./ipc";

const BASE_URL_PLACEHOLDER = "http://localhost:8080/v1";
const ADD_MARKER = "data-nexq-add-custom-provider";
const CARD_MARKER = "data-nexq-custom-provider";

function normalize(value: string): string {
  return value.trim().replace(/\/+$/, "");
}

function setControlledInputValue(input: HTMLInputElement, value: string): void {
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")?.set;
  setter?.call(input, value);
  input.dispatchEvent(new Event("input", { bubbles: true }));
  input.dispatchEvent(new Event("change", { bubbles: true }));
}

function setControlledSelectValue(select: HTMLSelectElement, value: string): void {
  select.value = value;
  select.dispatchEvent(new Event("change", { bubbles: true }));
}

function findCustomCard(input: HTMLInputElement): HTMLElement | null {
  let node: HTMLElement | null = input.parentElement;
  for (let i = 0; node && i < 8; i += 1) {
    if (node.querySelector("select")) return node;
    node = node.parentElement;
  }
  return null;
}

function findProviderGrid(input: HTMLInputElement): HTMLElement | null {
  let node: HTMLElement | null = input.parentElement;
  for (let i = 0; node && i < 12; i += 1) {
    if (node.classList.contains("grid-cols-4") && node.querySelectorAll("button").length >= 8) return node;
    node = node.parentElement;
  }
  return null;
}

async function currentValues(): Promise<{ baseUrl: string; authType: "none" | "bearer" | "api_key"; authValue: string }> {
  const input = document.querySelector<HTMLInputElement>(`input[placeholder="${BASE_URL_PLACEHOLDER}"]`);
  if (!input) return { baseUrl: "", authType: "none", authValue: "" };
  const card = findCustomCard(input);
  const selects = card ? Array.from(card.querySelectorAll("select")) : [];
  const authSelect = selects.find((select) => Array.from(select.options).some((o) => ["none", "bearer", "api_key"].includes(o.value)));
  const authType = authSelect?.value === "bearer" || authSelect?.value === "api_key" ? authSelect.value : "none";
  const token = card ? Array.from(card.querySelectorAll<HTMLInputElement>('input[type="password"]')).find((field) => field !== input) : undefined;
  return { baseUrl: normalize(input.value), authType, authValue: token?.value || "" };
}

async function mountAddButton(): Promise<void> {
  const input = document.querySelector<HTMLInputElement>(`input[placeholder="${BASE_URL_PLACEHOLDER}"]`);
  if (!input) return;
  const card = findCustomCard(input);
  if (!card || card.querySelector(`[${ADD_MARKER}]`)) return;

  const button = document.createElement("button");
  button.type = "button";
  button.setAttribute(ADD_MARKER, "true");
  button.className = "mt-3 inline-flex items-center rounded-lg border border-primary/30 bg-primary/5 px-3.5 py-2 text-xs font-medium text-primary hover:bg-primary/10 cursor-pointer";
  button.textContent = "Add as provider";

  button.addEventListener("click", async () => {
    const values = await currentValues();
    if (!values.baseUrl) return;
    try {
      if (values.authType !== "none" && values.authValue) await storeApiKey("custom", values.authValue);
      await saveCustomLlmConfig({ baseUrl: values.baseUrl, authType: values.authType });
      await renderProviderCards();
      button.textContent = "Added ✓";
      window.setTimeout(() => { button.textContent = "Add as provider"; }, 1400);
    } catch (error) {
      console.warn("[CustomEndpointProviders] add failed", error);
    }
  });

  card.appendChild(button);
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>\"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" }[c] || c));
}

async function applyProfile(profile: { baseUrl: string; authType: "none" | "bearer" | "api_key" }): Promise<void> {
  const input = document.querySelector<HTMLInputElement>(`input[placeholder="${BASE_URL_PLACEHOLDER}"]`);
  if (!input) return;
  const card = findCustomCard(input);
  setControlledInputValue(input, profile.baseUrl);
  if (card) {
    const authSelect = Array.from(card.querySelectorAll("select")).find((select) => Array.from(select.options).some((o) => ["none", "bearer", "api_key"].includes(o.value)));
    if (authSelect) setControlledSelectValue(authSelect, profile.authType);
    const token = Array.from(card.querySelectorAll<HTMLInputElement>('input[type="password"]')).find((field) => field !== input);
    if (token) setControlledInputValue(token, (await getCustomLlmEndpointKey(profile.baseUrl)) || "");
  }
  await selectCustomLlmEndpoint(profile.baseUrl);
}

async function renderProviderCards(): Promise<void> {
  const input = document.querySelector<HTMLInputElement>(`input[placeholder="${BASE_URL_PLACEHOLDER}"]`);
  if (!input) return;
  const grid = findProviderGrid(input);
  if (!grid) return;
  const profiles = await getCustomLlmEndpointProfiles();
  const existing = new Set(Array.from(grid.querySelectorAll<HTMLElement>(`[${CARD_MARKER}]`)).map((el) => el.dataset.nexqCustomProvider || ""));
  for (const profile of profiles) {
    if (existing.has(profile.baseUrl)) continue;
    const button = document.createElement("button");
    button.type = "button";
    button.setAttribute(CARD_MARKER, "true");
    button.dataset.nexqCustomProvider = profile.baseUrl;
    button.className = "relative flex min-h-[108px] flex-col items-start rounded-xl border border-border/50 p-3 text-left transition-all duration-150 hover:border-border hover:bg-accent/50 cursor-pointer";
    button.innerHTML = `<div class="absolute -top-1 -right-1"><div class="h-2.5 w-2.5 rounded-full bg-success ring-2 ring-card"></div></div><div class="flex w-full items-center gap-1.5"><span class="text-xs font-medium truncate">Custom · ${escapeHtml(profile.label)}</span></div><span class="mt-0.5 text-meta text-muted-foreground line-clamp-2 break-all">${escapeHtml(profile.baseUrl)}</span><span class="mt-1.5 inline-flex items-center rounded-full border px-1.5 py-0.5 text-meta font-medium bg-success/10 text-success border-success/20">Saved</span>`;
    button.addEventListener("click", () => applyProfile(profile).catch((error) => console.warn("[CustomEndpointProviders] select failed", error)));
    grid.appendChild(button);
  }
}

let scheduled = false;
function scheduleMount(): void {
  if (scheduled) return;
  scheduled = true;
  window.setTimeout(() => {
    scheduled = false;
    mountAddButton().catch(() => {});
    renderProviderCards().catch(() => {});
  }, 75);
}

if (typeof window !== "undefined" && typeof document !== "undefined") {
  const observer = new MutationObserver(scheduleMount);
  const start = () => {
    if (!document.body) return;
    observer.observe(document.body, { childList: true, subtree: true });
    scheduleMount();
  };
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start, { once: true });
  else start();
}
