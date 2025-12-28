import { Mission, MissionObjective, MissionReward, MissionSummary, World } from "@/types/game";

const missionBlueprints: Array<{
  id: string;
  title: string;
  description: string;
  objective: MissionObjective;
  reward: MissionReward;
}> = [
  {
    id: "mission-ghost",
    title: "Ghost in the Archive",
    description: "Exfil the prototype diagnostics without triggering the IDS.",
    objective: {
      type: "exfil",
      hostId: "hq-node",
      targetPath: "/secrets.txt",
    },
    reward: { cash: 2200, reputation: 20 },
  },
  {
    id: "mission-orbital",
    title: "Orbital Whisper",
    description: "Modify the telemetry log so the orbital launch appears delayed.",
    objective: {
      type: "modify",
      hostId: "orbital",
      targetPath: "/logs/manifest.log",
    },
    reward: { cash: 1800, reputation: 15 },
  },
  {
    id: "mission-iris",
    title: "Iris Signal",
    description: "Plant a tracer file inside Iris' vault to track the next shipment.",
    objective: {
      type: "plant",
      hostId: "iris",
      targetPath: "/data/vault.txt",
    },
    reward: { cash: 1600, reputation: 18 },
  },
];

export function generateMissions(world: World): { inbox: MissionSummary[]; missions: Mission[] } {
  const now = Date.now();
  const missions: Mission[] = missionBlueprints.map((blueprint, index) => {
    const host = world.hosts[blueprint.objective.hostId];
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

  const inbox: MissionSummary[] = missions.map((mission) => ({
    id: mission.id,
    title: mission.title,
    description: mission.description,
    reward: mission.reward,
    targetHost: mission.objective.hostId,
    deadline: mission.deadline,
    status: mission.status,
  }));

  return { inbox, missions };
}
