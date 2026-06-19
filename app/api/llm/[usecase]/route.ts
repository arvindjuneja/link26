// The LLM proxy — the key boundary. The Anthropic key lives only here (a server
// secret / Cloudflare secret), never in the client. Inert until the key is set:
// returns 503 {configured:false} so the client falls back to baked content.
//
// Before enabling in production, add (per docs/GAME_DESIGN.md §8):
//   - Supabase JWT validation (paid License gate)
//   - per-account + global daily token budget in Cloudflare KV (circuit breaker)
//   - response caching by (usecase, normalized prompt)

import { NextRequest, NextResponse } from "next/server";
import { MAX_OUTPUT_TOKENS, USECASE_MODEL, type LlmUseCase } from "@/app/lib/llm/models";

export const runtime = "nodejs";

export async function POST(
  req: NextRequest,
  context: { params: Promise<{ usecase: string }> }
) {
  const key = process.env.ANTHROPIC_API_KEY;
  if (!key) {
    // Not configured — the client falls back to the baked content pack.
    return NextResponse.json({ configured: false, text: null }, { status: 503 });
  }

  const { usecase } = await context.params;
  const model = USECASE_MODEL[usecase as LlmUseCase] ?? USECASE_MODEL.handler;
  const body = (await req.json().catch(() => ({}))) as { prompt?: string };
  const prompt = String(body.prompt ?? "").slice(0, 4000);
  if (!prompt) {
    return NextResponse.json({ configured: true, text: null, error: "empty prompt" }, { status: 400 });
  }

  try {
    const resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": key,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model,
        max_tokens: MAX_OUTPUT_TOKENS,
        messages: [{ role: "user", content: prompt }],
      }),
    });
    if (!resp.ok) {
      return NextResponse.json(
        { configured: true, text: null, error: `upstream ${resp.status}` },
        { status: 502 }
      );
    }
    const data = (await resp.json()) as { content?: Array<{ text?: string }> };
    const text = data?.content?.[0]?.text ?? null;
    return NextResponse.json({ configured: true, text });
  } catch (e) {
    return NextResponse.json(
      { configured: true, text: null, error: e instanceof Error ? e.message : "fetch failed" },
      { status: 502 }
    );
  }
}
