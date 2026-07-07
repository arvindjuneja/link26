"use client";

import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { useGameStore } from "@/app/lib/persistence/store";
import type { GameState } from "@/types/game";

// First-run, total-beginner onboarding — a scripted, PACED first job.
//
// Design goals (hard-won from playtest feedback):
//  • The player TYPES every command themselves — no auto-run buttons. Typing is
//    the skill; clicking a button taught nothing and felt like "the whole game is
//    one click".
//  • It has a story with TENSION: Mercer rushes the rookie into connecting with
//    no cover, the NETWORK bar spikes and the klaxon fires ("oh shit"), they bail,
//    and only THEN does Mercer teach the proxy — the lesson lands through felt
//    consequence, not a tooltip.
//  • One spotlight at a time + every advanced panel hidden, so a newcomer who has
//    never seen a terminal isn't buried.
//
// It advances strictly on real game-state transitions of the CURRENT step (never
// fast-forwards), and only runs for a genuinely fresh save.

const DONE_KEY = "link26_onboarding_v1";
const CH0 = "campaign-ch-first-light";

type Anchor = "terminal" | "map" | "exposure" | null;
type Kind = "intro" | "type" | "outro";

interface Step {
  kind: Kind;
  anchor: Anchor;
  title: string;
  body: string;
  /** For "type" steps: the exact command the player must type. */
  cmd?: string;
  /** For intro/outro: the button label. */
  button?: string;
  /** For "type" steps: satisfied → advance (checked only while this step is active). */
  done?: (g: GameState) => boolean;
  /**
   * Some commands flip their `done` state instantly but then stream a staged output
   * animation (e.g. `scan` sets `scannedHosts` at once, then renders its ports table
   * over ~1.2s — `isExecuting` only flips true a tick later, so we can't key off it).
   * `advanceDelayMs` holds the step this many ms after `done` flips true before
   * advancing, so the player sees the result render in the spotlighted panel instead
   * of behind the next step's overlay.
   */
  advanceDelayMs?: number;
}

const connectedTo = (g: GameState, host: string) => g.session.connectedHost === host;

const STEPS: Step[] = [
  {
    kind: "intro",
    anchor: null,
    title: "Never hacked before? Good.",
    body:
      "You're a freelancer who breaks into computers for money. Tonight's job: slip into a company's server, copy one file, get paid. I'm Mercer — I'll be in your ear the whole way. You don't need to know anything. I'll tell you exactly what to type; you hit Enter. Let's start.",
    button: "I'm ready ▸",
  },
  {
    kind: "type",
    anchor: "terminal",
    title: "Your terminal",
    body:
      "That dark panel on the right is a terminal — where you type orders to a computer. I'll give you each command; just type it in the box below and press Enter. It'll run in the terminal. This one takes the job.",
    cmd: `accept ${CH0}`,
    done: (g) => g.activeMissions.some((m) => m.id === CH0 && m.status !== "available" && m.status !== "locked"),
  },
  {
    kind: "type",
    anchor: "terminal",
    title: "Client's impatient — let's just grab it",
    body:
      "The target machine is called hq-node. Forget the careful stuff, we'll just connect straight to it and take the file. Type this:",
    cmd: "connect hq-node",
    done: (g) => connectedTo(g, "hq-node"),
  },
  {
    kind: "type",
    anchor: "exposure",
    title: "— wait. WAIT.",
    body:
      "Look at the NETWORK bar up there. It just jumped. That's their security tracing the connection straight back to YOU — because we walked in with nothing hiding us. We're lit up. Get out NOW. Type:",
    cmd: "disconnect",
    done: (g) => !g.session.connectedHost,
  },
  {
    kind: "type",
    anchor: "map",
    title: "Okay. Breathe. That was my fault.",
    body:
      "Here's the rule that keeps you out of prison: never touch a target directly. You bounce your connection through other machines first, so anyone tracing it hits a dead end. That's a proxy. See the map? Add a relay — type this (or click any glowing node):",
    cmd: "route add proxy-1",
    done: (g) => g.route.hops.length > 0,
  },
  {
    kind: "type",
    anchor: "terminal",
    title: "Now look before you leap",
    body:
      "Hidden now. Before we go back in, let's actually scan the target — see the file we want and any alarms waiting for us. A scan is just a careful look:",
    cmd: "scan hq-node",
    done: (g) => Array.from(g.session.scannedHosts ?? []).includes("hq-node"),
    // scan flips `scannedHosts` instantly but streams its ports table over ~1.2s;
    // hold ~1.5s so the table finishes rendering in the terminal before the coach
    // moves to the "read it" beat below (nothing is dimmed now, so it stays visible).
    advanceDelayMs: 1500,
  },
  {
    // A read-and-understand beat: pause on the scan result (now visible, not dimmed)
    // and explain WHAT it showed + WHY you scan, before the next instruction. Manual
    // advance (a button) so the player is never rushed past their first scan.
    kind: "intro",
    anchor: "terminal",
    title: "There it is — read the terminal.",
    body:
      "That's the scan: the file we came for — /secrets.txt — and the target's alarm state, laid out. THIS is why you look before you leap; you never walk in blind. Take a second to see it. When you're ready, we go in.",
    button: "Got it — go in ▸",
  },
  {
    kind: "type",
    anchor: "exposure",
    title: "Go back in — quietly this time",
    body:
      "Same command as before. But keep your eye on that NETWORK bar now — watch how little it moves when you're coming in through a relay. That's the whole difference between a ghost and a guy in handcuffs.",
    cmd: "connect hq-node",
    done: (g) => connectedTo(g, "hq-node"),
  },
  {
    kind: "type",
    anchor: "terminal",
    title: "See that? Barely a flicker.",
    body:
      "THAT is a clean entry. Now take what we came for — copy the file off their machine onto yours:",
    cmd: "cp /secrets.txt @local",
    done: (g) => g.inventory.some((i) => i.source === "hq-node" && i.path === "/secrets.txt"),
  },
  {
    kind: "type",
    anchor: "terminal",
    title: "Don't linger",
    body:
      "Every second you stay connected, that bar creeps back up. Hand the file to the client and disappear:",
    cmd: `submit ${CH0}`,
    done: (g) => g.campaign.chapter > 0,
  },
  {
    kind: "outro",
    anchor: null,
    title: "That's the whole game",
    body:
      "Take a job → hide your tracks → get in → grab the goods → get out before the heat catches up. You panicked back there, and you recovered. That's the job. The rest of your tools and tougher contracts are on screen now — they unlock as you work. Go earn, operator.",
    button: "Start playing ▸",
  },
];

export default function GuidedOnboarding({
  onActiveChange,
}: {
  onActiveChange?: (active: boolean) => void;
}) {
  const gameState = useGameStore((s) => s.gameState);
  const runCommand = useGameStore((s) => s.runCommand);
  const isExecuting = useGameStore((s) => s.isExecuting);

  const [mounted, setMounted] = useState(false);
  const [dismissed, setDismissed] = useState(true); // hidden until we decide on mount
  const [stepIndex, setStepIndex] = useState(0);
  const [rect, setRect] = useState<DOMRect | null>(null);
  const [vp, setVp] = useState({ w: 1440, h: 900 });
  const [typed, setTyped] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);
  const baseDone = useRef(false);
  const advanceTimer = useRef<number | null>(null);

  // Decide on mount: run only for a genuinely FRESH save (nothing touched yet).
  // Anything dirtier means they've played — skip, so we never cascade or confuse.
  useEffect(() => {
    setMounted(true);
    const finished = typeof window !== "undefined" && localStorage.getItem(DONE_KEY);
    const g = useGameStore.getState().gameState;
    const fresh =
      g.campaign.chapter === 0 &&
      g.route.hops.length === 0 &&
      g.inventory.length === 0 &&
      !g.session.connectedHost &&
      !g.activeMissions.some((m) => m.status === "accepted" || m.status === "completed");
    setDismissed(Boolean(finished) || !fresh);
  }, []);

  const active = mounted && !dismissed;
  const step = STEPS[stepIndex];

  useEffect(() => {
    onActiveChange?.(active);
  }, [active, onActiveChange]);

  // Snapshot whether the active step's goal is ALREADY met when it opens, so we
  // only advance on a fresh transition the player causes — never instantly.
  useEffect(() => {
    baseDone.current = STEPS[stepIndex]?.done?.(useGameStore.getState().gameState) ?? false;
  }, [stepIndex]);

  // Advance when the current step's goal flips from not-done → done. A step may
  // ask to hold briefly first (advanceDelayMs) so a staged result (e.g. the scan
  // ports table) renders in the spotlighted panel before the coach dims it.
  useEffect(() => {
    if (!active) return;
    const s = STEPS[stepIndex];
    if (!s?.done || !s.done(gameState) || baseDone.current) return;
    if (advanceTimer.current !== null) return; // already scheduled for this step
    const go = () => {
      advanceTimer.current = null;
      setStepIndex((i) => Math.min(i + 1, STEPS.length - 1));
    };
    if (s.advanceDelayMs) advanceTimer.current = window.setTimeout(go, s.advanceDelayMs);
    else go();
  }, [active, gameState, stepIndex]);

  // Cancel a pending delayed-advance if the step changes (or we unmount), so a
  // late timer can never skip the wrong step.
  useEffect(() => {
    return () => {
      if (advanceTimer.current !== null) {
        clearTimeout(advanceTimer.current);
        advanceTimer.current = null;
      }
    };
  }, [stepIndex]);

  // Each typed step gets its OWN input inside the coach bubble — so the player
  // never has to find/click the terminal (which the bubble can overlap). Clear
  // and focus it whenever the step changes.
  useEffect(() => {
    if (!active || step?.kind !== "type") return;
    setTyped("");
    const t = window.setTimeout(() => inputRef.current?.focus(), 140);
    return () => window.clearTimeout(t);
  }, [active, stepIndex, step?.kind]);

  // Measure the spotlighted element; keep it aligned as panels animate/resize.
  useLayoutEffect(() => {
    if (!active) return;
    const measure = () => {
      setVp({ w: window.innerWidth, h: window.innerHeight });
      if (!step?.anchor) {
        setRect(null);
        return;
      }
      const el = document.querySelector(`[data-onboarding="${step.anchor}"]`);
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
  }, [active, step?.anchor, stepIndex]);

  if (!active || !step) return null;

  const submitTyped = (e: React.FormEvent) => {
    e.preventDefault();
    const v = typed.trim();
    if (!v || isExecuting) return;
    runCommand(v); // runs through the real engine; echoes in the terminal too
    setTyped("");
  };

  const advanceManual = () => {
    if (step.kind === "outro") {
      try {
        localStorage.setItem(DONE_KEY, "1");
      } catch {
        /* ignore */
      }
      setDismissed(true);
      return;
    }
    setStepIndex((i) => i + 1);
  };

  // Bubble placement: below the spotlight if there's room, else above; clamped.
  const BUBBLE_W = 380;
  const pad = 18;
  let bubble: React.CSSProperties;
  if (rect) {
    const spaceBelow = vp.h - rect.bottom;
    const top = spaceBelow > 330 ? rect.bottom + 16 : Math.max(pad, rect.top - 332);
    const left = Math.min(Math.max(pad, rect.left), vp.w - BUBBLE_W - pad);
    bubble = { position: "fixed", top, left, width: BUBBLE_W };
  } else {
    bubble = {
      position: "fixed",
      top: "50%",
      left: "50%",
      width: BUBBLE_W,
      transform: "translate(-50%, -50%)",
    };
  }

  return (
    <>
      {/* Highlight. A glowing RING on the target — NOT a screen-dimming spotlight, so
          command output (esp. the scan's ports table) stays fully readable instead of
          being buried behind an overlay. Ring is pointer-events:none. For no-anchor
          story beats (intro/outro), a flat dim is fine — there's nothing to read. */}
      {rect ? (
        <div
          aria-hidden
          className="pointer-events-none fixed z-[70] rounded-xl border-2 border-cyan-400/70 transition-all duration-300"
          style={{
            left: rect.left - 8,
            top: rect.top - 8,
            width: rect.width + 16,
            height: rect.height + 16,
            boxShadow: "0 0 30px -2px rgba(34,211,238,0.6), 0 0 22px -4px rgba(34,211,238,0.45) inset",
          }}
        />
      ) : (
        <div aria-hidden className="pointer-events-auto fixed inset-0 z-[70] bg-[#020408]/[0.88]" />
      )}

      {/* Coach bubble */}
      <div style={bubble} className="z-[80] font-mono">
        <div className="pointer-events-auto rounded-lg border border-cyan-400/40 bg-[#05080c] p-4 shadow-[0_0_40px_-8px] shadow-cyan-500/40">
          <div className="mb-2 flex items-center gap-2">
            <span className="h-2 w-2 animate-pulse rounded-full bg-cyan-400" />
            <span className="text-[0.6rem] uppercase tracking-[0.2em] text-cyan-300">
              Mercer · your handler
            </span>
            <span className="ml-auto text-[0.58rem] text-zinc-600">
              {stepIndex + 1}/{STEPS.length}
            </span>
          </div>

          <h3 className="text-sm font-semibold text-zinc-100">{step.title}</h3>
          <p className="mt-1.5 text-[0.74rem] leading-relaxed text-zinc-400">{step.body}</p>

          {step.kind === "type" && step.cmd && (
            <form onSubmit={submitTyped} className="mt-3">
              <div className="mb-1 text-[0.56rem] uppercase tracking-[0.15em] text-zinc-500">
                ⌨ type it here, then press Enter
              </div>
              <div className="flex items-center gap-2 rounded border border-cyan-500/40 bg-black/70 px-2.5 py-2 focus-within:border-cyan-400/80">
                <span className="text-zinc-600">$</span>
                <input
                  ref={inputRef}
                  value={typed}
                  onChange={(e) => setTyped(e.target.value)}
                  placeholder={step.cmd}
                  spellCheck={false}
                  autoComplete="off"
                  autoCapitalize="off"
                  className="w-full bg-transparent text-[0.82rem] text-cyan-200 outline-none placeholder:text-zinc-700"
                />
              </div>
              <div className="mt-1.5 text-[0.6rem] text-zinc-600">
                type: <code className="text-zinc-400">{step.cmd}</code>
              </div>
            </form>
          )}

          {(step.kind === "intro" || step.kind === "outro") && step.button && (
            <button
              onClick={advanceManual}
              className="mt-3 w-full rounded border border-cyan-500/50 bg-cyan-700/25 py-2 text-[0.78rem] font-semibold tracking-wide text-cyan-100 transition-colors hover:bg-cyan-600/35"
            >
              {step.button}
            </button>
          )}
        </div>
      </div>
    </>
  );
}
