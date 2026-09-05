// SHA-pinned source slices (D4, D5, X4).
//
// Every region of the READ-ONLY web tree that this exporter hand-transcribes is
// delimited by two literal anchors and hashed. An edit to the taxonomy JSX,
// DISPOSITION_META, VERDICT_LABEL, the debrief headline ternary, gradeMeta, the
// coach STEPS, the handler bodies or the §3.2 handoff strings ABORTS the export with
//   stale pin: SocConsole.tsx#taxonomy
// A human then re-transcribes and re-pins. That is the only place drift can enter,
// and it is loud.
//
// S10 makes the RichSegment pins BIDIRECTIONAL: for a region marked `rich`, the
// export also asserts `segments.map(s => s.text).join("")` equals the JSX slice with
// tags stripped, entities decoded and whitespace normalised. Only the tone runs stay
// hand-authored.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { sha256Hex } from "@/app/lib/soc/exporter/canonical";

const REPO_ROOT = fileURLToPath(new URL("../../../../", import.meta.url));

export interface SourcePin {
  /** Repo-relative path. */
  file: string;
  /** Region id — the second half of the abort message. */
  id: string;
  startAnchor: string;
  endAnchor: string;
  sha256: string;
  purpose: string;
  /** true → the region is transcribed as RichSegment[] and pinned bidirectionally (S10). */
  rich?: boolean;
}

export const SOURCE_PINS: SourcePin[] = [
  // ── SocConsole.tsx ─────────────────────────────────────────────────────────
  {
    file: "app/components/soc/SocConsole.tsx",
    id: "taxonomy",
    startAnchor: "You&apos;re the Tier-1 analyst.",
    endAnchor: '<span className="text-rose-300">True Positive</span>.',
    sha256: "1fba22c9f8a418dd52a40de06aef385ce5254ac1a2ffd76fe133884ee8f070e6",
    purpose: "copy.intro.taxonomy — the DEF-A three-verdict paragraph",
    rich: true,
  },
  {
    file: "app/components/soc/SocConsole.tsx",
    id: "severity",
    startAnchor: "The tool&apos;s severity label is a <em>guess</em>",
    endAnchor: "never isolate a sanctioned operation.",
    sha256: "0c0e447c5966a7c310ecd3aa90da3be69659da3671cc214379360755bb6a9790",
    purpose: "copy.intro.severity — the tool-severity-is-a-guess paragraph",
    rich: true,
  },
  {
    file: "app/components/soc/SocConsole.tsx",
    id: "meters-line",
    startAnchor: "Miss a real one and it dwells",
    endAnchor: "Triage the board.",
    sha256: "923edda01e7e0989e05716ddbf47fd2a213672d409238659f086efe754ec5f56",
    purpose: "the briefing's two-meter line — the source of copy.meters' fear voice",
  },
  {
    file: "app/components/soc/SocConsole.tsx",
    id: "handoff-panel",
    startAnchor: "Tonight&apos;s queue is different:",
    endAnchor: "Same board, two seats.",
    sha256: "04733daab79f47e42027cbab7c8ed6ac3065acb0590257c570427ac2cb87c758",
    purpose: "copy.intro.handoff.redSeat — the web briefing's crossover panel",
    rich: true,
  },
  {
    file: "app/components/soc/SocConsole.tsx",
    id: "disposition-meta",
    startAnchor: "const DISPOSITION_META",
    endAnchor: '"escalate-ir-isolate": { label: "Escalate → IR + isolate host", sub: "active threat — contain now", tone: "rose" },',
    sha256: "161f1cb7d62bc6af798c6e856d12763c617de8f7323d2bf6c6e6ed3f6435546d",
    purpose: "copy.dispositionMeta — the four call buttons (the taxonomy slot)",
  },
  {
    file: "app/components/soc/SocConsole.tsx",
    id: "verdict-label",
    startAnchor: "const VERDICT_LABEL",
    endAnchor: '"benign-true-positive": "Benign True Positive",',
    sha256: "1850f50c12a88631ca4f96d285052b59aabcc31a75eed9d97f449ef485849b82",
    purpose: "copy.verdictLabels",
  },
  {
    file: "app/components/soc/SocConsole.tsx",
    id: "severity-tone",
    startAnchor: "const SEVERITY_TONE",
    endAnchor: 'Critical: "text-rose-300 border-rose-600/50",',
    sha256: "9a982540a73f3ffa0a833954a17ea8ffb0427129baf38bdd6aa0dadd02a84f70",
    purpose: "copy.severityMeta — the four tool-severity chips (S5)",
  },
  {
    file: "app/components/soc/SocConsole.tsx",
    id: "msg-tone",
    startAnchor: "const MSG_TONE",
    endAnchor: 'milestone: "border-fuchsia-500/30 text-fuchsia-300",',
    sha256: "60333c97bc2451318363fb22d0a7d076cf3f6026609db5cc9609633fdc3e5ac3",
    purpose: "copy.handlerToneMeta — the four inbox tones (S5)",
  },
  {
    file: "app/components/soc/SocConsole.tsx",
    id: "bpm",
    startAnchor: "const BPM:",
    endAnchor: "LOCKDOWN: 150 };",
    sha256: "b6661c5a183c3381af2a7abee65a1f8fcfc7c6bc4333f02334948e7dd3721d3a",
    purpose: "tuning.bpm — the heartbeat rate per status",
  },
  {
    file: "app/components/soc/SocConsole.tsx",
    id: "debrief-headlines",
    startAnchor: '{right ? "Good call"',
    endAnchor: ': "Wrong call"}',
    sha256: "eb0bfd217ea9947a9152a090242479f109316d9a7c92cf5a5ac5ba7fde058a96",
    purpose: "copy.debriefHeadlines — the three debrief eyebrows",
  },
  {
    file: "app/components/soc/SocConsole.tsx",
    id: "debrief-coverage",
    startAnchor: "you pulled {pulledKeys}/{c.keySourceIds.length} of the sources that answer this case",
    endAnchor: "thorough — you pulled the logs that answer this.",
    sha256: "9e498d797c51e1361a1ded962f1e12a09da900e44fbabc320760511eb26bfbd7",
    purpose: "chrome.debriefCoverage / .debriefBlind / .debriefThorough",
  },
  {
    file: "app/components/soc/SocConsole.tsx",
    id: "grade-meta",
    startAnchor: "const gradeMeta = {",
    endAnchor: "}[score.grade];",
    sha256: "3d5e3d7018c62d1608a0757e8f7058b7b837f48cb17c5ae9d30e08465c8c6db2",
    purpose: "copy.gradeMeta — CLEAN / ROUGH / BREACH headlines and lines",
  },
  {
    file: "app/components/soc/SocConsole.tsx",
    id: "summary-investigation",
    startAnchor: "Investigation — pulled",
    endAnchor: "it can&apos;t grade clean)",
    sha256: "bc4a36639ac272402f2e2ca3d7d85eea5dd9f118a5cc94585717e35ee7f4ca96",
    purpose: "copy.summary.investigationLine / .blindLine",
  },
  {
    file: "app/components/soc/SocConsole.tsx",
    id: "ladder",
    startAnchor: 'This is the <span className="text-zinc-200">Tier-1</span> seat',
    endAnchor: "NICE &ldquo;Cyber Defense Analyst&rdquo; role.",
    sha256: "c16246d5e738d831d883890b0bda932810617ef9da75752163cd92c6510b3ed4",
    purpose: "copy.ladder.body — the Tier-1 → Tier-2 → Tier-3 paragraph",
    rich: true,
  },
  {
    file: "app/components/soc/SocConsole.tsx",
    id: "ladder-note",
    startAnchor: "In-game framing only.",
    endAnchor: "no pay figures are presented as fact.",
    sha256: "06f799e670c191d5705d894e4d58ea15f584fafef03743edbed104b8b9541946",
    purpose: "the web's ladder disclaimer — copy.ladder.note re-voices it per DESIGN Appendix A G21",
  },
  {
    file: "app/components/soc/SocConsole.tsx",
    id: "disclaimer",
    startAnchor: "Fiction simulator. Cases are illustrative",
    endAnchor: "never a working technique.",
    sha256: "502a8da7b3d3c5b16386b2a0c749050bfc45fdbec6de4aca3b59508e32ad5117",
    purpose: "copy.intro.disclaimer",
  },
  {
    file: "app/components/soc/SocConsole.tsx",
    id: "demo-complete",
    startAnchor: '} else if (screen === "complete") {',
    endAnchor: 'setPhase("complete");',
    sha256: "3c9611e31ced978cbd8130d59d86946853d5190fd3b4c59219478ecc1c49eb29",
    purpose: "the D13 golden run — shift-runs.json#demo-complete is scripted from this block",
  },

  // ── SocOnboarding.tsx ──────────────────────────────────────────────────────
  {
    file: "app/components/soc/SocOnboarding.tsx",
    id: "coach-steps",
    startAnchor: "const STEPS: Step[] = [",
    endAnchor: "// terminal: SocConsole persists completion on the first real call; or dismiss here.",
    sha256: "6a87d7b045a2cfa5191253fe2a40a1570662b239c427dfd8782a8c701868157f",
    purpose: "copy.coachSteps — the three first-shift coach bubbles (S4 overrides applied)",
  },

  // ── handler.ts ─────────────────────────────────────────────────────────────
  {
    file: "app/lib/career/handler.ts",
    id: "inbox-bodies",
    startAnchor: "export function inboxFor",
    endAnchor: "return out.slice(0, 4);",
    sha256: "2e625877742b52ac5daa20e6795e6768b08b2d266118b0e14c90fea052a47642",
    purpose: "copy.handler.templates — every Vale/Mercer subject and body",
  },
  {
    file: "app/lib/career/handler.ts",
    id: "senders",
    startAnchor: "const VALE = {",
    endAnchor: 'const MERCER = { from: "Mercer", role: "handler · red seat" };',
    sha256: "e953eb25b515d76593cfe36abcfaf94c4f91c81ed21a79f3c37106f5daa204f5",
    purpose: "copy.handler.senders",
  },

  // ── the five §3.2 strings (D4) ─────────────────────────────────────────────
  {
    file: "app/lib/soc/handoff.ts",
    id: "handoff-why",
    startAnchor: "const why = run.authorized",
    endAnchor: "not who ran it.`;",
    sha256: "4acfa6a68a5a6c0cda1bee01c69f793f538f4f5f0a9fafc957242a74c5e31f28",
    purpose: "§3.2 row 1 — the generated `why` opener the blue-only override re-voices",
  },
  {
    file: "app/lib/soc/cases.ts",
    id: "edr-test-why",
    startAnchor: '"The detection is correct — that really is an offensive-security tool',
    endAnchor: "(Your own red-seat run, seen from the blue chair.)\",",
    sha256: "0d52364cfc98cc59f8ac1e81e57ad196440185f00e9b8f669e3ea64bbcced3e8",
    purpose: "§3.2 row 3 — soc-edr-test's red-seat aside",
  },
  {
    file: "app/lib/soc/cases.ts",
    id: "auth-pentest-why",
    startAnchor: '"This looks exactly like an attack because it IS attack behaviour',
    endAnchor: "note it on the ticket, close benign.\",",
    sha256: "c30dd3ed06a9e8dbada66b1f57a6dcc190103f44b111f992112bd8befa5320b4",
    purpose: "§3.2 row 4 — soc-auth-pentest's two-seats aside",
  },
  {
    file: "app/lib/soc/cases.ts",
    id: "shifts",
    startAnchor: "export const SHIFTS: ShiftDef[] = [",
    endAnchor: "unlockStanding: 210,",
    sha256: "4bbc090c9df4705bcc61987796b1f920825b30e3004c986aa8f54b3618327b9d",
    purpose: "the 0/40/90/90+redrun/210 ladder the blue-only override remaps to 0/40/80/120/160",
  },
];

const fileCache = new Map<string, string>();

function readRepoFile(rel: string): string {
  const hit = fileCache.get(rel);
  if (hit !== undefined) return hit;
  const text = readFileSync(`${REPO_ROOT}${rel}`, "utf8");
  fileCache.set(rel, text);
  return text;
}

/** The exact source text between (and including) a pin's two anchors. */
export function sliceFor(pin: SourcePin): string {
  const text = readRepoFile(pin.file);
  const start = text.indexOf(pin.startAnchor);
  if (start < 0) throw new Error(`stale pin: ${pin.file}#${pin.id} — start anchor not found`);
  const endAt = text.indexOf(pin.endAnchor, start);
  if (endAt < 0) throw new Error(`stale pin: ${pin.file}#${pin.id} — end anchor not found`);
  return text.slice(start, endAt + pin.endAnchor.length);
}

export function pin(id: string): SourcePin {
  const p = SOURCE_PINS.find((x) => x.id === id);
  if (!p) throw new Error(`unknown source pin: ${id}`);
  return p;
}

/** JSX slice → plain text: tags stripped, `{" "}` folded, entities decoded, whitespace normalised. */
export function jsxToText(src: string): string {
  return src
    .replace(/\{"\s*"\}/g, " ")
    .replace(/<[^>]*>/g, "")
    .replace(/&apos;/g, "'")
    .replace(/&ldquo;/g, "“")
    .replace(/&rdquo;/g, "”")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/\s+/g, " ")
    .trim();
}

/** The plain text a `rich` pin's RichSegment[] must reproduce exactly (S10). */
export function pinnedText(id: string): string {
  return jsxToText(sliceFor(pin(id)));
}

/** Verify every pin. Throws `stale pin: <file>#<id>` on the first mismatch. */
export function verifyPins(): void {
  for (const p of SOURCE_PINS) {
    const actual = sha256Hex(sliceFor(p));
    if (p.sha256 !== actual) {
      throw new Error(
        `stale pin: ${p.file}#${p.id}\n` +
          `  expected sha256 ${p.sha256}\n` +
          `  actual   sha256 ${actual}\n` +
          `  purpose: ${p.purpose}\n` +
          `  Re-transcribe the exporter copy for this region, then re-pin.`
      );
    }
  }
}

/** Dev helper: the sha256 every pin currently hashes to (used to re-pin by hand). */
export function currentPinHashes(): { id: string; file: string; sha256: string }[] {
  return SOURCE_PINS.map((p) => ({ id: p.id, file: p.file, sha256: sha256Hex(sliceFor(p)) }));
}
