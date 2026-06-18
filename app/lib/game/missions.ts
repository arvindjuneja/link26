import { Mission, MissionObjective, MissionReward, MissionSummary, World } from "@/types/game";
import { missionSummaryFromMission } from "@/app/lib/game/missionLogic";

const missionBlueprints: Array<{
  id: string;
  title: string;
  description: string;
  objective: MissionObjective;
  reward: MissionReward;
  scopeNote?: string;
}> = [
  {
    id: "mission-ghost",
    title: "Ghost in the Archive",
    description:
      "Pull the asset register off the mail relay. Read-only exfil — copy it to @local and leave no write artifacts behind.",
    objective: {
      type: "exfil",
      hostId: "hq-node",
      targetPath: "/secrets.txt",
    },
    reward: { cash: 2200, reputation: 20 },
    scopeNote: "In scope: hq-node read paths only, this window. Read-only — any write trips the deal.",
  },
  {
    id: "mission-orbital",
    title: "Orbital Whisper",
    description:
      "Falsify the freight telemetry manifest so the shipment window reads delayed. Tamper it in place with `edit`.",
    objective: {
      type: "modify",
      hostId: "orbital",
      targetPath: "/logs/manifest.log",
    },
    reward: { cash: 1800, reputation: 15 },
    scopeNote: "In scope: orbital /logs only. One entry — no broad rewrites, no second pass.",
  },
  {
    id: "mission-iris",
    title: "Iris Signal",
    description:
      "Doctor the quarterly ledger snapshot to bury one shipment entry. Modify it in place with `edit`.",
    objective: {
      type: "modify",
      hostId: "iris",
      targetPath: "/data/vault.txt",
    },
    reward: { cash: 1600, reputation: 18 },
    scopeNote: "In scope: iris /data only, single in-place edit. Leave other checksums untouched.",
  },
  {
    id: "mission-faceless",
    title: "Faceless",
    description:
      "Attribute the operator behind the Aurora lab handle. Assemble a handle, a work email and a breach record on them (`osint <handle> --active`).",
    objective: {
      type: "identify",
      hostId: "aurora",
      targetPersonId: "person-aurora",
      requiredKinds: ["handle", "email", "breach"],
    },
    reward: { cash: 2000, reputation: 22 },
    scopeNote: "In scope: person-aurora OSINT only (passive + active). No touching live lab assets.",
  },
  {
    id: "mission-carrier",
    title: "Silent Carrier",
    description:
      "Characterize the unlabeled emitter at the Solstice substation — band and signature only (`collect rf solstice`).",
    objective: {
      type: "characterize",
      hostId: "solstice",
      emitterId: "emitter-solstice",
    },
    reward: { cash: 1500, reputation: 16 },
    scopeNote: "In scope: emitter-solstice RF characterization only. No host contact.",
  },
];

export function generateMissions(
  world: World,
  now: number = Date.now()
): { inbox: MissionSummary[]; missions: Mission[] } {
  const missions: Mission[] = missionBlueprints.map((blueprint, index) => {
    const host = blueprint.objective.hostId
      ? world.hosts[blueprint.objective.hostId]
      : undefined;
    const desc = host ? `${blueprint.description} Target: ${host.label}` : blueprint.description;
    return {
      ...blueprint,
      description: desc,
      deadline: now + (index + 1) * 1000 * 60 * 60,
      status: "available",
      objective: blueprint.objective,
      completed: false,
    } as Mission;
  });

  const inbox: MissionSummary[] = missions.map(missionSummaryFromMission);

  return { inbox, missions };
}
