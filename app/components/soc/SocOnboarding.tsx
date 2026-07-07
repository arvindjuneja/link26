"use client";

import { useEffect, useLayoutEffect, useState } from "react";

// A light first-shift coach — the blue-seat cousin of GuidedOnboarding, but tuned for
// an EXPLORATORY loop rather than a strict "type this command" tutorial. It GUIDES
// (a glowing ring on what to look at) without CAGING: no screen-dimming, everything
// stays clickable, and every step has an obvious way forward. Teaches the loop once:
// pull the right log → read the evidence → make the call.

export const SOC_ONBOARDING_DONE_KEY = "sentry_soc_onboarding_v1";
const DONE_KEY = SOC_ONBOARDING_DONE_KEY;

type Anchor = "sources" | "evidence" | "call";

interface Step {
  anchor: Anchor;
  title: string;
  body: string;
  /** auto-advance when this becomes true (a real action the player took) */
  done?: (s: { sourcesPulled: number; hasEvidence: boolean }) => boolean;
  /** or a manual "continue" button (for read-and-proceed steps that shouldn't gate) */
  button?: string;
}

const STEPS: Step[] = [
  {
    anchor: "sources",
    title: "Pull the log that answers the question",
    body: "Each source shows the question it answers — that's the skill. Start with the process tree: click it.",
    done: (s) => s.sourcesPulled >= 1,
  },
  {
    anchor: "evidence",
    title: "Read what actually happened",
    body: "Findings land here — the evidence, not the tool's 'High' guess. Pull more logs on the left if you're not sure. When you can justify a call, hit Got it.",
    button: "Got it ▸",
  },
  {
    anchor: "call",
    title: "Now make the call",
    body: "True Positive, False Positive, or Benign (authorized)? Pick one — you'll get a full debrief either way. (You can still pull more logs first.)",
    // terminal: SocConsole persists completion on the first real call; or dismiss here.
  },
];

export default function SocOnboarding({
  sourcesPulled,
  hasEvidence,
}: {
  sourcesPulled: number;
  hasEvidence: boolean;
}) {
  const [mounted, setMounted] = useState(false);
  const [dismissed, setDismissed] = useState(true);
  const [stepIndex, setStepIndex] = useState(0);
  const [rect, setRect] = useState<DOMRect | null>(null);
  const [vp, setVp] = useState({ w: 1440, h: 900 });

  useEffect(() => {
    setMounted(true);
    const finished = typeof window !== "undefined" && localStorage.getItem(DONE_KEY);
    setDismissed(Boolean(finished));
  }, []);

  const active = mounted && !dismissed;
  const step = STEPS[stepIndex];

  // Auto-advance only for steps with a `done` action (never gate on a hidden condition).
  useEffect(() => {
    if (!active) return;
    if (step?.done?.({ sourcesPulled, hasEvidence })) {
      setStepIndex((i) => Math.min(i + 1, STEPS.length - 1));
    }
  }, [active, step, sourcesPulled, hasEvidence]);

  // Measure the highlighted element; keep aligned as panels resize.
  useLayoutEffect(() => {
    if (!active) return;
    const measure = () => {
      setVp({ w: window.innerWidth, h: window.innerHeight });
      const el = document.querySelector(`[data-soc="${step.anchor}"]`);
      setRect(el ? el.getBoundingClientRect() : null);
    };
    measure();
    const id = window.setInterval(measure, 250);
    window.addEventListener("resize", measure);
    window.addEventListener("scroll", measure, true);
    return () => {
      window.clearInterval(id);
      window.removeEventListener("resize", measure);
      window.removeEventListener("scroll", measure, true);
    };
  }, [active, step.anchor, stepIndex]);

  if (!active) return null;

  const next = () => setStepIndex((i) => Math.min(i + 1, STEPS.length - 1));
  const finish = () => {
    try {
      localStorage.setItem(DONE_KEY, "1");
    } catch {
      /* ignore */
    }
    setDismissed(true);
  };

  const BUBBLE_W = 360;
  const pad = 16;
  let bubble: React.CSSProperties;
  if (rect) {
    const spaceBelow = vp.h - rect.bottom;
    const top = spaceBelow > 230 ? rect.bottom + 14 : Math.max(pad, rect.top - 224);
    const left = Math.min(Math.max(pad, rect.left), vp.w - BUBBLE_W - pad);
    bubble = { position: "fixed", top, left, width: BUBBLE_W };
  } else {
    bubble = { position: "fixed", bottom: 24, left: "50%", width: BUBBLE_W, transform: "translateX(-50%)" };
  }

  return (
    <>
      {/* A glowing ring on what to look at — NO screen-dimming, so the whole console
          stays visible and clickable. The ring is pointer-events-none. */}
      {rect && (
        <div
          aria-hidden
          className="pointer-events-none fixed z-[60] rounded-lg border-2 border-emerald-400/70 transition-all duration-300"
          style={{
            left: rect.left - 6,
            top: rect.top - 6,
            width: rect.width + 12,
            height: rect.height + 12,
            boxShadow: "0 0 26px -2px rgba(16,185,129,0.55), 0 0 22px -4px rgba(16,185,129,0.4) inset",
          }}
        />
      )}

      <div style={bubble} className="z-[70] font-mono">
        <div className="pointer-events-auto rounded-lg border border-emerald-400/40 bg-[#05080c] p-4 shadow-[0_0_36px_-8px] shadow-emerald-500/40">
          <div className="mb-1.5 flex items-center gap-2">
            <span className="h-2 w-2 animate-pulse rounded-full bg-emerald-400" />
            <span className="text-[0.58rem] uppercase tracking-[0.2em] text-emerald-300">Shift lead · in your ear</span>
            <span className="ml-auto text-[0.55rem] text-zinc-600">{stepIndex + 1}/{STEPS.length}</span>
          </div>
          <h3 className="text-sm font-semibold text-zinc-100">{step.title}</h3>
          <p className="mt-1 text-[0.72rem] leading-relaxed text-zinc-400">{step.body}</p>
          <div className="mt-2.5 flex items-center gap-3">
            {step.button && (
              <button
                onClick={next}
                className="rounded border border-emerald-500/50 bg-emerald-700/25 px-3 py-1 text-[0.68rem] font-semibold text-emerald-100 transition-colors hover:bg-emerald-600/35"
              >
                {step.button}
              </button>
            )}
            <button
              onClick={finish}
              className="text-[0.6rem] text-zinc-600 transition-colors hover:text-zinc-400"
            >
              skip coaching
            </button>
          </div>
        </div>
      </div>
    </>
  );
}
