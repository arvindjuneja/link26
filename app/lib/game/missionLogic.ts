// Pure mission-state logic, extracted out of the monolithic store so it can be
// unit-tested and reused by the reducer. No side effects, no I/O.

import type { GameState, Mission, MissionStatus, MissionSummary } from "@/types/game";

/** A display label for the objective's target (host, person, or emitter). */
export function objectiveTarget(mission: Mission): string {
  const o = mission.objective;
  return o.hostId ?? o.targetPersonId ?? o.emitterId ?? "—";
}

export function missionSummaryFromMission(mission: Mission): MissionSummary {
  return {
    id: mission.id,
    title: mission.title,
    description: mission.description,
    reward: mission.reward,
    targetHost: objectiveTarget(mission),
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

/** Whether a mission's objective is currently satisfied by world/inventory/evidence. */
export function evaluateMission(state: GameState, mission: Mission): boolean {
  const { objective } = mission;

  switch (objective.type) {
    case "exfil":
      if (!objective.hostId || !objective.targetPath) return false;
      return state.inventory.some(
        (item) => item.source === objective.hostId && item.path === objective.targetPath
      );
    case "modify": {
      if (!objective.hostId || !objective.targetPath) return false;
      const file = state.world.hosts[objective.hostId]?.filesystem.find(
        (entry) => entry.path === objective.targetPath
      );
      return (
        !!file?.content?.includes("tampered") || !!file?.content?.includes("state patched")
      );
    }
    case "plant":
      if (!objective.hostId || !objective.targetPath) return false;
      return !!state.world.hosts[objective.hostId]?.filesystem.some(
        (entry) => entry.path === objective.targetPath && entry.content?.includes("tracer")
      );
    case "identify": {
      // Assembled, not typed: do we hold a card of each required kind for the subject?
      if (!objective.targetPersonId || !objective.requiredKinds?.length) return false;
      const got = new Set(
        state.evidence
          .filter((e) => e.sourceId === objective.targetPersonId)
          .map((e) => e.factKind)
      );
      return objective.requiredKinds.every((k) => got.has(k));
    }
    case "characterize":
      if (!objective.emitterId) return false;
      return state.evidence.some(
        (e) => e.sourceId === objective.emitterId && e.factKind === "signature"
      );
    default:
      return false;
  }
}
