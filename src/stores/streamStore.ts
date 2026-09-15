import { create } from "zustand";
import type { AIResponse, IntelligenceMode, StreamSource } from "../lib/types";
import { stripThinkTags } from "../lib/utils";

function collapseExactDuplicate(text: string): string {
  const trimmed = text.trim();
  if (!trimmed) return text;
  const normalize = (value: string) => value.replace(/\s+/g, " ").trim().toLowerCase();
  const paragraphs = trimmed.split(/\n\s*\n/).map((part) => part.trim()).filter(Boolean);
  if (paragraphs.length >= 2 && paragraphs.length % 2 === 0) {
    const half = paragraphs.length / 2;
    if (paragraphs.slice(0, half).every((value, index) => normalize(value) === normalize(paragraphs[index + half]))) {
      return paragraphs.slice(0, half).join("\n\n");
    }
  }
  if (trimmed.length % 2 === 0) {
    const half = trimmed.length / 2;
    if (normalize(trimmed.slice(0, half)) === normalize(trimmed.slice(half))) return trimmed.slice(0, half).trim();
  }
  return trimmed;
}

interface StreamState {
  isStreaming: boolean;
  currentContent: string;
  _rawContent: string;
  currentMode: IntelligenceMode | null;
  currentModel: string;
  currentProvider: string;
  currentSources: StreamSource[];
  error: string | null;
  latencyMs: number | null;
  responseHistory: AIResponse[];
  pinnedResponses: AIResponse[];
  setStreaming: (streaming: boolean) => void;
  appendToken: (token: string) => void;
  startStream: (mode: IntelligenceMode, model: string, provider: string) => void;
  setSources: (sources: StreamSource[]) => void;
  endStream: (latencyMs: number) => void;
  setError: (error: string | null) => void;
  clearCurrent: () => void;
  pinResponse: (id: string) => void;
  unpinResponse: (id: string) => void;
}

export const useStreamStore = create<StreamState>((set, get) => ({
  isStreaming: false,
  currentContent: "",
  _rawContent: "",
  currentMode: null,
  currentModel: "",
  currentProvider: "",
  currentSources: [],
  error: null,
  latencyMs: null,
  responseHistory: [],
  pinnedResponses: [],

  setStreaming: (streaming) => set({ isStreaming: streaming }),
  appendToken: (token) => set((state) => {
    const raw = state._rawContent + token;
    return { _rawContent: raw, currentContent: stripThinkTags(raw) };
  }),
  startStream: (mode, model, provider) => set({
    isStreaming: true, currentContent: "", _rawContent: "", currentMode: mode,
    currentModel: model, currentProvider: provider, currentSources: [], error: null, latencyMs: null,
  }),
  setSources: (sources) => set({ currentSources: sources }),
  endStream: (latencyMs) => {
    const state = get();
    const content = collapseExactDuplicate(stripThinkTags(state._rawContent));
    const response: AIResponse = {
      id: crypto.randomUUID(), content, mode: state.currentMode!, timestamp: Date.now(), pinned: false,
      model: state.currentModel, provider: state.currentProvider, latency_ms: latencyMs,
      sources: state.currentSources.length > 0 ? state.currentSources : undefined,
    };
    set((s) => ({ isStreaming: false, currentContent: content, latencyMs, responseHistory: [response, ...s.responseHistory].slice(0, 5) }));
  },
  setError: (error) => set({ error, isStreaming: false }),
  clearCurrent: () => set({ currentContent: "", _rawContent: "", currentMode: null, currentModel: "", currentProvider: "", currentSources: [], error: null, latencyMs: null }),
  pinResponse: (id) => {
    const state = get();
    const response = state.responseHistory.find((r) => r.id === id);
    if (response && !state.pinnedResponses.find((r) => r.id === id)) set({ pinnedResponses: [...state.pinnedResponses, { ...response, pinned: true }] });
  },
  unpinResponse: (id) => set((state) => ({ pinnedResponses: state.pinnedResponses.filter((r) => r.id !== id) })),
}));
