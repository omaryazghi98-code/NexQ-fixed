// Sub-PRD 5: User-configured custom endpoint with auto-detect SSE/NDJSON

use futures::StreamExt;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::time::Instant;
use tauri::Emitter;

use super::provider::{
    CompletionStats, GenerationParams, LLMError, LLMMessage, LLMProvider, ModelInfo,
    StreamEndPayload, StreamTokenPayload,
};
use super::stream_parser::{LineBuffer, NDJSONParser, SSEParser};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum CustomAuthType {
    None,
    Bearer,
    ApiKey,
}

#[derive(Debug, Clone)]
pub struct CustomConfig {
    pub base_url: String,
    pub auth_type: CustomAuthType,
    pub auth_value: Option<String>,
    pub auth_header: Option<String>,
}

pub struct CustomClient {
    config: CustomConfig,
    client: reqwest::Client,
}

impl CustomClient {
    pub fn new(mut config: CustomConfig) -> Self {
        // Accept either a base /v1 URL or a pasted endpoint URL such as
        // /responses or /chat/completions. Normalize it once here so the
        // provider can safely build the appropriate endpoint internally.
        config.base_url = config.base_url.trim_end_matches('/').to_string();
        for suffix in ["/responses", "/chat/completions"] {
            if config.base_url.ends_with(suffix) {
                config.base_url.truncate(config.base_url.len() - suffix.len());
                break;
            }
        }
        Self {
            config,
            client: reqwest::Client::new(),
        }
    }

    fn is_azure_foundry(&self) -> bool {
        self.config.base_url.contains(".services.ai.azure.com")
            || self.config.base_url.contains(".openai.azure.com")
    }

    fn uses_responses_api(&self) -> bool {
        // Current Azure AI Foundry resource/project endpoints expose the
        // OpenAI v1 Responses API. Keep the OpenAI resource endpoint path on
        // the chat-compatible path unless the newer Foundry services endpoint
        // is detected explicitly.
        self.config.base_url.contains(".services.ai.azure.com")
    }

    /// Apply authentication to a request based on the configured auth type.
    fn apply_auth(&self, builder: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
        match &self.config.auth_type {
            CustomAuthType::None => builder,
            CustomAuthType::Bearer => {
                if let Some(ref token) = self.config.auth_value {
                    builder.header("Authorization", format!("Bearer {}", token))
                } else {
                    builder
                }
            }
            CustomAuthType::ApiKey => {
                // Azure OpenAI / Foundry API-key authentication uses the
                // `api-key` header. Other custom endpoints retain x-api-key
                // as the existing default unless the caller supplies a header.
                let header = self
                    .config
                    .auth_header
                    .as_deref()
                    .or_else(|| self.is_azure_foundry().then_some("api-key"))
                    .unwrap_or("x-api-key");
                if let Some(ref key) = self.config.auth_value {
                    builder.header(header, key.as_str())
                } else {
                    builder
                }
            }
        }
    }

    /// Detect whether a stream is SSE or NDJSON and parse tokens accordingly.
    /// Returns (token_text, is_done).
    fn try_extract_token(line: &str) -> Vec<(Option<String>, bool)> {
        let mut results = Vec::new();

        // Try SSE format first
        let sse_events = SSEParser::parse_chunk(line);
        if !sse_events.is_empty() {
            for event in sse_events {
                match event {
                    Some(data) => {
                        // OpenAI Responses API streaming event. This is used
                        // by current Azure Foundry `.../openai/v1/responses`.
                        if data
                            .get("type")
                            .and_then(|t| t.as_str())
                            == Some("response.output_text.delta")
                        {
                            if let Some(delta) = data.get("delta").and_then(|d| d.as_str()) {
                                results.push((Some(delta.to_string()), false));
                                continue;
                            }
                        }

                        if data
                            .get("type")
                            .and_then(|t| t.as_str())
                            == Some("response.completed")
                        {
                            results.push((None, true));
                            continue;
                        }

                        // Try OpenAI-compatible chat completions format
                        if let Some(token) = SSEParser::extract_openai_token(&data) {
                            results.push((Some(token), false));
                            continue;
                        }
                        // Try Anthropic format
                        if let Some(token) = SSEParser::extract_anthropic_token(&data) {
                            results.push((Some(token), false));
                            continue;
                        }
                        // Try Gemini format
                        if let Some(token) = SSEParser::extract_gemini_token(&data) {
                            results.push((Some(token), false));
                            continue;
                        }
                        // Unknown SSE format - try generic text extraction
                        if let Some(text) = data.get("text").and_then(|t| t.as_str()) {
                            results.push((Some(text.to_string()), false));
                            continue;
                        }
                        if let Some(content) = data.get("content").and_then(|t| t.as_str()) {
                            results.push((Some(content.to_string()), false));
                        }
                    }
                    None => {
                        // [DONE]
                        results.push((None, true));
                    }
                }
            }
            return results;
        }

        // Try NDJSON format
        let ndjson_events = NDJSONParser::parse_chunk(line);
        for data in ndjson_events {
            if NDJSONParser::is_ollama_done(&data) {
                results.push((None, true));
                continue;
            }
            // Try Ollama format
            if let Some(token) = NDJSONParser::extract_ollama_token(&data) {
                results.push((Some(token), false));
                continue;
            }
            // Try generic extraction
            if let Some(text) = data.get("text").and_then(|t| t.as_str()) {
                results.push((Some(text.to_string()), false));
                continue;
            }
            if let Some(content) = data.get("content").and_then(|t| t.as_str()) {
                results.push((Some(content.to_string()), false));
                continue;
            }
            // Try OpenAI format in NDJSON (some servers do this)
            if let Some(token) = SSEParser::extract_openai_token(&data) {
                results.push((Some(token), false));
            }
        }

        results
    }
}

#[async_trait::async_trait]
impl LLMProvider for CustomClient {
    fn provider_name(&self) -> &str {
        "custom"
    }

    async fn list_models(&self) -> Result<Vec<ModelInfo>, LLMError> {
        // Try OpenAI-compatible /models endpoint
        let url = format!("{}/models", self.config.base_url);
        let request = self.apply_auth(self.client.get(&url));

        match request.send().await {
            Ok(response) if response.status().is_success() => {
                let body: serde_json::Value = response.json().await?;
                let mut models = body
                    .get("data")
                    .and_then(|d| d.as_array())
                    .map(|arr| {
                        arr.iter()
                            .filter_map(|m| {
                                let id = m.get("id")?.as_str()?.to_string();
                                Some(ModelInfo {
                                    id: id.clone(),
                                    name: m
                                        .get("name")
                                        .and_then(|n| n.as_str())
                                        .unwrap_or(&id)
                                        .to_string(),
                                    provider: "custom".to_string(),
                                    context_window: None,
                                })
                            })
                            .collect::<Vec<_>>()
                    })
                    .unwrap_or_default();

                // Azure Foundry's /models endpoint exposes model IDs, while
                // inference requires the deployment name. Expose the known
                // NexQ fine-tuned deployment so it can be selected explicitly.
                if self.is_azure_foundry()
                    && !models.iter().any(|m| m.id == "nexq-interview")
                {
                    models.push(ModelInfo {
                        id: "nexq-interview".to_string(),
                        name: "nexq-interview (Azure deployment)".to_string(),
                        provider: "custom".to_string(),
                        context_window: None,
                    });
                }

                Ok(models)
            }
            _ => {
                // Try Ollama-compatible /api/tags endpoint
                let url = format!("{}/api/tags", self.config.base_url);
                let request = self.apply_auth(self.client.get(&url));

                match request.send().await {
                    Ok(response) if response.status().is_success() => {
                        let body: serde_json::Value = response.json().await?;
                        let models = body
                            .get("models")
                            .and_then(|m| m.as_array())
                            .map(|arr| {
                                arr.iter()
                                    .filter_map(|m| {
                                        let name = m.get("name")?.as_str()?.to_string();
                                        Some(ModelInfo {
                                            id: name.clone(),
                                            name: name.clone(),
                                            provider: "custom".to_string(),
                                            context_window: None,
                                        })
                                    })
                                    .collect()
                            })
                            .unwrap_or_default();
                        Ok(models)
                    }
                    _ => {
                        // Return empty list - user can type model name manually
                        if self.is_azure_foundry() {
                            Ok(vec![ModelInfo {
                                id: "nexq-interview".to_string(),
                                name: "nexq-interview (Azure deployment)".to_string(),
                                provider: "custom".to_string(),
                                context_window: None,
                            }])
                        } else {
                            Ok(vec![])
                        }
                    }
                }
            }
        }
    }

    async fn test_connection(&self) -> Result<bool, LLMError> {
        // Try /models first (OpenAI-compat)
        let url = format!("{}/models", self.config.base_url);
        let request = self.apply_auth(self.client.get(&url));
        if let Ok(resp) = request.send().await {
            if resp.status().is_success() {
                return Ok(true);
            }
        }

        // Try /api/tags (Ollama-compat)
        let url = format!("{}/api/tags", self.config.base_url);
        let request = self.apply_auth(self.client.get(&url));
        if let Ok(resp) = request.send().await {
            if resp.status().is_success() {
                return Ok(true);
            }
        }

        // Try a simple GET to the base URL
        let request = self.apply_auth(self.client.get(&self.config.base_url));
        match request.send().await {
            Ok(resp) => Ok(resp.status().is_success()),
            Err(_) => Ok(false),
        }
    }

    async fn stream_completion(
        &self,
        messages: Vec<LLMMessage>,
        model: &str,
        params: GenerationParams,
        app_handle: tauri::AppHandle,
    ) -> Result<CompletionStats, LLMError> {
        let start = Instant::now();

        let msgs: Vec<serde_json::Value> = messages
            .iter()
            .map(|m| {
                json!({
                    "role": m.role,
                    "content": m.content
                })
            })
            .collect();

        let (url, body) = if self.uses_responses_api() {
            let url = format!("{}/responses", self.config.base_url);
            let mut body = json!({
                "model": model,
                "input": msgs,
                "stream": true
            });
            if let Some(max_tok) = params.max_tokens {
                body["max_output_tokens"] = json!(max_tok);
            }
            (url, body)
        } else {
            // OpenAI-compatible chat completions endpoint.
            let url = format!("{}/chat/completions", self.config.base_url);
            let mut body = json!({
                "model": model,
                "messages": msgs,
                "stream": true
            });
            if let Some(temp) = params.temperature {
                body["temperature"] = json!(temp);
            }
            if let Some(max_tok) = params.max_tokens {
                body["max_tokens"] = json!(max_tok);
            }
            (url, body)
        };

        let mut request = self
            .apply_auth(self.client.post(&url))
            .header("Content-Type", "application/json");
        if self.config.base_url.contains("router.requesty.ai") {
            request = request
                .header("HTTP-Referer", "https://github.com/omaryazghi98-code/NexQ-fixed")
                .header("X-Title", "NexQ");
        }
        let request = request.json(&body);

        let response = request.send().await.map_err(|e| {
            let _ = app_handle.emit("llm_stream_error", e.to_string());
            LLMError::ConnectionFailed(format!(
                "Failed to connect to custom endpoint {}: {}",
                url, e
            ))
        })?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            let err_msg = format!(
                "Custom endpoint request failed ({}): {}",
                status, body
            );
            let _ = app_handle.emit("llm_stream_error", &err_msg);
            return Err(LLMError::ProviderError(err_msg));
        }

        let mut stream = response.bytes_stream();
        let mut line_buffer = LineBuffer::new();
        let mut token_count: u64 = 0;

        while let Some(chunk_result) = stream.next().await {
            let chunk = chunk_result.map_err(|e| {
                let _ = app_handle.emit("llm_stream_error", e.to_string());
                LLMError::HttpError(e)
            })?;

            let chunk_str = String::from_utf8_lossy(&chunk);
            let lines = line_buffer.push(&chunk_str);

            for line in lines {
                let extractions = Self::try_extract_token(&line);
                for (maybe_token, _is_done) in extractions {
                    if let Some(token) = maybe_token {
                        if !token.is_empty() {
                            token_count += 1;
                            let _ = app_handle.emit(
                                "llm_stream_token",
                                StreamTokenPayload {
                                    token: token.clone(),
                                },
                            );
                        }
                    }
                }
            }
        }

        // Flush remaining
        if let Some(remaining) = line_buffer.flush() {
            let extractions = Self::try_extract_token(&remaining);
            for (maybe_token, _is_done) in extractions {
                if let Some(token) = maybe_token {
                    if !token.is_empty() {
                        token_count += 1;
                        let _ = app_handle.emit(
                            "llm_stream_token",
                            StreamTokenPayload {
                                token: token.clone(),
                            },
                        );
                    }
                }
            }
        }

        let latency_ms = start.elapsed().as_millis() as u64;
        let stats = CompletionStats {
            prompt_tokens: 0,
            completion_tokens: token_count,
            total_tokens: token_count,
            latency_ms,
        };

        let _ = app_handle.emit(
            "llm_stream_end",
            StreamEndPayload {
                total_tokens: token_count,
                latency_ms,
            },
        );

        Ok(stats)
    }
}
