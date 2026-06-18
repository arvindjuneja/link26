import { describe, expect, it } from "vitest";
import { generateWorld } from "@/app/lib/game/worldgen";

describe("generateWorld — seeded + entity graph", () => {
  it("is deterministic for the same (now, seed)", () => {
    const a = generateWorld(0, 7);
    const b = generateWorld(0, 7);
    expect(b).toEqual(a);
  });

  it("varies with the seed", () => {
    const a = generateWorld(0, 1);
    const b = generateWorld(0, 2);
    // people handles are seed-derived, so at least one should differ
    const handlesA = Object.values(a.people).map((p) => p.label).join(",");
    const handlesB = Object.values(b.people).map((p) => p.label).join(",");
    expect(handlesA).not.toEqual(handlesB);
  });

  it("spawns one person and one emitter per host site", () => {
    const w = generateWorld(0, 3);
    const hostCount = Object.keys(w.hosts).length;
    expect(Object.keys(w.people).length).toBe(hostCount);
    expect(Object.keys(w.emitters).length).toBe(hostCount);
  });

  it("people carry both passive and active facts (the OSINT footprint tradeoff)", () => {
    const w = generateWorld(0, 3);
    for (const person of Object.values(w.people)) {
      expect(person.facts.some((f) => f.passive)).toBe(true);
      expect(person.facts.some((f) => !f.passive)).toBe(true);
    }
  });

  it("emitters describe a signature without decoding content", () => {
    const w = generateWorld(0, 3);
    const e = Object.values(w.emitters)[0];
    expect(e.band).toBeTruthy();
    expect(e.signature).toBeTruthy();
    expect(e.siteHostId).toBeTruthy();
  });
});
