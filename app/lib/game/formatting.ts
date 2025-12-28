import { Host, MissionSummary, ProxyNode } from "@/types/game";

const stateMapping = (exposure: number) => {
  if (exposure > 0.6) return "open";
  if (exposure > 0.35) return "filtered";
  return "closed";
};

export function formatScanOutput(host: Host): string[] {
  const header = "PORT     STATE     SERVICE   INFO";
  const body = host.services.map((service) => {
    const state = stateMapping(service.exposure);
    const info = service.banner || service.versionHint || "";
    return `${service.port.toString().padEnd(8)}${state.padEnd(10)}${service.name.padEnd(10)}${info}`;
  });
  return [header, ...body];
}

export function formatProxyTable(proxies: ProxyNode[]): string[] {
  const header = "ID         LABEL        ANON   HEAT   COST";
  const body = proxies.map((proxy) =>
    `${proxy.id.padEnd(10)}${proxy.label.padEnd(12)}${proxy.anonymity.toFixed(2).padEnd(7)}${proxy.heat.toFixed(1).padEnd(7)}${proxy.costPerUse.toFixed(0)}`
  );
  return [header, ...body];
}

export function missionSummaryLine(mission: MissionSummary): string {
  return `${mission.id} | ${mission.title} | ${mission.reward.cash}c / ${mission.reward.reputation}r | ${mission.status}`;
}

export function formatMissionDetail(mission: MissionSummary): string[] {
  return [mission.title, mission.description, `Reward: ${mission.reward.cash} credits, ${mission.reward.reputation} rep`, `Deadline: ${new Date(mission.deadline).toLocaleString()}`];
}
