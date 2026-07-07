import { describe, expect, it } from "vitest";
import { CAMPAIGN, buildCampaignMissions } from "@/app/lib/game/campaign";
import { generateWorld } from "@/app/lib/game/worldgen";

// Guards every campaign chapter against referencing an entity or path that the
// generated world can't satisfy — the way a broken/unwinnable chapter ships.
describe("CAMPAIGN — chapters reference reachable world entities", () => {
  const world = generateWorld(0, 26);

  it("covers all three acts in order", () => {
    const acts = [...new Set(CAMPAIGN.map((c) => c.act))];
    expect(acts).toEqual(["I", "II", "III"]);
    // chapters never go backwards through the acts
    const order = { I: 0, II: 1, III: 2 } as const;
    for (let i = 1; i < CAMPAIGN.length; i++) {
      expect(order[CAMPAIGN[i].act as keyof typeof order]).toBeGreaterThanOrEqual(
        order[CAMPAIGN[i - 1].act as keyof typeof order]
      );
    }
  });

  it("every objective points at a real host / person / emitter and a reachable path", () => {
    for (const c of CAMPAIGN) {
      const o = c.objective;
      if (o.hostId) expect(world.hosts[o.hostId], `host ${o.hostId} (${c.id})`).toBeDefined();

      switch (o.type) {
        case "exfil":
        case "modify": {
          const host = world.hosts[o.hostId!];
          const file = host.filesystem.find((f) => f.path === o.targetPath);
          expect(file, `${o.targetPath} on ${o.hostId} (${c.id})`).toBeDefined();
          break;
        }
        case "identify": {
          expect(world.people[o.targetPersonId!], `person ${o.targetPersonId} (${c.id})`).toBeDefined();
          expect(o.requiredKinds?.length, `requiredKinds (${c.id})`).toBeGreaterThan(0);
          break;
        }
        case "characterize": {
          expect(world.emitters[o.emitterId!], `emitter ${o.emitterId} (${c.id})`).toBeDefined();
          break;
        }
        default:
          throw new Error(`unhandled objective type in ${c.id}: ${o.type}`);
      }
    }
  });

  it("buildCampaignMissions unlocks exactly one chapter and gates the rest", () => {
    const missions = buildCampaignMissions(0, 3);
    expect(missions).toHaveLength(CAMPAIGN.length);
    expect(missions.filter((m) => m.status === "completed")).toHaveLength(3);
    expect(missions.filter((m) => m.status === "available")).toHaveLength(1);
    expect(missions[3].status).toBe("available");
    expect(missions[4].status).toBe("locked");
  });
});
