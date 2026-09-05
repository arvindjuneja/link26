"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import type { TraceStatus } from "@/types/game";
import {
  applyCall,
  assembleShift,
  gradeCall,
  overallShiftStatus,
  scoreShift,
  shiftComplete,
  type CallGrade,
} from "@/app/lib/soc/engine";
import { FIRST_SHIFT_CASE_IDS, SHIFTS, SOC_CASES_BY_ID } from "@/app/lib/soc/cases";
import {
  DISPOSITIONS,
  type Disposition,
  type ShiftState,
  type SocCase,
  type SocEvidence,
} from "@/app/lib/soc/types";
import SocOnboarding, { SOC_ONBOARDING_DONE_KEY } from "@/app/components/soc/SocOnboarding";
import {
  KIT,
  INITIAL_CAREER,
  awardForShift,
  buyKit,
  isUnlocked,
  loadCareer,
  nextRank,
  owns,
  rankFor,
  saveCareer,
  type CareerState,
  type KitItem,
  type ShiftReward,
} from "@/app/lib/career/state";
import { inboxFor, type HandlerEvent } from "@/app/lib/career/handler";

// Cold-glass palette, shared with the red seat's ExposureBoard so the two chairs
// read as one product. Color is spent as tension rises.
const STATUS_COLOR: Record<TraceStatus, { bar: string; text: string; border: string; glow: string }> = {
  CALM: { bar: "bg-cyan-500/60", text: "text-cyan-300", border: "border-cyan-500/25", glow: "" },
  ALERT: { bar: "bg-amber-500/70", text: "text-amber-300", border: "border-amber-500/35", glow: "shadow-[0_0_14px_-3px] shadow-amber-500/40" },
  HUNT: { bar: "bg-orange-500/80", text: "text-orange-300", border: "border-orange-500/40", glow: "shadow-[0_0_18px_-3px] shadow-orange-500/50" },
  LOCKDOWN: { bar: "bg-rose-500/90", text: "text-rose-300", border: "border-rose-500/50", glow: "shadow-[0_0_24px_-2px] shadow-rose-500/60" },
};

const BPM: Record<TraceStatus, number> = { CALM: 50, ALERT: 76, HUNT: 112, LOCKDOWN: 150 };

const DISPOSITION_META: Record<
  Disposition,
  { label: string; sub: string; tone: "cyan" | "emerald" | "amber" | "rose" }
> = {
  "close-false-positive": { label: "Close · False Positive", sub: "didn't happen — the rule misread it", tone: "cyan" },
  "close-benign": { label: "Close · Benign (authorized)", sub: "it happened — and it was sanctioned", tone: "emerald" },
  "escalate-tier2": { label: "Escalate → Tier 2", sub: "suspicious / confirmed — hand up", tone: "amber" },
  "escalate-ir-isolate": { label: "Escalate → IR + isolate host", sub: "active threat — contain now", tone: "rose" },
};

const TONE: Record<string, string> = {
  cyan: "border-cyan-500/40 bg-cyan-500/5 hover:bg-cyan-500/15 text-cyan-200",
  emerald: "border-emerald-500/40 bg-emerald-500/5 hover:bg-emerald-500/15 text-emerald-200",
  amber: "border-amber-500/40 bg-amber-500/5 hover:bg-amber-500/15 text-amber-200",
  rose: "border-rose-500/40 bg-rose-500/5 hover:bg-rose-500/15 text-rose-200",
};

const SEVERITY_TONE: Record<SocCase["toolSeverity"], string> = {
  Low: "text-zinc-400 border-zinc-600",
  Medium: "text-amber-300 border-amber-600/50",
  High: "text-orange-300 border-orange-600/50",
  Critical: "text-rose-300 border-rose-600/50",
};

const VERDICT_LABEL: Record<string, string> = {
  "true-positive": "True Positive",
  "false-positive": "False Positive",
  "benign-true-positive": "Benign True Positive",
};

type Phase = "hub" | "briefing" | "investigating" | "debrief" | "complete";

interface LastResult {
  case: SocCase;
  chosen: Disposition;
  grade: CallGrade;
}

function makeShift(i: number): ShiftState {
  const s = SHIFTS[((i % SHIFTS.length) + SHIFTS.length) % SHIFTS.length];
  return assembleShift(s.id, s.caseIds);
}

// Owned kit pre-pulls a source at case open (the cash sink's benefit).
function initialQueried(c: SocCase | undefined, career: CareerState): string[] {
  if (c && owns(career, "intel-feed") && c.sources.some((s) => s.id === "threat-intel")) {
    return ["threat-intel"];
  }
  return [];
}

// ── Compact pressure meter (reuses the heartbeat language of the red seat) ─────
function PressureBar({ label, level, fear }: { label: string; level: number; fear: string }) {
  const status = level >= 80 ? "LOCKDOWN" : level >= 50 ? "HUNT" : level >= 25 ? "ALERT" : "CALM";
  const col = STATUS_COLOR[status as TraceStatus];
  return (
    <div title={fear}>
      <div className="mb-0.5 flex items-center justify-between text-[0.58rem]">
        <span className={`tracking-wider ${level > 0 ? col.text : "text-zinc-500"}`}>{label}</span>
        <span className={`tabular-nums ${col.text}`}>{level.toFixed(0)}%</span>
      </div>
      <div className="h-1.5 w-full overflow-hidden rounded-full bg-zinc-800/80">
        <div className={`h-full rounded-full ${col.bar} transition-all duration-500`} style={{ width: `${Math.min(100, level)}%` }} />
      </div>
    </div>
  );
}

export default function SocConsole() {
  const [shiftIdx, setShiftIdx] = useState(0);
  const [shift, setShift] = useState<ShiftState>(() => makeShift(0));
  const [phase, setPhase] = useState<Phase>("hub"); // the career hub is home
  const [queried, setQueried] = useState<string[]>([]);
  const [last, setLast] = useState<LastResult | null>(null);
  // The career layer — cash / standing / rank / unlocks, persisted locally.
  const [career, setCareer] = useState<CareerState>(INITIAL_CAREER);
  const [reward, setReward] = useState<ShiftReward | null>(null); // last shift's payout
  const [lastEvent, setLastEvent] = useState<HandlerEvent>({}); // drives the handler inbox

  // Load persisted career after mount (localStorage is client-only).
  useEffect(() => {
    setCareer(loadCareer());
  }, []);

  // QA/demo affordance: /soc?demo=<screen> jumps straight to a screen so each can
  // be screenshotted/linked without clicking the whole shift. Harmless, dev-facing.
  //   ?demo=1|investigating → first case, two sources pre-pulled
  //   ?demo=debrief         → a (deliberately wrong) call on the first case
  //   ?demo=complete        → a finished shift with a representative mix of calls
  useEffect(() => {
    if (typeof window === "undefined") return;
    const screen = new URLSearchParams(window.location.search).get("demo");
    if (!screen) return;
    try {
      localStorage.setItem(SOC_ONBOARDING_DONE_KEY, "1"); // demo deep-links skip the first-shift coach
    } catch {
      /* ignore */
    }
    if (screen === "debrief") {
      const c = SOC_CASES_BY_ID[FIRST_SHIFT_CASE_IDS[0]];
      const chosen: Disposition = "close-false-positive"; // wrong: closes a real threat
      // build non-functionally so a StrictMode double-invoke stays idempotent
      setShift(applyCall(makeShift(0), c, chosen, ["edr-process-tree"], 10));
      setLast({ case: c, chosen, grade: gradeCall(c, chosen) });
      setPhase("debrief");
    } else if (screen === "complete") {
      let s = makeShift(0);
      // mostly-right shift with one slip, so the scorecard shows real numbers
      const calls: Record<string, Disposition> = {
        "soc-ps-cradle": "escalate-ir-isolate",
        "soc-auth-reset": "escalate-tier2", // slip: escalated an FP
        "soc-ps-patch": "close-benign",
        "soc-dns-beacon": "escalate-ir-isolate",
        "soc-auth-bruteforce": "escalate-ir-isolate",
        "soc-dns-cdn": "close-false-positive",
        "soc-auth-pentest": "close-benign",
      };
      for (const id of s.caseIds) {
        const c = SOC_CASES_BY_ID[id];
        // pull the answering logs for most; one case called blind (to show the mechanic)
        const queried = id === "soc-dns-cdn" ? [] : c.keySourceIds;
        s = applyCall(s, c, calls[id] ?? c.correctDisposition, queried, 18);
      }
      setShift(s);
      setPhase("complete");
    } else if (screen === "shift2") {
      // jump into the round-2 shift's opening phishing case, two sources pulled
      setShiftIdx(1);
      setShift(makeShift(1));
      setQueried(["email-auth", "sender-reputation"]);
      setPhase("investigating");
    } else if (screen === "lockout") {
      // jump into the lockout shift's opening (stale-credential FP) case
      setShiftIdx(2);
      setShift(makeShift(2));
      setQueried(["auth-failures", "it-helpdesk"]);
      setPhase("investigating");
    } else if (screen === "handoff") {
      // jump into the Red↔Blue handoff shift's opening (authorized) run
      setShiftIdx(3);
      setShift(makeShift(3));
      setQueried(["change-tickets", "auth-logs"]);
      setPhase("investigating");
    } else if (screen === "insider") {
      // jump into the insider desk's opening (departing-employee) case
      setShiftIdx(4);
      setShift(makeShift(4));
      setQueried(["hr-directory", "change-tickets"]);
      setPhase("investigating");
    } else {
      setQueried(["edr-process-tree", "change-tickets"]);
      setPhase("investigating");
    }
  }, []);

  const current: SocCase | undefined = SOC_CASES_BY_ID[shift.caseIds[shift.index]];
  const overall = overallShiftStatus(shift);
  const oc = STATUS_COLOR[overall];
  const beatMs = Math.round(60000 / BPM[overall]);
  // QUEUE position: index has already advanced during the debrief, so show the
  // case just reviewed (shift.index) rather than reading ahead to the next one.
  const queuePos =
    phase === "complete"
      ? shift.caseIds.length
      : Math.min(phase === "debrief" ? shift.index : shift.index + 1, shift.caseIds.length);

  const revealed: SocEvidence[] = useMemo(() => {
    if (!current) return [];
    return current.evidence.filter((e) => queried.includes(e.sourceId));
  }, [current, queried]);

  const timeSpent = useMemo(() => {
    if (!current) return 0;
    return current.sources.filter((s) => queried.includes(s.id)).reduce((a, s) => a + s.cost, 0);
  }, [current, queried]);

  const pullSource = (id: string) => {
    if (queried.includes(id)) return;
    setQueried((q) => [...q, id]);
  };

  const makeCall = (disp: Disposition) => {
    if (!current || phase !== "investigating") return; // re-entrancy guard
    const grade = gradeCall(current, disp);
    const cur = current;
    setShift((s) => applyCall(s, cur, disp, queried, timeSpent));
    setLast({ case: cur, chosen: disp, grade });
    // Persist onboarding completion the moment the player makes their first real
    // call — so the first-shift coach doesn't re-fire every new shift / reload.
    if (shift.index === 0) {
      try {
        localStorage.setItem(SOC_ONBOARDING_DONE_KEY, "1");
      } catch {
        /* ignore */
      }
    }
    setPhase("debrief");
  };

  const nextCase = () => {
    setLast(null);
    if (shiftComplete(shift)) {
      // Shift finished → award career (cash + standing), compute new unlocks, persist.
      const score = scoreShift(shift, SOC_CASES_BY_ID);
      const wasUnlocked = new Set(SHIFTS.filter((s) => isUnlocked(career, s)).map((s) => s.id));
      const r = awardForShift(career, score);
      const unlocked = SHIFTS.filter((s) => !wasUnlocked.has(s.id) && isUnlocked(r.state, s)).map((s) => ({
        id: s.id,
        label: s.label,
      }));
      setCareer(r.state);
      saveCareer(r.state);
      setReward(r);
      setLastEvent({
        type: score.grade === "clean" ? "shift-clean" : score.grade === "rough" ? "shift-rough" : "shift-breached",
        rankUp: r.rankUp,
        unlocked,
      });
      setPhase("complete");
    } else {
      setQueried(initialQueried(SOC_CASES_BY_ID[shift.caseIds[shift.index]], career));
      setPhase("investigating");
    }
  };

  // Start a shift from the hub (respects owned kit's pre-pull).
  const startShift = (i: number) => {
    setShiftIdx(i);
    const s = makeShift(i);
    setShift(s);
    setQueried(initialQueried(SOC_CASES_BY_ID[s.caseIds[0]], career));
    setLast(null);
    setReward(null);
    setPhase("briefing");
  };

  const toHub = () => {
    setLast(null);
    setPhase("hub");
  };

  const buyItem = (item: KitItem) => {
    const c = buyKit(career, item);
    setCareer(c);
    saveCareer(c);
  };

  return (
    <div className={`relative min-h-screen overflow-x-hidden bg-[#000102] font-mono text-white ${overall === "CALM" ? "" : `transition-colors duration-500`}`}>
      {/* Edge glow rises with the worst pressure meter — the dread is the breach now */}
      <div
        aria-hidden
        className={`pointer-events-none fixed inset-0 z-0 transition-all duration-700 ${overall === "HUNT" || overall === "LOCKDOWN" ? "animate-pulse" : ""}`}
        style={{
          boxShadow: `inset 0 0 140px 12px ${
            { CALM: "transparent", ALERT: "rgba(245,158,11,0.08)", HUNT: "rgba(249,115,22,0.14)", LOCKDOWN: "rgba(244,63,94,0.22)" }[overall]
          }`,
        }}
      />

      <div className="relative z-10 mx-auto flex min-h-screen w-full max-w-[1500px] flex-col gap-3 px-3 py-4">
        {/* ── System bar ── */}
        <header className={`flex items-center justify-between rounded border ${oc.border} ${oc.glow} bg-black/60 px-4 py-2 text-[0.7rem] transition-all duration-300`}>
          <div className="flex items-center gap-4">
            <span className="font-semibold tracking-[0.18em] text-emerald-300">SENTRY · SOC</span>
            <span className="text-zinc-600">|</span>
            <span className="text-zinc-500">
              BLUE SEAT · <span className="text-zinc-300">{rankFor(career.standing).label}</span>
            </span>
          </div>
          <div className="flex items-center gap-4">
            <span className="text-zinc-500" title="standing — earned by clean shifts; unlocks harder queues">
              ⬢ <span className="text-emerald-300">{career.standing}</span>
            </span>
            <span className="text-zinc-500" title="cash — earned by the work; spent on kit">
              ¢ <span className="text-amber-400">{career.cash}</span>
            </span>
            {phase !== "hub" && (
              <>
                <div className="flex items-center gap-2">
                  <span className={`inline-block h-2.5 w-2.5 rounded-full ${oc.bar}`} style={{ animation: overall === "CALM" ? "none" : `soc-beat ${beatMs}ms ease-in-out infinite` }} />
                  <span className={oc.text}>{overall === "CALM" ? "QUIET" : overall}</span>
                </div>
                <span className="text-zinc-500">
                  QUEUE <span className="text-zinc-300">{queuePos}/{shift.caseIds.length}</span>
                </span>
              </>
            )}
            <Link href="/" className="rounded border border-zinc-700 px-2.5 py-1 text-zinc-400 transition-colors hover:bg-zinc-800/60">
              ↩ red seat
            </Link>
          </div>
        </header>

        {phase === "hub" && (
          <CareerHub career={career} lastEvent={lastEvent} onStart={startShift} onBuy={buyItem} />
        )}

        {phase === "briefing" && (
          <Briefing
            onBegin={() => {
              setQueried(initialQueried(SOC_CASES_BY_ID[shift.caseIds[0]], career));
              setPhase("investigating");
            }}
            total={shift.caseIds.length}
            label={SHIFTS[shiftIdx].label}
            isHandoff={SHIFTS[shiftIdx].id === "handoff-shift"}
          />
        )}

        {phase === "complete" && (
          <ShiftComplete shift={shift} reward={reward} unlocked={lastEvent.unlocked ?? []} onHub={toHub} />
        )}

        {phase === "investigating" && current && (
          <div className="flex flex-col gap-3 lg:flex-row lg:items-start">
            {/* ── Left: the alert queue ── */}
            <aside className="w-full shrink-0 lg:w-56">
              <div className="rounded border border-zinc-800 bg-black/50 p-3">
                <div className="mb-2 text-[0.6rem] uppercase tracking-[0.18em] text-zinc-500">Alert queue</div>
                <ol className="space-y-1.5">
                  {shift.caseIds.map((id, i) => {
                    const c = SOC_CASES_BY_ID[id];
                    const done = shift.results[id];
                    const isCur = i === shift.index;
                    return (
                      <li
                        key={id}
                        className={`rounded border px-2 py-1.5 text-[0.66rem] leading-tight ${
                          isCur
                            ? "border-cyan-500/50 bg-cyan-500/10 text-cyan-100"
                            : done
                            ? "border-zinc-800 bg-zinc-900/40 text-zinc-500"
                            : "border-zinc-800/60 bg-black/30 text-zinc-600"
                        }`}
                      >
                        <div className="flex items-center justify-between gap-1">
                          <span className="truncate">
                            {c.handoff && <span className="text-fuchsia-400">↔ </span>}
                            {c.alertTitle}
                          </span>
                          {done && (
                            <span className={done.verdictCorrect ? "text-emerald-400" : "text-rose-400"}>{done.verdictCorrect ? "✓" : "✗"}</span>
                          )}
                        </div>
                      </li>
                    );
                  })}
                </ol>
              </div>

              <div className="mt-3 rounded border border-zinc-800 bg-black/50 p-3">
                <div className="mb-2 flex items-center justify-between">
                  <span className="text-[0.6rem] uppercase tracking-[0.18em] text-zinc-500">Shift pressure</span>
                  <span className="text-[0.55rem] text-zinc-600">{shift.timeUsed}m</span>
                </div>
                <div className="space-y-2">
                  <PressureBar label="BREACH RISK" level={shift.breachRisk} fear="a real threat you closed is dwelling undetected" />
                  <PressureBar label="NOISE / FATIGUE" level={shift.noise} fear="crying wolf — Tier-2 stops trusting your tickets" />
                </div>
              </div>
            </aside>

            {/* ── Center: the active case ── */}
            <section className="min-w-0 flex-1 space-y-3">
              {/* Alert header */}
              <div className={`rounded border ${oc.border} bg-black/60 p-4`}>
                <div className="mb-1 flex flex-wrap items-center gap-2 text-[0.58rem] uppercase tracking-[0.18em]">
                  <span className={`rounded border px-1.5 py-0.5 ${SEVERITY_TONE[current.toolSeverity]}`}>{current.toolSeverity} · as flagged</span>
                  {current.handoff && (
                    <span className="rounded border border-fuchsia-500/40 bg-fuchsia-500/10 px-1.5 py-0.5 text-fuchsia-300">↔ from your red seat</span>
                  )}
                  <span className="text-zinc-600">{current.detectionRule}</span>
                </div>
                <h2 className="text-base font-semibold text-zinc-100">{current.alertTitle}</h2>
                <p className="mt-1 text-[0.78rem] leading-relaxed text-zinc-400">{current.trigger}</p>
                <div className="mt-1.5 text-[0.62rem] text-zinc-600">asset: <span className="text-zinc-400">{current.asset}</span></div>
              </div>

              <div className="grid gap-3 md:grid-cols-2">
                {/* Data sources — the log-to-question move */}
                <div data-soc="sources" className="rounded border border-zinc-800 bg-black/50 p-3">
                  <div className="mb-2 text-[0.6rem] uppercase tracking-[0.18em] text-zinc-500">
                    Pull a data source — which log answers the question?
                  </div>
                  <div className="space-y-1.5">
                    {current.sources.map((s) => {
                      const pulled = queried.includes(s.id);
                      return (
                        <button
                          key={s.id}
                          disabled={pulled}
                          onClick={() => pullSource(s.id)}
                          className={`w-full rounded border px-2.5 py-1.5 text-left transition-colors disabled:cursor-default ${
                            pulled
                              ? "border-zinc-800 bg-zinc-900/50 opacity-60"
                              : "border-zinc-700 bg-black/40 hover:border-cyan-600/50 hover:bg-cyan-500/5"
                          }`}
                        >
                          <div className="flex items-center justify-between">
                            <span className="text-[0.72rem] text-zinc-200">{s.label}</span>
                            <span className="text-[0.55rem] text-zinc-600">{pulled ? "pulled" : `${s.cost}m`}</span>
                          </div>
                          <div className="text-[0.6rem] italic text-zinc-500">{s.question}</div>
                        </button>
                      );
                    })}
                  </div>
                </div>

                {/* Evidence board */}
                <div data-soc="evidence" className="rounded border border-zinc-800 bg-black/50 p-3">
                  <div className="mb-2 flex items-center justify-between">
                    <span className="text-[0.6rem] uppercase tracking-[0.18em] text-zinc-500">Evidence board</span>
                    <span className="text-[0.55rem] text-zinc-600">{revealed.length} findings</span>
                  </div>
                  {revealed.length === 0 ? (
                    <p className="py-6 text-center text-[0.66rem] text-zinc-600">Pull a source to surface findings.<br />You can&apos;t make the call blind.</p>
                  ) : (
                    <ul className="space-y-1.5">
                      {revealed.map((e) => (
                        <li key={e.id} className="rounded border border-zinc-800 bg-black/40 px-2.5 py-1.5">
                          <div className="text-[0.7rem] font-medium text-zinc-200">{e.label}</div>
                          <div className="text-[0.62rem] leading-snug text-zinc-500">{e.detail}</div>
                        </li>
                      ))}
                    </ul>
                  )}
                </div>
              </div>

              {/* Make the call */}
              <div data-soc="call" className={`rounded border ${oc.border} bg-black/60 p-3`}>
                <div className="mb-2 flex items-center justify-between">
                  <span className="text-[0.6rem] uppercase tracking-[0.18em] text-zinc-500">Make the call</span>
                  {revealed.length === 0 && <span className="text-[0.55rem] text-amber-400/80">investigate first</span>}
                </div>
                <div className="grid gap-2 sm:grid-cols-2">
                  {DISPOSITIONS.map((d) => {
                    const m = DISPOSITION_META[d];
                    return (
                      <button
                        key={d}
                        disabled={revealed.length === 0}
                        onClick={() => makeCall(d)}
                        className={`rounded border px-3 py-2 text-left transition-colors disabled:cursor-not-allowed disabled:opacity-40 ${TONE[m.tone]}`}
                      >
                        <div className="text-[0.74rem] font-semibold">{m.label}</div>
                        <div className="text-[0.58rem] text-zinc-500">{m.sub}</div>
                      </button>
                    );
                  })}
                </div>
              </div>
            </section>
          </div>
        )}
      </div>

      {/* Debrief overlay */}
      {phase === "debrief" && last && <Debrief result={last} shift={shift} onNext={nextCase} />}

      {/* First-shift coaching (only fires on the opening case) */}
      {phase === "investigating" && shift.index === 0 && (
        <SocOnboarding hasEvidence={revealed.length > 0} sourcesPulled={queried.length} />
      )}

      <style jsx global>{`
        @keyframes soc-beat {
          0%, 100% { transform: scale(1); opacity: 0.85; }
          14% { transform: scale(1.7); opacity: 1; }
          28% { transform: scale(1); opacity: 0.85; }
          42% { transform: scale(1.35); opacity: 0.95; }
        }
        @media (prefers-reduced-motion: reduce) {
          .animate-pulse,
          [style*="soc-beat"] { animation: none !important; }
        }
      `}</style>
    </div>
  );
}

// ── Briefing (shift handover) ─────────────────────────────────────────────────
function Briefing({
  onBegin,
  total,
  label,
  isHandoff,
}: {
  onBegin: () => void;
  total: number;
  label: string;
  isHandoff?: boolean;
}) {
  const border = isHandoff ? "border-fuchsia-500/30 shadow-fuchsia-500/30" : "border-emerald-500/30 shadow-emerald-500/30";
  const dot = isHandoff ? "bg-fuchsia-400" : "bg-emerald-400";
  const accent = isHandoff ? "text-fuchsia-300" : "text-emerald-300";
  return (
    <div className={`mx-auto mt-6 max-w-2xl rounded-lg border ${border} bg-black/60 p-6 shadow-[0_0_40px_-12px]`}>
      <div className={`mb-2 flex items-center justify-between text-[0.6rem] uppercase tracking-[0.2em] ${accent}`}>
        <span className="flex items-center gap-2">
          <span className={`h-2 w-2 animate-pulse rounded-full ${dot}`} /> Shift handover · 08:00
        </span>
        <span className="text-zinc-500">{label}</span>
      </div>
      <h1 className="text-lg font-semibold text-zinc-100">Welcome to the desk. {total} alerts on the board.</h1>
      {isHandoff && (
        <div className="mt-3 rounded border border-fuchsia-500/30 bg-fuchsia-500/5 p-3 text-[0.76rem] leading-relaxed text-fuchsia-200/90">
          Tonight&apos;s queue is different: <span className="font-semibold">every alert is a run YOU pulled off in the red seat</span>, seen from this chair.
          The tradecraft is real attack behaviour — the tells you left. The only question that decides the verdict is whether an engagement <em>authorized</em> it:
          a <span className="text-emerald-300">sanctioned</span> run (RoE on file) is a Benign-TP; the one you ran <span className="text-rose-300">off-book</span>, with no engagement behind it, is a real intrusion you escalate — <span className="font-semibold">authorization, not authorship</span>. Same board, two seats.
        </div>
      )}
      <div className="mt-3 space-y-2.5 text-[0.8rem] leading-relaxed text-zinc-400">
        <p>
          You&apos;re the Tier-1 analyst. One question decides every alert on that queue:{" "}
          <span className="font-semibold text-zinc-200">did the attack behaviour the rule hunts for actually happen?</span>{" "}
          If it didn&apos;t, and ordinary activity only looked like it, that&apos;s a <span className="text-cyan-300">False Positive</span>;
          if it did but a pentest, change ticket or known tool sanctioned it, that&apos;s a <span className="text-emerald-300">Benign True Positive</span>;
          if it did and nothing sanctioned it, that&apos;s a <span className="text-rose-300">True Positive</span>.
        </p>
        <p>
          The tool&apos;s severity label is a <em>guess</em> — most of what it screams about is noise. Your job is to
          pull the right logs, read what actually happened, and make the call. Escalate a real threat; don&apos;t bury
          Tier-2 in noise; and never isolate a sanctioned operation.
        </p>
        <p className="text-[0.7rem] text-zinc-600">
          Miss a real one and it dwells — watch the BREACH RISK meter. Cry wolf and the NOISE meter climbs. Triage the board.
        </p>
      </div>
      <button
        onClick={onBegin}
        className="mt-5 w-full rounded border border-emerald-500/50 bg-emerald-700/25 py-2.5 text-[0.82rem] font-semibold tracking-wide text-emerald-100 transition-colors hover:bg-emerald-600/35"
      >
        Start the shift ▸
      </button>
      <p className="mt-3 text-center text-[0.62rem] leading-snug text-zinc-500">
        Fiction simulator. Cases are illustrative, not a training platform — every log line is fabricated and teaches the analyst&apos;s read, never a working technique.
      </p>
    </div>
  );
}

// ── Per-case teaching debrief ─────────────────────────────────────────────────
function Debrief({ result, shift, onNext }: { result: LastResult; shift: ShiftState; onNext: () => void }) {
  const { case: c, chosen, grade } = result;
  const right = grade.verdictCorrect && grade.dispositionCorrect;
  const tone = right ? "emerald" : grade.verdictCorrect ? "amber" : "rose";
  const ring = { emerald: "border-emerald-500/40 shadow-emerald-500/30", amber: "border-amber-500/40 shadow-amber-500/30", rose: "border-rose-500/40 shadow-rose-500/30" }[tone];
  const decisive = c.evidence.filter((e) => e.weight === "decisive");
  const pulledKeys = shift.results[c.id]?.keySourcesPulled ?? 0;

  // Esc closes the debrief (advances to the next alert), like any modal.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onNext();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onNext]);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-[#020408]/85 p-4">
      <div
        role="dialog"
        aria-modal="true"
        aria-label={`Case debrief: ${c.alertTitle}`}
        className={`max-h-[90vh] w-full max-w-xl overflow-y-auto rounded-lg border ${ring} bg-[#05080c] p-5 font-mono shadow-[0_0_50px_-10px]`}
      >
        <div className="mb-1 flex items-center justify-between">
          <span className={`text-[0.6rem] uppercase tracking-[0.2em] ${right ? "text-emerald-300" : grade.verdictCorrect ? "text-amber-300" : "text-rose-300"}`}>
            {right ? "Good call" : grade.verdictCorrect ? "Right verdict, off on the response" : "Wrong call"}
          </span>
          <span className="text-[0.58rem] text-zinc-600">truth: <span className="text-zinc-300">{VERDICT_LABEL[c.truth]}</span></span>
        </div>

        <p className="text-[0.8rem] leading-relaxed text-zinc-200">{grade.outcome}</p>

        <div className="mt-3 rounded border border-zinc-800 bg-black/40 p-3">
          <div className="mb-1.5 text-[0.58rem] uppercase tracking-[0.16em] text-zinc-500">Why</div>
          <p className="text-[0.74rem] leading-relaxed text-zinc-400">{c.why}</p>
        </div>

        <div className="mt-3 grid gap-3 sm:grid-cols-2">
          <div className="rounded border border-zinc-800 bg-black/40 p-3">
            <div className="mb-1.5 text-[0.58rem] uppercase tracking-[0.16em] text-zinc-500">The decisive findings</div>
            <ul className="space-y-1">
              {decisive.map((e) => (
                <li key={e.id} className="text-[0.66rem] leading-snug text-zinc-300">
                  <span className="text-emerald-400">▸</span> {e.label}
                </li>
              ))}
            </ul>
            <div className="mt-2 text-[0.56rem]">
              <span className="text-zinc-600">you pulled {pulledKeys}/{c.keySourceIds.length} of the sources that answer this case</span>
              {c.keySourceIds.length > 0 && pulledKeys === 0 ? (
                <div className="mt-0.5 text-rose-300/90">called on thin evidence — that&apos;s luck, not a read. Pull the logs that answer the alert.</div>
              ) : pulledKeys >= c.keySourceIds.length ? (
                <div className="mt-0.5 text-emerald-400/80">thorough — you pulled the logs that answer this.</div>
              ) : null}
            </div>
          </div>
          <div className="rounded border border-cyan-900/40 bg-cyan-950/20 p-3">
            <div className="mb-1.5 text-[0.58rem] uppercase tracking-[0.16em] text-cyan-400/80">Learn it for real</div>
            <p className="text-[0.66rem] leading-snug text-zinc-300">{c.learn.concept}</p>
            {c.learn.mitre && (
              <div className="mt-2 inline-block rounded border border-zinc-700 px-1.5 py-0.5 text-[0.55rem] text-zinc-400">
                {c.learn.mitre.id} · {c.learn.mitre.name}
              </div>
            )}
            {c.learn.pointer && <div className="mt-1.5 text-[0.55rem] text-zinc-600">{c.learn.pointer}</div>}
          </div>
        </div>

        <div className="mt-3 flex items-center justify-between">
          <div className="text-[0.58rem] text-zinc-600">
            your call: <span className="text-zinc-400">{DISPOSITION_META[chosen].label}</span>
          </div>
          <button
            autoFocus
            onClick={onNext}
            className="rounded border border-cyan-500/50 bg-cyan-700/25 px-5 py-2 text-[0.78rem] font-semibold text-cyan-100 transition-colors hover:bg-cyan-600/35"
          >
            {shiftComplete(shift) ? "End shift ▸" : "Next alert ▸"}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── End-of-shift scorecard + career framing ──────────────────────────────────
function ShiftComplete({
  shift,
  reward,
  unlocked,
  onHub,
}: {
  shift: ShiftState;
  reward: ShiftReward | null;
  unlocked: { id: string; label: string }[];
  onHub: () => void;
}) {
  const score = scoreShift(shift, SOC_CASES_BY_ID);
  const gradeMeta = {
    clean: { label: "CLEAN SHIFT", tone: "text-emerald-300", line: "Sharp reads all night. Nothing dwelt, and you didn't bury Tier-2 in noise. This is what a good T1 looks like." },
    rough: { label: "ROUGH SHIFT", tone: "text-amber-300", line: "You held the line, but a few calls were off. Re-read the debriefs — the misses are where the learning is." },
    breached: { label: "BREACH ON YOUR WATCH", tone: "text-rose-300", line: "Something real got closed and dwelt. It happens to every analyst once — the lesson is which logs you skipped before you called it." },
  }[score.grade];

  return (
    <div className="mx-auto mt-6 max-w-2xl space-y-3">
      <div className="rounded-lg border border-zinc-800 bg-black/60 p-6 text-center">
        <div className="text-[0.6rem] uppercase tracking-[0.2em] text-zinc-500">Shift complete · 16:00 handover</div>
        <div className={`mt-2 text-2xl font-bold tracking-wide ${gradeMeta.tone}`}>{gradeMeta.label}</div>
        <p className="mx-auto mt-2 max-w-md text-[0.76rem] leading-relaxed text-zinc-400">{gradeMeta.line}</p>

        <div className="mt-5 grid grid-cols-2 gap-3 sm:grid-cols-4">
          <Stat label="Accuracy" value={`${Math.round(score.accuracy * 100)}%`} tone={score.accuracy >= 0.8 ? "text-emerald-300" : "text-amber-300"} />
          <Stat label="Calls" value={`${score.verdictCorrect}/${score.total}`} tone="text-zinc-200" />
          <Stat label="Missed threats" value={`${score.missedDetections}`} tone={score.missedDetections ? "text-rose-300" : "text-emerald-300"} />
          <Stat label="False escalations" value={`${score.falseEscalations}`} tone={score.falseEscalations ? "text-amber-300" : "text-emerald-300"} />
        </div>
        <div className="mt-3 text-[0.62rem] text-zinc-500">
          Investigation — pulled <span className="text-zinc-300">{Math.round(score.investigationRate * 100)}%</span> of the logs that answer these cases
          {score.blindCalls > 0 && (
            <span className="text-rose-300/90"> · {score.blindCalls} call{score.blindCalls > 1 ? "s" : ""} made blind (a right call reached blind is luck, not a read — it can&apos;t grade clean)</span>
          )}
        </div>
      </div>

      {reward && (
        <div className="rounded-lg border border-emerald-900/40 bg-emerald-950/15 p-4">
          <div className="mb-2 text-[0.6rem] uppercase tracking-[0.18em] text-emerald-400/80">Payout</div>
          <div className="flex flex-wrap items-center gap-4 text-[0.82rem]">
            <span className="text-amber-400">+{reward.cashGain}¢</span>
            <span className="text-emerald-300">+{reward.standingGain} ⬢ standing</span>
            {reward.rankUp && (
              <span className="rounded border border-emerald-500/40 bg-emerald-500/10 px-2 py-0.5 text-[0.72rem] text-emerald-200">
                promoted → {reward.rankUp.label}
              </span>
            )}
          </div>
          {unlocked.length > 0 && (
            <div className="mt-2.5 rounded border border-fuchsia-500/30 bg-fuchsia-500/5 px-2.5 py-1.5 text-[0.74rem] text-fuchsia-200/90">
              🔓 New queue unlocked — {unlocked.map((u) => u.label).join(" · ")}
            </div>
          )}
        </div>
      )}

      <div className="rounded-lg border border-cyan-900/40 bg-cyan-950/15 p-4">
        <div className="mb-1.5 text-[0.6rem] uppercase tracking-[0.18em] text-cyan-400/80">The ladder</div>
        <p className="text-[0.74rem] leading-relaxed text-zinc-400">
          This is the <span className="text-zinc-200">Tier-1</span> seat: monitor, triage, enrich, escalate. Consistent clean shifts are
          what move an analyst toward <span className="text-zinc-200">Tier-2</span> (deep investigation, malware analysis, containment) and on to
          <span className="text-zinc-200"> Tier-3</span> (threat hunting, detection engineering, forensics) — and it isn&apos;t automatic; the jump
          is earned. The real-world entry credential for this chair is <span className="text-zinc-300">BTL1 (Blue Team Level 1)</span>, which maps to the
          NICE &ldquo;Cyber Defense Analyst&rdquo; role.
        </p>
        <p className="mt-2 text-[0.62rem] leading-snug text-zinc-500">
          In-game framing only. Illustrative of the role, not a certification or training platform — and no pay figures are presented as fact.
        </p>
      </div>

      <div className="flex items-center justify-between gap-3">
        <Link href="/" className="rounded border border-zinc-700 px-4 py-2 text-[0.74rem] text-zinc-400 transition-colors hover:bg-zinc-800/60">
          ↩ back to the red seat
        </Link>
        <button onClick={onHub} className="rounded border border-emerald-500/50 bg-emerald-700/25 px-5 py-2 text-[0.78rem] font-semibold text-emerald-100 transition-colors hover:bg-emerald-600/35">
          Back to the desk ▸
        </button>
      </div>
    </div>
  );
}

function Stat({ label, value, tone }: { label: string; value: string; tone: string }) {
  return (
    <div className="rounded border border-zinc-800 bg-black/40 px-2 py-3">
      <div className={`text-lg font-bold tabular-nums ${tone}`}>{value}</div>
      <div className="text-[0.55rem] uppercase tracking-wider text-zinc-600">{label}</div>
    </div>
  );
}

// ── The career hub — home base: rank + progress, the queue board (locked/unlocked),
//    the analyst-kit shop (spend ¢), and the handler inbox (Vale / Mercer). ────────
const MSG_TONE: Record<string, string> = {
  warm: "border-emerald-500/30 text-emerald-300",
  warn: "border-amber-500/30 text-amber-300",
  tip: "border-cyan-500/30 text-cyan-300",
  milestone: "border-fuchsia-500/30 text-fuchsia-300",
};

function CareerHub({
  career,
  lastEvent,
  onStart,
  onBuy,
}: {
  career: CareerState;
  lastEvent: HandlerEvent;
  onStart: (i: number) => void;
  onBuy: (item: KitItem) => void;
}) {
  const rank = rankFor(career.standing);
  const nr = nextRank(career.standing);
  const messages = inboxFor(career, lastEvent);

  return (
    <div className="mx-auto mt-4 w-full max-w-[1200px] space-y-3">
      {/* Desk banner — rank + progress to the next rung */}
      <div className="rounded-lg border border-emerald-500/25 bg-black/60 p-5">
        <div className="flex items-center justify-between gap-4">
          <div>
            <div className="text-[0.6rem] uppercase tracking-[0.2em] text-emerald-300">The desk · your career</div>
            <div className="mt-1 text-lg font-semibold text-zinc-100">{rank.label}</div>
          </div>
          <div className="text-right text-[0.72rem] text-zinc-500">
            <div>
              ⬢ <span className="text-emerald-300">{career.standing}</span> standing · ¢ <span className="text-amber-400">{career.cash}</span>
            </div>
            {nr && <div className="mt-0.5">{nr.min - career.standing} to {nr.label}</div>}
          </div>
        </div>
        {nr && (
          <div className="mt-3 h-1.5 w-full overflow-hidden rounded-full bg-zinc-800/80">
            <div
              className="h-full rounded-full bg-emerald-500/60 transition-all duration-500"
              style={{ width: `${Math.min(100, Math.round((career.standing / nr.min) * 100))}%` }}
            />
          </div>
        )}
      </div>

      <div className="grid gap-3 lg:grid-cols-3">
        {/* Queue board + kit shop */}
        <div className="space-y-2 lg:col-span-2">
          <div className="text-[0.6rem] uppercase tracking-[0.18em] text-zinc-500">Queues — earn ⬢ to open harder work</div>
          {SHIFTS.map((s, i) => {
            const open = isUnlocked(career, s);
            const reqs = [
              career.standing < s.unlockStanding ? `⬢ ${s.unlockStanding}` : null,
              s.requiresRedRun && career.redRunsDone < 1 ? "a red-seat run" : null,
            ].filter(Boolean);
            return (
              <div
                key={s.id}
                className={`rounded border px-3 py-2.5 transition-colors ${open ? "border-zinc-700 bg-black/40" : "border-zinc-800/60 bg-black/20"}`}
              >
                <div className="flex items-center justify-between gap-3">
                  <div className={open ? "text-zinc-200" : "text-zinc-600"}>
                    <div className="text-[0.8rem] font-medium">{s.label}</div>
                    {!open ? (
                      <div className="text-[0.62rem] text-zinc-600">🔒 unlocks: {reqs.join(" + ")}{s.note ? ` · ${s.note}` : ""}</div>
                    ) : (
                      s.note && <div className="text-[0.6rem] text-zinc-600">{s.note}</div>
                    )}
                  </div>
                  {open ? (
                    <button
                      onClick={() => onStart(i)}
                      className="shrink-0 rounded border border-emerald-500/50 bg-emerald-700/25 px-3 py-1 text-[0.72rem] font-semibold text-emerald-100 transition-colors hover:bg-emerald-600/35"
                    >
                      Start ▸
                    </button>
                  ) : (
                    <span className="shrink-0 text-[0.6rem] text-zinc-700">🔒</span>
                  )}
                </div>
              </div>
            );
          })}

          <div className="mt-3 text-[0.6rem] uppercase tracking-[0.18em] text-zinc-500">Analyst kit — spend ¢</div>
          {KIT.map((item) => {
            const owned = owns(career, item.id);
            const afford = career.cash >= item.cost;
            return (
              <div key={item.id} className="rounded border border-zinc-800 bg-black/40 px-3 py-2.5">
                <div className="flex items-center justify-between gap-3">
                  <div>
                    <div className="text-[0.78rem] text-zinc-200">{item.label}</div>
                    <div className="text-[0.62rem] leading-snug text-zinc-500">{item.blurb}</div>
                  </div>
                  {owned ? (
                    <span className="shrink-0 rounded border border-emerald-600/40 px-2 py-1 text-[0.62rem] text-emerald-300">owned</span>
                  ) : (
                    <button
                      onClick={() => onBuy(item)}
                      disabled={!afford}
                      className="shrink-0 rounded border border-amber-500/40 bg-amber-500/5 px-3 py-1 text-[0.72rem] text-amber-200 transition-colors hover:bg-amber-500/15 disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      Buy · ¢{item.cost}
                    </button>
                  )}
                </div>
              </div>
            );
          })}
        </div>

        {/* Handler inbox — the point of contact */}
        <div className="space-y-2">
          <div className="text-[0.6rem] uppercase tracking-[0.18em] text-zinc-500">Inbox</div>
          {messages.length === 0 ? (
            <div className="rounded border border-zinc-800 bg-black/30 px-3 py-3 text-[0.66rem] text-zinc-600">Quiet for now.</div>
          ) : (
            messages.map((m) => (
              <div key={m.id} className={`rounded border bg-[#05080c] px-3 py-2.5 ${MSG_TONE[m.tone] ?? "border-zinc-700 text-zinc-300"}`}>
                <div className="flex items-center gap-2 text-[0.56rem] uppercase tracking-[0.16em]">
                  <span className="h-1.5 w-1.5 rounded-full bg-current" />
                  <span>{m.from}</span>
                  <span className="text-zinc-600">· {m.role}</span>
                </div>
                <div className="mt-1 text-[0.74rem] font-semibold text-zinc-100">{m.subject}</div>
                <p className="mt-0.5 text-[0.68rem] leading-relaxed text-zinc-400">{m.body}</p>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
}
