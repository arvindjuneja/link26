// The blue-only overrides (D4, B1) — applied to the EXPORT, never to the web tree.
//
// `SHIFTS` and `caseFromRedRun` are never mutated and never gain a `voice` option, so
// `state.test.ts`'s two red-run assertions and `handoff.test.ts` stay green untouched
// (D1). Each override pins the sha256 of the SOURCE value it rewrites; if the web copy
// moves, the export aborts with `stale override: soc-handoff-the-key.why` and a human
// re-transcribes.
//
// Two changes, both from `docs/ios/DESIGN.md` §3:
//   §3.1 the ladder — 0 / 40 / 80 / 120 / 160, `requiresRedRun: false` on EVERY shift
//        (B1: iOS has no red seat, so a cross-seat gate would be unopenable), and the
//        handoff shift's label + note re-voiced seat-neutral;
//   §3.2 the five re-voiced strings — the generated handoff `why` opener, the two
//        cases.ts asides, the handoff shift note, and the briefing handoff panel
//        (which lives in copy.ts as `intro.handoff.blueOnly`).

import { sha256Hex } from "@/app/lib/soc/exporter/canonical";

export interface BlueOnlyOverride {
  /** The abort id — `stale override: <id>`. */
  id: string;
  /** sha256 of the exact source text this override rewrites. */
  sha256: string;
  purpose: string;
  rewrite: (src: string) => string;
}

/** §3.1 — the blue-only standing ladder, keyed by shift id. */
export const BLUE_ONLY_UNLOCK_STANDING: Record<string, number> = {
  "first-shift": 0,
  "second-shift": 40,
  "lockout-shift": 80,
  "handoff-shift": 120,
  "insider-shift": 160,
};

/** §3.1 — the handoff shift, re-voiced so it reads from the blue chair only. */
export const BLUE_ONLY_HANDOFF_SHIFT = {
  label: "Shift 4 · the other chair (a red team's runs)",
  note: "Adjudicate a contracted red team's tradecraft from the blue side.",
};

const HANDOFF_WHY_OPENER_FROM =
  "This alert IS a run you performed in the red seat — the same board, from the blue chair.";
const HANDOFF_WHY_OPENER_TO =
  "This alert IS a red-team engagement's run, seen from your chair — the same board, the other seat.";

const EDR_TEST_ASIDE_FROM = "(Your own red-seat run, seen from the blue chair.)";
const EDR_TEST_ASIDE_TO = "(A red-team engagement's run, seen from the blue chair.)";

const AUTH_PENTEST_ASIDE_FROM =
  "(It's also the bridge between the two seats — a red-team run, seen from the blue chair, is a Benign-TP.)";
const AUTH_PENTEST_ASIDE_TO =
  "(It's also the bridge to the red team's world: same tradecraft, opposite verdict.)";

function replaceOnce(src: string, from: string, to: string, id: string): string {
  const at = src.indexOf(from);
  if (at < 0) throw new Error(`stale override: ${id} — the pinned fragment is no longer present`);
  return src.slice(0, at) + to + src.slice(at + from.length);
}

/**
 * Every override, pinned by the sha256 of the value it rewrites. The `sha256` fields
 * are filled from the live corpus by `npm run soc:export`'s first run and must be
 * re-pinned by hand whenever the web copy legitimately changes.
 */
export const BLUE_ONLY_OVERRIDES: BlueOnlyOverride[] = [
  {
    id: "soc-handoff-the-key.why",
    sha256: "3ff4f991d76260053112e2c2835151e51e5af0ebb1fe1450ffe87a4d11fd88a1",
    purpose: "§3.2 row 1 — the red-seat authorship opener becomes seat-neutral",
    rewrite: (s) => replaceOnce(s, HANDOFF_WHY_OPENER_FROM, HANDOFF_WHY_OPENER_TO, "soc-handoff-the-key.why"),
  },
  {
    id: "soc-handoff-burn-notice.why",
    sha256: "74672b328bc8ea2f1358e88a62c5e62155a3339b4c38b4516ba2b2601a1ff439",
    purpose: "§3.2 row 1 — the red-seat authorship opener becomes seat-neutral",
    rewrite: (s) => replaceOnce(s, HANDOFF_WHY_OPENER_FROM, HANDOFF_WHY_OPENER_TO, "soc-handoff-burn-notice.why"),
  },
  {
    id: "soc-edr-test.why",
    sha256: "766f3e44275e5047755aa9b555fd8545fde8bb7c4effcded3255afa79653eb91",
    purpose: "§3.2 row 3 — the parenthetical aside drops 'your own'",
    rewrite: (s) => replaceOnce(s, EDR_TEST_ASIDE_FROM, EDR_TEST_ASIDE_TO, "soc-edr-test.why"),
  },
  {
    id: "soc-auth-pentest.why",
    sha256: "0f1f3b78a3c810c3c0e14a003bea9dad82ab27475427e5221f9d625a50c635a3",
    purpose: "§3.2 row 4 — 'the two seats' becomes 'the red team's world'",
    rewrite: (s) => replaceOnce(s, AUTH_PENTEST_ASIDE_FROM, AUTH_PENTEST_ASIDE_TO, "soc-auth-pentest.why"),
  },
];

const byId = new Map(BLUE_ONLY_OVERRIDES.map((o) => [o.id, o]));

/** Apply the override registered for `id`, aborting if its pinned source has drifted. */
export function applyOverride(id: string, src: string): string {
  const o = byId.get(id);
  if (!o) throw new Error(`unknown blue-only override: ${id}`);
  const actual = sha256Hex(src);
  if (o.sha256 !== actual) {
    throw new Error(
      `stale override: ${id}\n` +
        `  expected sha256 ${o.sha256}\n` +
        `  actual   sha256 ${actual}\n` +
        `  purpose: ${o.purpose}\n` +
        `  Re-read the web copy, re-transcribe the override, then re-pin.`
    );
  }
  return o.rewrite(src);
}

/** Which case ids carry an override (the rest are exported untouched). */
export function overriddenCaseIds(): string[] {
  return BLUE_ONLY_OVERRIDES.map((o) => o.id.replace(/\.why$/, ""));
}

