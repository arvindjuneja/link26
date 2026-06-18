// Pure mission-state logic, extracted out of the monolithic store so it can be
// unit-tested and reused by the reducer. No side effects, no I/O.

import type { GameState, Mission, MissionStatus, MissionSummary } from "@/types/game";

export function missionSummaryFromMission(mission: Mission): MissionSummary {
  return {
    id: mission.id,
    title: mission.title,
    description: mission.description,
    reward: mission.reward,
    targetHost: mission.objective.hostId,
    deadline: mission.deadline,
    status: mission.status,
  };
}

export function syncInbox(missions: Mission[]): MissionSummary[] {
  return missions.map(missionSummaryFromMission);
}

/** Return a new state with the given mission's status changed (inbox kept in sync). */
export function setMissionStatus(
  state: GameState,
  missionId: string,
  status: MissionStatus
): GameState {
  const activeMissions = state.activeMissions.map((mission) =>
    mission.id === missionId ? { ...mission, status } : mission
  );
  return { ...state, activeMissions, inbox: syncInbox(activeMissions) };
}

/** Whether a mission's objective is currently satisfied by world/inventory state. */
export function evaluateMission(state: GameState, mission: Mission): boolean {
  const { objective } = mission;
  const host = state.world.hosts[objective.hostId];
  if (!host) return false;

  switch (objective.type) {
    case "exfil":
      return state.inventory.some(
        (item) => item.source === objective.hostId && item.path === objective.targetPath
      );
    case "modify": {
      const fileEntry = host.filesystem.find((entry) => entry.path === objective.targetPath);
      return (
        !!fileEntry?.content?.includes("tampered") ||
        !!fileEntry?.content?.includes("state patched")
      );
    }
    case "plant":
      return host.filesystem.some(
        (entry) => entry.path === objective.targetPath && entry.content?.includes("tracer")
      );
    default:
      return false;
  }
}
