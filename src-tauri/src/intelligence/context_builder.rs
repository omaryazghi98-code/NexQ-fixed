// Sub-PRD 6: Assemble prompt per template with context resources
//
// Architecture: UNIVERSAL, data-driven prompt builder.
// - System message = per-action editable system prompt + composed instructions (tone/format/length/custom).
//   This is the ONLY instruction the LLM receives. Configured entirely from the settings page.
// - User message = data sections ONLY, each controlled by a per-action toggle:
//   1. Reference Materials (RAG chunks) — controlled by `include_context`
//   2. Meeting Transcript — controlled by `include_transcript`, windowed by caller
//   3. User's Question — always included when provided (user explicitly typed it)
//   4. Detected Question — controlled by `include_question`

use crate::llm::provider::LLMMessage;

use super::question_detector::DetectedQuestion;

const VERIFIED_CANDIDATE_FACTS: &str = "\
- Comdata: inbound/outbound telephone customer support; handled complex cases and escalated or coordinated with external/internal teams. Do not describe Comdata as chat support or multiple simultaneous chats.\
- Spotify: chat-only support; handled multiple concurrent live chats.\
- Epic Games/5CA: gaming/player support.\
- ENGIE: inbound telephone support; handled tense customer calls and stayed calm while working toward a solution.\
- Airalo: eSIM troubleshooting including ICCID, APN, and device compatibility.\
- Beerwulf: handled damaged or missing components and replacement/refund cases.\
- Never invent an employer, title, responsibility, tool, support channel, workload, achievement, metric, or experience. Never move a fact from one employer/project to another.\
Use these only when relevant; do not force them into unrelated answers.";

/// Builds the full prompt (list of LLMMessages) sent to the LLM.
pub struct ContextBuilder;

impl ContextBuilder {
    pub fn new() -> Self { Self }

    pub fn build_prompt_with_config(
        &self,
        system_prompt: &str,
        transcript_text: &str,
        question: Option<&DetectedQuestion>,
        context_text: &str,
        custom_question: Option<&str>,
        include_context: bool,
        include_transcript: bool,
        include_question: bool,
    ) -> Vec<LLMMessage> {
        let mut messages: Vec<LLMMessage> = Vec::new();
        messages.push(LLMMessage { role: "system".to_string(), content: system_prompt.to_string() });

        let mut user_parts: Vec<String> = Vec::new();
        if include_context && !context_text.is_empty() {
            user_parts.push(format!("## Reference Materials\n{}\n", context_text));
        }
        if include_transcript && !transcript_text.is_empty() {
            user_parts.push(format!("## Meeting Transcript (Recent)\n{}\n", transcript_text));
        }
        if let Some(q) = custom_question {
            if !q.is_empty() { user_parts.push(format!("## User's Question\n{}\n", q)); }
        }
        if include_question {
            if let Some(q) = question {
                user_parts.push(format!("## Detected Question (confidence: {:.0}%)\n{}\n", q.confidence * 100.0, q.text));
            }
        }
        if system_prompt.to_ascii_lowercase().contains("real-time response coach") {
            user_parts.push(format!("## Verified Candidate Facts\n{}\n", VERIFIED_CANDIDATE_FACTS));
        }

        messages.push(LLMMessage { role: "user".to_string(), content: user_parts.join("\n") });
        messages
    }
}
