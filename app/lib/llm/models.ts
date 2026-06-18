// Claude model tiering for in-game LLM use (see docs/GAME_DESIGN.md §8).
// The free tier runs entirely on the baked content pack; live generation is the
// paid delighter. These ids are wired but inert until ANTHROPIC_API_KEY is set
// on the server (the Worker), so no key ever reaches the client.

export const LLM_MODELS = {
  cheap: "claude-haiku-4-5", // NPC chatter, ambient flavor, host banners
  workhorse: "claude-sonnet-4-6", // mission generation, analyst-call grading
  marquee: "claude-opus-4-8", // campaign set-piece beats only
} as const;

export type LlmUseCase = "handler" | "mission" | "analyst";

export const USECASE_MODEL: Record<LlmUseCase, string> = {
  handler: LLM_MODELS.cheap,
  mission: LLM_MODELS.workhorse,
  analyst: LLM_MODELS.workhorse,
};

// Hard per-request output cap (cost guard). Per-account/global daily budgets and
// caching live in the Worker (Cloudflare KV) when this is enabled.
export const MAX_OUTPUT_TOKENS = 400;
