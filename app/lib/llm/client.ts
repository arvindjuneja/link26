// Client-side LLM access. Always degrade gracefully to baked content: if the
// server route is unconfigured (no key) or errors, this returns null and the
// caller uses the baked pack. The free tier is genuinely free-to-run.

import type { LlmUseCase } from "@/app/lib/llm/models";

// Flip to true once the Worker/API key is wired. Until then baked content is the
// single source of truth and no network call to the LLM proxy is attempted.
export const LLM_ENABLED = false;

export async function llmGenerate(usecase: LlmUseCase, prompt: string): Promise<string | null> {
  if (!LLM_ENABLED) return null;
  try {
    const res = await fetch(`/api/llm/${usecase}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ prompt }),
    });
    if (!res.ok) return null;
    const data = (await res.json()) as { text?: string | null };
    return typeof data.text === "string" ? data.text : null;
  } catch {
    return null;
  }
}
