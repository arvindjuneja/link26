export type TraceStatus = "CALM" | "ALERT" | "HUNT" | "LOCKDOWN";

type GeoPoint = { lat: number; lon: number; region: string };

type AccessRules = {
  requiresCreds?: boolean;
  multiFactor?: boolean;
};

export interface Service {
  port: number;
  proto: "tcp" | "udp";
  name: "ssh" | "http" | "db" | "mail" | string;
  banner?: string;
  versionHint?: string;
  exposure: number;
  vulnTags?: string[];
  accessRules: AccessRules;
}

export interface LogEntry {
  timestamp: number;
  level: "info" | "warning" | "alert";
  message: string;
}

export interface FileSystemEntry {
  path: string;
  name: string;
  type: "file" | "dir";
  content?: string;
}

export interface Host {
  id: string;
  label: string;
  geo: GeoPoint;
  monitoring: number; // 0..1
  services: Service[];
  filesystem: FileSystemEntry[];
  logs: LogEntry[];
  flags: { honeypot?: boolean; rateLimited?: boolean };
}

export interface ProxyNode {
  id: string;
  label: string;
  geo: GeoPoint;
  stability: number; // 0..1
  anonymity: number; // 0..1
  heat: number; // 0..1
  costPerUse: number;
}

export interface World {
  hosts: Record<string, Host>;
  proxies: Record<string, ProxyNode>;
}

export interface TraceInfo {
  level: number; // 0..100
  status: TraceStatus;
  lastEvent?: string;
}

export interface RouteState {
  hops: string[];
  latencyMs: number;
  anonymity: number; // 0..1
}

export type ToolId = "scanner" | "proxyChain" | "wiper" | "tracker";

export interface ToolInstance {
  id: ToolId;
  level: number;
  label: string;
  description: string;
}

export interface MissionReward {
  cash: number;
  reputation: number;
}

export type MissionStatus = "available" | "accepted" | "completed" | "failed";

export interface MissionObjective {
  type: "exfil" | "modify" | "plant";
  hostId: string;
  targetPath: string;
  marker?: string;
}

export interface MissionSummary {
  id: string;
  title: string;
  description: string;
  reward: MissionReward;
  targetHost: string;
  deadline: number;
  status: MissionStatus;
}

export interface Mission extends MissionSummary {
  objective: MissionObjective;
  completed: boolean;
  evidenceTag?: string;
}

export interface InventoryItem {
  id: string;
  label: string;
  source: string;
  path?: string;
  content?: string;
}

export interface SessionState {
  currentTarget?: string;
  connectedHost?: string;
  workingDir?: string;
  scannedHosts?: Set<string>;
}

export interface GameState {
  time: number;
  cash: number;
  reputation: number;
  trace: TraceInfo;
  route: RouteState;
  playerTools: Record<ToolId, ToolInstance>;
  inbox: MissionSummary[];
  activeMissions: Mission[];
  world: World;
  session: SessionState;
  inventory: InventoryItem[];
}

export interface TerminalLine {
  id: string;
  text: string;
  type: "info" | "command" | "error" | "success" | "warning";
}

export type VfxEventType = "scan" | "alert" | "success" | "idle" | "connect";

export interface VfxEvent {
  type: VfxEventType;
  value?: string;
  target?: string;  // Target host ID for visual effects
}
