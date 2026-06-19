import { describe, expect, it } from "vitest";
import type { ExposureState, RouteState } from "@/types/game";
import {
  applyChannelNoise,
  createExposure,
  overallTrace,
  tickExposure,
  topChannel,
} from "@/app/lib/game/exposure";

const DIRECT: RouteState = { hops: [], latencyMs: 0, anonymity: 0 };

describe("exposure engine", () => {
  it("starts with NETWORK warm and the other channels cold and calm", () => {
    const e = createExposure(8);
    expect(e.NETWORK.level).toBe(8);
    expect(e.RF.level).toBe(0);
    expect(e.FOOTPRINT.level).toBe(0);
    expect(e.ATTRIBUTION.level).toBe(0);
    expect(Object.values(e).every((c) => c.status === "CALM")).toBe(true);
  });

  it("applyChannelNoise raises only the targeted channel", () => {
    const e = createExposure(8);
    const next = applyChannelNoise(e, "RF", 40, DIRECT);
    expect(next.RF.level).toBeGreaterThan(e.RF.level);
    expect(next.NETWORK.level).toBe(e.NETWORK.level);
    expect(next.FOOTPRINT.level).toBe(e.FOOTPRINT.level);
  });

  it("the dwell clock raises NETWORK while connected, cools it while idle", () => {
    const e = createExposure(20);
    const held = tickExposure(e, { connected: true, route: DIRECT });
    const idle = tickExposure(e, { connected: false, route: DIRECT });
    expect(held.NETWORK.level).toBeGreaterThan(e.NETWORK.level);
    expect(idle.NETWORK.level).toBeLessThan(e.NETWORK.level);
  });

  it("the dwell clock closes the window: holding a session reaches HUNT, idle cools it", () => {
    let e = createExposure(8);
    let ticks = 0;
    while (e.NETWORK.status !== "HUNT" && ticks < 60) {
      e = tickExposure(e, { connected: true, route: DIRECT });
      ticks++;
    }
    expect(e.NETWORK.status).toBe("HUNT"); // the window actually closes
    expect(ticks).toBeLessThan(40); // within a felt window (~<2min at 3s/tick)
    const cooled = tickExposure(e, { connected: false, route: DIRECT });
    expect(cooled.NETWORK.level).toBeLessThan(e.NETWORK.level);
  });

  it("ATTRIBUTION cools far slower than the other channels", () => {
    const hot: ExposureState = {
      ...createExposure(0),
      FOOTPRINT: { level: 40, status: "ALERT" },
      ATTRIBUTION: { level: 40, status: "ALERT" },
    };
    const next = tickExposure(hot, { connected: false, route: DIRECT });
    const footprintDrop = hot.FOOTPRINT.level - next.FOOTPRINT.level;
    const attributionDrop = hot.ATTRIBUTION.level - next.ATTRIBUTION.level;
    expect(attributionDrop).toBeLessThan(footprintDrop);
  });

  it("overallTrace and topChannel report the worst channel", () => {
    let e = createExposure(8);
    e = applyChannelNoise(e, "RF", 90, DIRECT); // push RF to a high status
    expect(topChannel(e)).toBe("RF");
    expect(overallTrace(e).status).toBe(e.RF.status);
    expect(overallTrace(e).level).toBe(e.RF.level);
  });
});
