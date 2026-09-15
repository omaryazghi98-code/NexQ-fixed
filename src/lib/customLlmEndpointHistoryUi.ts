import {
  getCustomLlmEndpointKey,
  getCustomLlmEndpointProfiles,
  selectCustomLlmEndpoint,
} from "./customLlmConfig";

const BASE_URL_PLACEHOLDER = "http://localhost:8080/v1";
const UI_MARKER = "data-nexq-custom-endpoint-picker";

function setControlledInputValue(input: HTMLInputElement, value: string): void {
  const setter = Object.getOwnPropertyDescriptor(
    HTMLInputElement.prototype,
    "value"
  )?.set;
  setter?.call(input, value);
  input.dispatchEvent(new Event("input", { bubbles: true }));
  input.dispatchEvent(new Event("change", { bubbles: true }));
}

function setControlledSelectValue(select: HTMLSelectElement, value: string): void {
  select.value = value;
  select.dispatchEvent(new Event("change", { bubbles: true }));
}

function findCustomCard(input: HTMLInputElement): HTMLElement | null {
  // The Custom Provider card contains the base URL input, auth select and
  // optional token input. Walk upward until we find at least one select.
  let node: HTMLElement | null = input.parentElement;
  for (let i = 0; node && i < 5; i += 1) {
    if (node.querySelector("select")) return node;
    node = node.parentElement;
  }
  return null;
}

async function applyProfile(baseUrl: string): Promise<void> {
  const input = document.querySelector<HTMLInputElement>(
    `input[placeholder="${BASE_URL_PLACEHOLDER}"]`
  );
  if (!input) return;

  const profile = await selectCustomLlmEndpoint(baseUrl);
  setControlledInputValue(input, profile.baseUrl);

  const card = findCustomCard(input);
  if (!card) return;

  const authSelect = Array.from(card.querySelectorAll("select")).find((select) =>
    Array.from(select.options).some((option) =>
      ["none", "bearer", "api_key"].includes(option.value)
    )
  );
  if (authSelect) setControlledSelectValue(authSelect, profile.authType);

  if (profile.authType !== "none") {
    const tokenInput = Array.from(card.querySelectorAll<HTMLInputElement>('input[type="password"]'))
      .find((field) => field !== input);
    if (tokenInput) {
      const key = await getCustomLlmEndpointKey(profile.baseUrl);
      if (key) setControlledInputValue(tokenInput, key);
    }
  }
}

async function mountPicker(): Promise<void> {
  const input = document.querySelector<HTMLInputElement>(
    `input[placeholder="${BASE_URL_PLACEHOLDER}"]`
  );
  if (!input) return;
  if (input.parentElement?.querySelector(`[${UI_MARKER}]`)) return;

  const card = findCustomCard(input);
  if (!card) return;

  const wrapper = document.createElement("div");
  wrapper.setAttribute(UI_MARKER, "true");
  wrapper.className = "mb-3";

  const label = document.createElement("label");
  label.textContent = "Saved endpoints";
  label.className = "mb-1.5 block text-xs font-medium text-foreground";

  const select = document.createElement("select");
  select.className =
    "w-full rounded-lg border border-border/50 bg-background px-3.5 py-2.5 text-sm text-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary/20 cursor-pointer";

  const placeholder = document.createElement("option");
  placeholder.value = "";
  placeholder.textContent = "Select a saved endpoint...";
  select.appendChild(placeholder);

  const profiles = await getCustomLlmEndpointProfiles();
  for (const profile of profiles) {
    const option = document.createElement("option");
    option.value = profile.baseUrl;
    option.textContent = `${profile.label} — ${profile.baseUrl}`;
    select.appendChild(option);
  }

  const current = input.value.trim().replace(/\/+$/, "");
  if (current && profiles.some((profile) => profile.baseUrl === current)) {
    select.value = current;
  }

  select.addEventListener("change", () => {
    const value = select.value;
    if (!value) return;
    applyProfile(value).catch((error) => {
      console.warn("[CustomEndpointPicker] Failed to restore endpoint:", error);
    });
  });

  wrapper.appendChild(label);
  wrapper.appendChild(select);

  // Insert directly above the Base URL field without changing the React tree.
  const baseSection = input.closest("div")?.parentElement;
  if (baseSection?.parentElement) {
    baseSection.parentElement.insertBefore(wrapper, baseSection);
  } else {
    card.insertBefore(wrapper, card.firstChild);
  }
}

function observeSettingsDom(): void {
  if (typeof window === "undefined" || typeof document === "undefined") return;

  const observer = new MutationObserver(() => {
    mountPicker().catch(() => {});
  });

  const start = () => {
    if (!document.body) return;
    observer.observe(document.body, { childList: true, subtree: true });
    mountPicker().catch(() => {});
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start, { once: true });
  } else {
    start();
  }
}

observeSettingsDom();
