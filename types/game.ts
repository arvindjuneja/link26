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

// A discoverable fact about a person — the raw material of OSINT evidence cards.
// `passive` facts come from public/cached sources (near-zero FOOTPRINT); active
// facts require probing a watched entity and cost FOOTPRINT exposure.
export interface PersonFact {
  kind:
    | "handle"
    | "email"
    | "domain"
    | "breach"
    | "device"
    | "timezone"
    | "employer"
    | "location";
  label: string;
  value: string; // fictional datum
  passive: boolean;
}

export interface Person {
  id: string;
  label: string; // online handle
  geo: GeoPoint;
  org?: string; // employing org / host label
  timezone: string;
  watched: boolean; // active recon against a watched entity spikes FOOTPRINT
  facts: PersonFact[];
}

// An RF emitter co-located with a target site. ELINT thinking, fully abstract:
// you characterize a signature, you never decode content.
export interface RfEmitter {
  id: string;
  label: string;
  geo: GeoPoint;
  band: string; // e.g. "2.4 GHz"
  signature: string; // descriptive parameters (PRF/modulation/duty), never a recipe
  siteHostId?: string;
}

export interface World {
  hosts: Record<string, Host>;
  proxies: Record<string, ProxyNode>;
  people: Record<string, Person>;
  emitters: Record<string, RfEmitter>;
}

export interface TraceInfo {
  level: number; // 0..100
  status: TraceStatus;
  lastEvent?: string;
}

// The Exposure Board: UPLINK's single trace tracker, instantiated per detection
// vector. The skill is triaging multiple rising bars, not zeroing one.
//   NETWORK     — "are they tracing the packet back?"  (scan/connect/log ops)
//   RF          — "is someone in that building noticing me?" (deployed sensors)
//   FOOTPRINT   — "did I tip them off just by looking?" (active OSINT)
//   ATTRIBUTION — the slow one: "they're profiling ME" (kit/TTP reuse; persists)
export type ExposureChannel = "NETWORK" | "RF" | "FOOTPRINT" | "ATTRIBUTION";
export type ExposureState = Record<ExposureChannel, TraceInfo>;

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

export type MissionObjectiveType =
  | "exfil"
  | "modify"
  | "plant"
  | "identify" // assemble evidence cards about a person
  | "characterize"; // collect an RF emitter signature

export interface MissionObjective {
  type: MissionObjectiveType;
  hostId?: string;
  targetPath?: string;
  marker?: string;
  // identify: assemble cards of these fact kinds about this person
  targetPersonId?: string;
  requiredKinds?: string[];
  // characterize: collect a signature card for this emitter
  emitterId?: string;
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

// A piece of intel collected from recon. The OSINT "identify" missions are
// completed by ASSEMBLING the right set of cards (a deterministic predicate),
// never by typing free text — that is what keeps grading crisp and fair.
export interface EvidenceCard {
  id: string;
  sourceKind: "person" | "emitter";
  sourceId: string;
  factKind: string; // a PersonFact kind, or "signature" for an emitter
  label: string;
  value: string;
}

export interface SessionState {
  currentTarget?: string;
  connectedHost?: string;
  workingDir?: string;
  scannedHosts?: Set<string>;
  acquired?: string[]; // host ids the player has acquired access credentials for
}

export interface GameState {
  time: number;
  seed: number; // world seed — same seed reproduces the same skeleton
  cash: number;
  reputation: number;
  exposure: ExposureState;
  route: RouteState;
  playerTools: Record<ToolId, ToolInstance>;
  inbox: MissionSummary[];
  activeMissions: Mission[];
  world: World;
  session: SessionState;
  inventory: InventoryItem[];
  evidence: EvidenceCard[]; // collected OSINT/RF intel (assembled for identify missions)
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
