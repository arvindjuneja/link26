// The §4.2 constraint suite over the whole precomputed horizon (C1 acceptance #4).
//
// The board is a pure function of the date (D6), so these are the only assertions that
// exist about it anywhere — nothing is ported to Swift, which reads `daily.json` and
// wraps `daysSince(horizonStart) mod days.count` past the horizon.

import { describe, expect, it } from "vitest";

import { SOC_CASES_BY_ID } from "@/app/lib/soc/cases";
import type { SocCase } from "@/app/lib/soc/types";
import {
  BOARD_SIZE,
  HORIZON_DAYS,
  HORIZON_START,
  addDays,
  boardFor,
  dailyCalendar,
  dailyPool,
  fnv1a32,
  satisfies,
  xorshift32,
} from "@/app/lib/soc/exporter/daily";

const calendar = dailyCalendar();
const casesOf = (ids: string[]): SocCase[] => ids.map((id) => SOC_CASES_BY_ID[id]);

describe("daily · the horizon", () => {
  it("precomputes 730 consecutive days from the pinned start", () => {
    expect(calendar.days).toHaveLength(HORIZON_DAYS);
    expect(calendar.horizonStart).toBe(HORIZON_START);
    calendar.days.forEach((day, i) => expect(day.date).toBe(addDays(HORIZON_START, i)));
  });

  it("draws five distinct hand-authored cases every day", () => {
    for (const day of calendar.days) {
      expect(day.caseIds, day.date).toHaveLength(BOARD_SIZE);
      expect(new Set(day.caseIds).size, day.date).toBe(BOARD_SIZE);
      for (const id of day.caseIds) {
        const c = SOC_CASES_BY_ID[id];
        expect(c, `${day.date}: unknown case ${id}`).toBeDefined();
        expect(c.handoff, `${day.date}: ${id} is a campaign-only handoff case`).toBeUndefined();
      }
    }
  });

  it("ships a shift template with a {date} slot (S9)", () => {
    expect(calendar.shiftTemplate.idPrefix).toBe("daily-");
    expect(calendar.shiftTemplate.label).toContain("{date}");
    expect(calendar.shiftTemplate.kind).toBe("daily");
    expect(calendar.shiftTemplate.unlockStanding).toBe(40);
  });
});

describe("daily · the §4.2 constraints, on every one of the 730 boards", () => {
  it("(a) presents all three verdicts", () => {
    for (const day of calendar.days) {
      const verdicts = new Set(casesOf(day.caseIds).map((c) => c.truth));
      expect(verdicts.size, `${day.date}: ${[...verdicts].join(", ")}`).toBe(3);
    }
  });

  it("(b) draws at most two of any archetype", () => {
    for (const day of calendar.days) {
      const counts = new Map<string, number>();
      for (const c of casesOf(day.caseIds)) counts.set(c.archetype, (counts.get(c.archetype) ?? 0) + 1);
      for (const [archetype, n] of counts) expect(n, `${day.date}: ${archetype} × ${n}`).toBeLessThanOrEqual(2);
    }
  });

  it("(c) keeps FP + Benign-TP ≥ TP — real triage is mostly not-a-threat", () => {
    for (const day of calendar.days) {
      const cs = casesOf(day.caseIds);
      const tp = cs.filter((c) => c.truth === "true-positive").length;
      expect(cs.length - tp, `${day.date}: ${tp} true positives`).toBeGreaterThanOrEqual(tp);
    }
  });

  it("(d) never opens on a true positive — a daily starts calm", () => {
    for (const day of calendar.days) {
      expect(casesOf(day.caseIds)[0].truth, `${day.date}`).not.toBe("true-positive");
    }
  });
});

describe("daily · recency", () => {
  it("never repeats a case on two consecutive days", () => {
    for (let i = 1; i < calendar.days.length; i++) {
      const prev = new Set(calendar.days[i - 1].caseIds);
      const repeats = calendar.days[i].caseIds.filter((id) => prev.has(id));
      expect(repeats, `${calendar.days[i].date} repeats ${repeats.join(", ")}`).toEqual([]);
    }
  });

  it("still rotates the pool — no board is ever a repeat of the day before", () => {
    const boards = new Set(calendar.days.map((d) => d.caseIds.join("|")));
    expect(boards.size).toBeGreaterThan(HORIZON_DAYS / 2);
  });
});

describe("daily · determinism", () => {
  it("gives the same date the identical board, in the identical order", () => {
    const again = dailyCalendar();
    expect(again.days).toEqual(calendar.days);
  });

  it("is a pure function of the date string, not of the clock or the locale", () => {
    const pool = dailyPool();
    const a = boardFor("2027-02-14", pool, []).map((c) => c.id);
    const b = boardFor("2027-02-14", pool, []).map((c) => c.id);
    expect(a).toEqual(b);
    expect(boardFor("2027-02-15", pool, []).map((c) => c.id)).not.toEqual(a);
  });

  it("has a stable PRNG", () => {
    expect(fnv1a32("2026-09-05")).toBe(fnv1a32("2026-09-05"));
    const next = xorshift32(fnv1a32("2026-09-05"));
    const first = [next(), next(), next()];
    const again = xorshift32(fnv1a32("2026-09-05"));
    expect([again(), again(), again()]).toEqual(first);
    for (const n of first) expect(Number.isInteger(n) && n >= 0 && n <= 0xffffffff).toBe(true);
  });

  it("handles a UTC month and year roll-over", () => {
    expect(addDays("2026-12-31", 1)).toBe("2027-01-01");
    expect(addDays("2028-02-28", 1)).toBe("2028-02-29");
    expect(addDays("2026-09-05", 730)).toBe("2028-09-04");
  });
});

describe("daily · the fallback ladder and totality", () => {
  const pick = (id: string): SocCase => SOC_CASES_BY_ID[id];

  it("still returns a board when a starved pool cannot satisfy (b) or (c)", () => {
    // Three TPs of one archetype + one FP + one BTP: rules (b) and (c) are unsatisfiable,
    // so the ladder must drop them. Rule (a) is never dropped.
    const starved = [
      pick("soc-auth-bruteforce"), // TP  · auth-bruteforce
      pick("soc-lockout-attack"), // TP  · account-lockout
      pick("soc-dns-beacon"), // TP  · dns-c2
      pick("soc-auth-reset"), // FP  · auth-bruteforce
      pick("soc-auth-pentest"), // BTP · auth-bruteforce
    ];
    const board = boardFor("2026-09-05", starved, []);
    expect(board).toHaveLength(BOARD_SIZE);
    expect(new Set(board.map((c) => c.truth)).size).toBe(3);
    expect(satisfies(board, { archetypeCap: true, notTpHeavy: true, calmOpener: true })).toBe(false);
  });

  it("returns a board even when the pool holds a single verdict", () => {
    const oneVerdict = ["soc-ps-cradle", "soc-dns-beacon", "soc-auth-bruteforce", "soc-id-mfa", "soc-edr-loader"].map(
      pick
    );
    const board = boardFor("2026-09-05", oneVerdict, []);
    expect(board).toHaveLength(BOARD_SIZE);
  });

  it("narrows the recency window rather than starving, and never drops yesterday", () => {
    const pool = dailyPool();
    // Three days of history leaves 6 candidates — below the 8-candidate floor — so the
    // §4.2 ladder drops the oldest day. Yesterday's ids must still be excluded.
    const history = [
      ["soc-ps-cradle", "soc-auth-reset", "soc-ps-patch", "soc-dns-beacon", "soc-auth-bruteforce"],
      ["soc-dns-cdn", "soc-auth-pentest", "soc-phish-harvest", "soc-id-vpn", "soc-edr-test"],
      ["soc-id-mfa", "soc-exfil-backup", "soc-edr-loader", "soc-phish-sim", "soc-exfil-cloud"],
    ];
    const board = boardFor("2026-10-01", pool, history).map((c) => c.id);
    expect(board).toHaveLength(BOARD_SIZE);
    for (const id of history[0]) expect(board, `yesterday's ${id} came back`).not.toContain(id);
  });

  it("never throws for any date from 2026 through 2030", () => {
    const pool = dailyPool();
    let date = "2026-01-01";
    let n = 0;
    while (date < "2031-01-01") {
      expect(() => boardFor(date, pool, [])).not.toThrow();
      date = addDays(date, 7);
      n++;
    }
    expect(n).toBeGreaterThan(250);
  });
});
