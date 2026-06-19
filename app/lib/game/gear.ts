// The gear / rank acquisition track — UPLINK's power fantasy.
//
// Completing jobs buys gear, and each tier visibly FLATTENS one exposure
// channel's noise coefficient: the player feels a specific fear get quieter
// ("owning the rig"). This is the week-1 carrot that balances the dread.

import type { ExposureChannel } from "@/types/game";

export interface GearItem {
  id: string;
  label: string;
  channel: ExposureChannel;
  step: number; // noise reduction added per tier
  maxTier: number;
  baseCost: number;
  description: string;
}

export const GEAR: GearItem[] = [
  {
    id: "rig",
    label: "Cold-Rig CPU",
    channel: "NETWORK",
    step: 0.12,
    maxTier: 4,
    baseCost: 1500,
    description: "Quieter packet timing — flattens NETWORK noise.",
  },
  {
    id: "damper",
    label: "RF Damper",
    channel: "RF",
    step: 0.15,
    maxTier: 3,
    baseCost: 1200,
    description: "Lower transmit power on tasked sensors — flattens RF.",
  },
  {
    id: "scrubber",
    label: "Footprint Scrubber",
    channel: "FOOTPRINT",
    step: 0.15,
    maxTier: 3,
    baseCost: 1400,
    description: "Source rotation + cached pulls — flattens FOOTPRINT.",
  },
  {
    id: "launder",
    label: "Identity Launderer",
    channel: "ATTRIBUTION",
    step: 0.1,
    maxTier: 3,
    baseCost: 2200,
    description: "Breaks infra/TTP overlap — flattens ATTRIBUTION.",
  },
];

const MITIGATION_CAP = 0.6;

export function gearById(id: string): GearItem | undefined {
  return GEAR.find((g) => g.id === id);
}

/** Total noise reduction (0..cap) a player's gear gives a channel. */
export function channelMitigation(
  gear: Record<string, number>,
  channel: ExposureChannel
): number {
  let m = 0;
  for (const g of GEAR) {
    if (g.channel === channel) m += (gear[g.id] ?? 0) * g.step;
  }
  return Math.min(MITIGATION_CAP, m);
}

/** Cost to buy the next tier of an item, rising steeply. */
export function nextCost(item: GearItem, currentTier: number): number {
  return Math.round(item.baseCost * Math.pow(1.8, currentTier));
}
