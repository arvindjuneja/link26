// Every player-facing string the app draws, plus the RichSegment[] paragraphs (D5).
//
// Anything that already exists on the web is lifted VERBATIM from the SHA-pinned
// regions in `sourcePins.ts`; the four colour-run paragraphs are hand-transcribed and
// asserted BOTH ways (S10) — the pin catches a web edit, and `verifyRichCopy` catches
// a transcription that no longer reproduces the JSX text.
//
// The 11 `outcomes` strings are transcribed from `engine.ts` and cross-asserted
// against `gradeCall` for all 96 (case × disposition) pairs at export time (D2), so a
// wording change there aborts the export naming the pair.

import { CHROME } from "@/app/lib/soc/exporter/chrome";
import { pinnedText } from "@/app/lib/soc/exporter/sourcePins";
import {
  CONTENT_SCHEMA_VERSION,
  type ExportedCopy,
  type MeterKey,
  type RichSegment,
} from "@/app/lib/soc/exporter/schema";

// ── the four colour-run paragraphs (D5) ──────────────────────────────────────

/** SocConsole.tsx briefing — the DEF-A taxonomy. Pin: SocConsole.tsx#taxonomy. */
const TAXONOMY: RichSegment[] = [
  { text: "You're the Tier-1 analyst. One question decides every alert on that queue: " },
  { text: "did the attack behaviour the rule hunts for actually happen?", tone: "strong" },
  { text: " If it didn't, and ordinary activity only looked like it, that's a " },
  { text: "False Positive", tone: "cyan" },
  { text: "; if it did but a pentest, change ticket or known tool sanctioned it, that's a " },
  { text: "Benign True Positive", tone: "emerald" },
  { text: "; if it did and nothing sanctioned it, that's a " },
  { text: "True Positive", tone: "rose" },
  { text: "." },
];

/** SocConsole.tsx briefing — the severity-is-a-guess paragraph. Pin: #severity. */
const SEVERITY_PARAGRAPH: RichSegment[] = [
  { text: "The tool's severity label is a " },
  { text: "guess", tone: "em" },
  {
    text:
      " — most of what it screams about is noise. Your job is to pull the right logs, read what actually happened, and make the call. Escalate a real threat; don't bury Tier-2 in noise; and never isolate a sanctioned operation.",
  },
];

/** SocConsole.tsx briefing — the web's crossover panel. Pin: #handoff-panel. */
const HANDOFF_RED_SEAT: RichSegment[] = [
  { text: "Tonight's queue is different: " },
  { text: "every alert is a run YOU pulled off in the red seat", tone: "strong" },
  {
    text:
      ", seen from this chair. The tradecraft is real attack behaviour — the tells you left. The only question that decides the verdict is whether an engagement ",
  },
  { text: "authorized", tone: "em" },
  { text: " it: a " },
  { text: "sanctioned", tone: "emerald" },
  { text: " run (RoE on file) is a Benign-TP; the one you ran " },
  { text: "off-book", tone: "rose" },
  { text: ", with no engagement behind it, is a real intrusion you escalate — " },
  { text: "authorization, not authorship", tone: "strong" },
  { text: ". Same board, two seats." },
];

/**
 * The blue-only crossover panel (DESIGN.md §3.2 row 5, §2.4's wireframe). NEW copy —
 * seat-neutral, because iOS ships no red seat, so "a run YOU pulled off" is a claim
 * about something the player never did. Not SHA-pinned; there is nothing to pin to.
 */
const HANDOFF_BLUE_ONLY: RichSegment[] = [
  { text: "Tonight's queue is different: " },
  { text: "every alert is a contracted red team's run, seen from your chair", tone: "strong" },
  {
    text:
      ". The tradecraft is real attack behaviour — the tells they left. The only question that decides the verdict is whether an engagement ",
  },
  { text: "authorized", tone: "em" },
  { text: " it: a " },
  { text: "sanctioned", tone: "emerald" },
  { text: " run (RoE on file) is a Benign-TP; the one with " },
  { text: "no engagement behind it", tone: "rose" },
  { text: " is a real intrusion you escalate — " },
  { text: "authorization, not authorship", tone: "strong" },
  { text: ". Same board, the other seat." },
];

/** SocConsole.tsx shift summary — the Tier-1 → Tier-3 ladder. Pin: #ladder. */
const LADDER_BODY: RichSegment[] = [
  { text: "This is the " },
  { text: "Tier-1", tone: "strong" },
  { text: " seat: monitor, triage, enrich, escalate. Consistent clean shifts are what move an analyst toward " },
  { text: "Tier-2", tone: "strong" },
  { text: " (deep investigation, malware analysis, containment) and on to " },
  { text: "Tier-3", tone: "strong" },
  {
    text:
      " (threat hunting, detection engineering, forensics) — and it isn't automatic; the jump is earned. The real-world entry credential for this chair is ",
  },
  { text: "BTL1 (Blue Team Level 1)", tone: "strong" },
  { text: ", which maps to the NICE “Cyber Defense Analyst” role." },
];

/** DESIGN.md Appendix A · G21 — the re-voiced ladder disclaimer. */
const LADDER_NOTE =
  "Credentials people in this chair often cite: BTL1, NICE 'Cyber Defense Analyst'. This is fiction — not a certification, not a training platform, and it makes no claims about hiring or pay.";

// ── the fiction disclaimer, printed twice (§5.11) ────────────────────────────

/**
 * The first-run gate's block AND the About screen's fiction block are THE SAME text —
 * the App Store fiction-disclaimer requirement, asserted by the drift guard.
 */
const FICTION_BLOCK =
  "Every organisation, host, user and log line in this game is fabricated. Cases show how a Tier-1 analyst reads evidence — the concepts and the workflow, never a working technique. Not a training platform, not a certification, and it makes no claims about hiring or pay. MITRE ATT&CK® ids are lookup labels only.";

// ── meters ───────────────────────────────────────────────────────────────────

const METERS: Record<MeterKey, { label: string; fear: string }> = {
  breach: { label: "BREACH RISK", fear: "a real threat you closed is dwelling undetected" },
  noise: { label: "NOISE / FATIGUE", fear: "crying wolf — Tier-2 stops trusting your tickets" },
  time: { label: "TIME", fear: "a soft budget — surfaced, never scored" },
};

const METER_ORDER: MeterKey[] = ["breach", "noise", "time"];

// ── the copy pack ────────────────────────────────────────────────────────────

export const COPY: ExportedCopy = {
  schemaVersion: CONTENT_SCHEMA_VERSION,
  contentHash: "",
  chrome: CHROME,

  verdictLabels: {
    "true-positive": "True Positive",
    "false-positive": "False Positive",
    "benign-true-positive": "Benign True Positive",
  },

  dispositionMeta: {
    "close-false-positive": {
      label: "Close · False Positive",
      sub: "didn't happen — the rule misread it",
      tone: "cyan",
    },
    "close-benign": {
      label: "Close · Benign (authorized)",
      sub: "it happened — and it was sanctioned",
      tone: "emerald",
    },
    "escalate-tier2": {
      label: "Escalate → Tier 2",
      sub: "suspicious / confirmed — hand up",
      tone: "amber",
    },
    "escalate-ir-isolate": {
      label: "Escalate → IR + isolate host",
      sub: "active threat — contain now",
      tone: "rose",
    },
  },

  // Transcribed from engine.ts's `gradeCall`; cross-asserted over all 96 pairs (D2).
  outcomes: {
    "tp.missed": "MISSED DETECTION — a live threat was closed and is now dwelling undetected.",
    "tp.escalated-correct": "Good call — escalated a genuine threat with the right urgency.",
    "tp.over-contained":
      "Right verdict, but over-reacted — this one should be handed up (HR/legal), not isolated. Isolating tips them off and burns the case.",
    "tp.under-contained":
      "Right verdict, but under-contained — the threat had room to move before IR caught up.",
    "fp.closed-fp": "Correct — recognized the noise and closed it without burning Tier-2 cycles.",
    "fp.closed-as-benign":
      "Closed it (good), but as 'authorized' rather than 'false positive' — nothing the rule hunts for happened.",
    "fp.escalated":
      "False escalation — you sent noise up the chain. Do this often and Tier-2 stops trusting your tickets.",
    "btp.closed-benign": "Correct — found the authorization and closed it as a benign true positive.",
    "btp.closed-as-fp":
      "Closed it (fine), but it wasn't a false positive — the behaviour really happened; it was just sanctioned.",
    "btp.escalated-t2":
      "Escalated authorized activity — Tier-2 will bounce it back. The change ticket was right there.",
    "btp.isolated":
      "You isolated a sanctioned operation — ops impact, and an angry change-owner. Always check for authorization first.",
  },

  debriefHeadlines: {
    good: "Good call",
    verdictOnly: "Right verdict, off on the response",
    wrong: "Wrong call",
  },

  gradeMeta: {
    clean: {
      label: "CLEAN SHIFT",
      line: "Sharp reads all night. Nothing dwelt, and you didn't bury Tier-2 in noise. This is what a good T1 looks like.",
      tone: "emerald",
    },
    rough: {
      label: "ROUGH SHIFT",
      line: "You held the line, but a few calls were off. Re-read the debriefs — the misses are where the learning is.",
      tone: "amber",
    },
    breached: {
      label: "BREACH ON YOUR WATCH",
      line: "Something real got closed and dwelt. It happens to every analyst once — the lesson is which logs you skipped before you called it.",
      tone: "rose",
    },
  },

  // S5 — SEVERITY_TONE (SocConsole.tsx:69-74), amended by R2. The web's HIGH is
  // orange; folding it into amber was wrong, because amber already carries "escalate
  // to Tier-2" on the call sheet, so a HIGH chip in amber read as a recommendation
  // rather than as the tool's guess. `Tone` therefore gains `orange` — the HUNT hue
  // of the status ramp — and C7's `Theme` maps it.
  severityMeta: {
    entries: {
      Low: { label: "LOW", tone: "muted" },
      Medium: { label: "MEDIUM", tone: "amber" },
      High: { label: "HIGH", tone: "orange" },
      Critical: { label: "CRITICAL", tone: "rose" },
    },
    fallback: "muted",
  },

  // S5 — MSG_TONE (SocConsole.tsx:781-786). `label` is the VoiceOver word for the dot.
  handlerToneMeta: {
    entries: {
      warm: { label: "good news", tone: "emerald" },
      warn: { label: "heads up", tone: "amber" },
      tip: { label: "tip", tone: "cyan" },
      milestone: { label: "milestone", tone: "fuchsia" },
    },
    fallback: "muted",
  },

  intro: {
    eyebrow: "Shift handover · 08:00",
    title: "{n} alerts on the board.",
    taxonomy: TAXONOMY,
    severity: SEVERITY_PARAGRAPH,
    meters: METER_ORDER.map((key) => ({ key, label: METERS[key].label, fear: METERS[key].fear })),
    handoff: { blueOnly: HANDOFF_BLUE_ONLY, redSeat: HANDOFF_RED_SEAT },
    cta: "Start the shift ▸",
    disclaimer:
      "Fiction simulator. Cases are illustrative, not a training platform — every log line is fabricated and teaches the analyst's read, never a working technique.",
  },

  // SocOnboarding.tsx STEPS (pin: SocOnboarding.tsx#coach-steps) with the two S4
  // overrides applied:
  //   step 1  "click it" → "tap it"
  //   step 2  "Pull more logs on the left …" → the R4 body, approved by the lead.
  // C1 flagged that S4's literal replacement said the same thing twice ("findings
  // land under EVIDENCE" in a bubble already anchored to EVIDENCE) and dropped the
  // "if you're not sure" that made the sentence an offer rather than an order. R4
  // is the ruling: keep the offer, name the tab the phone actually has, say it once.
  coachSteps: [
    {
      anchor: "sources",
      title: "Pull the log that answers the question",
      body: "Each source shows the question it answers — that's the skill. Start with the process tree: tap it.",
      button: null,
      advance: "on-first-source-pulled",
    },
    {
      anchor: "evidence",
      title: "Read what actually happened",
      body: "Findings land here — the evidence, not the tool's 'High' guess. Not sure yet? Pull more logs from SOURCES. When you can justify a call, hit Got it.",
      button: "Got it ▸",
      advance: "button",
    },
    {
      anchor: "call",
      title: "Now make the call",
      body:
        "True Positive, False Positive, or Benign (authorized)? Pick one — full debrief either way.\n" +
        "Didn't happen → False Positive. Happened + sanctioned → Benign-TP. Happened + unsanctioned → True Positive.\n" +
        "FP means the rule's logic is wrong — change what it fires on. Benign-TP means the rule is right — scope an exception and leave the logic alone.",
      button: null,
      advance: "terminal",
    },
  ],

  ladder: {
    eyebrow: "The ladder",
    body: LADDER_BODY,
    note: LADDER_NOTE,
  },

  summary: {
    eyebrow: "Shift complete · 16:00 handover",
    investigationLine: "Investigation — pulled {pct}% of the logs that answer these cases",
    blindLine: "{blind} — a right call reached blind is luck, not a read; it can't grade clean.",
  },

  firstRun: {
    title: "Fiction simulator",
    body: FICTION_BLOCK,
    cta: "I understand",
  },

  about: {
    fiction: FICTION_BLOCK,
    privacy: "No account. No network. No analytics. Your career is stored only on this device.",
    promise: "No ads, no pay-to-win, no timers, no loot boxes, no data selling.",
    credits:
      "MITRE ATT&CK® technique ids are cited as lookup labels only. IBM Plex Mono and Space Grotesk ship under the SIL Open Font Licence.",
  },

  meters: METERS,

  handler: {
    senders: {
      vale: { from: "Vale", role: "your shift lead" },
      mercer: { from: "Mercer", role: "handler · red seat" },
    },
    // Verbatim from handler.ts (pin: handler.ts#inbox-bodies), with the named
    // placeholders the TS builds by interpolation. The `*-blue-only` variants are the
    // DESIGN.md §3.2 re-voicings the iOS handler uses in place of Mercer's lines.
    templates: {
      "ev-clean": {
        sender: "vale",
        tone: "warm",
        subject: "Clean shift — nice work",
        body: "Sharp reads all the way through. +40 standing. Keep them clean and you're {gap} short of {rank} — then I open a harder queue for you.",
      },
      "ev-clean-max": {
        sender: "vale",
        tone: "warm",
        subject: "Clean shift — nice work",
        body: "Sharp reads all the way through. +40 standing. You're at the top of what I can put you up for — Tier-2's next, and that's earned, not given.",
      },
      "ev-rough": {
        sender: "vale",
        tone: "warn",
        subject: "Rough one — that's the job",
        body: "A few calls were off. It happens to everyone on this desk. Re-read the debriefs — the misses are where the read gets sharper. Standing barely moved; clean shifts are how you climb, not volume.",
      },
      "ev-breach": {
        sender: "vale",
        tone: "warn",
        subject: "Something got past you",
        body: "A real one got closed and dwelt. Every analyst has that night once. The lesson is which log you skipped before you called it — pull the answering source next time. We're still in your corner.",
      },
      "ev-rankup": {
        sender: "vale",
        tone: "milestone",
        subject: "You made {rank}",
        body: "That's {rank}. I flagged you to the lead. This is the ladder, and you're climbing it the right way — by being right.",
      },
      "ev-rankup-t2": {
        sender: "mercer",
        tone: "milestone",
        subject: "You made {rank}",
        body: "Mercer here. Your shift lead's been talking you up. You've got the read now — and the other chair's a lot easier once you've sat in this one. When you're ready.",
      },
      "ev-rankup-t2-blue-only": {
        sender: "vale",
        tone: "milestone",
        subject: "You made {rank}",
        body: "That's Tier-2 · candidate. The desk is yours to run now — and Tier-2 is earned, not given. You earned it.",
      },
      "ev-unlock": {
        sender: "vale",
        tone: "milestone",
        subject: "New queue: {queue}",
        body: "{queue} is open to you now — you earned it. Harder alerts, same read.",
      },
      "ev-unlock-handoff": {
        sender: "mercer",
        tone: "milestone",
        subject: "The other chair is open to you",
        body: "Mercer. Your lead says you're ready to see the runs I sent you from the blue side. That's Shift 4 — the same board, the other chair. Go find out what your own tradecraft looks like to a defender.",
      },
      "ev-unlock-handoff-blue-only": {
        sender: "vale",
        tone: "milestone",
        subject: "The other chair is open to you",
        body: "A contracted red team ran three engagements against us this month. One of them was never sanctioned. Shift 4 is their board, from your chair — go find it.",
      },
      "tip-redrun": {
        sender: "mercer",
        tone: "tip",
        subject: "Come sit in the other chair",
        body: "Mercer. Your lead says you've got the reads down. Want to see what you're actually defending against? Run one contract in the red seat — do that and the handoff desk opens: your own tradecraft, seen from the blue side.",
      },
      "tip-kit": {
        sender: "vale",
        tone: "tip",
        subject: "You've banked enough for the intel feed",
        body: "You're at {cash}¢ — enough for the {item}. Grab it before your next shift; it pre-pulls enrichment on every case and saves you shift-time. This is what the cash is for.",
      },
      welcome: {
        sender: "vale",
        tone: "warm",
        subject: "Welcome to the desk",
        body: "I'm Vale — I run this shift. New here? Start with the fundamentals queue. Clean shifts move you up the ladder and I'll open harder work as you earn it; the cash from the job buys kit that makes you faster. You're not alone on this — ping me any time. Go get one.",
      },
    },
  },
};

/** The plain text a RichSegment[] renders to. */
export function flatten(segments: RichSegment[]): string {
  return segments.map((s) => s.text).join("");
}

/**
 * S10 — the second half of every `rich` pin. The pin proves the JSX has not changed;
 * this proves the hand-transcription still reproduces it, character for character.
 */
export function verifyRichCopy(): void {
  const checks: [string, RichSegment[]][] = [
    ["taxonomy", COPY.intro.taxonomy],
    ["severity", COPY.intro.severity],
    ["handoff-panel", COPY.intro.handoff.redSeat],
    ["ladder", COPY.ladder.body],
  ];
  for (const [id, segments] of checks) {
    const expected = pinnedText(id);
    const actual = flatten(segments);
    if (expected !== actual) {
      throw new Error(
        `rich transcription drift: ${id}\n` +
          `  JSX  : ${JSON.stringify(expected)}\n` +
          `  COPY : ${JSON.stringify(actual)}`
      );
    }
  }
}
