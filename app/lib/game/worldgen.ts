import {
  Host,
  ProxyNode,
  Service,
  FileSystemEntry,
  World,
  Person,
  PersonFact,
  RfEmitter,
} from "@/types/game";
import { mulberry32, hashSeed, type Rng } from "@/app/lib/util/rng";

// Realistic geographic coordinates for regions - spread out across the world
const regionCoords: Record<string, { lat: number; lon: number }> = {
  "North America": { lat: 45, lon: -95 },      // Central US
  "Europe": { lat: 52, lon: 5 },               // Netherlands/Germany
  "Asia": { lat: 35, lon: 140 },               // Japan
  "Africa": { lat: -5, lon: 25 },              // Central Africa
  "Oceania": { lat: -35, lon: 150 },           // Eastern Australia
  "South America": { lat: -20, lon: -50 },     // Central Brazil
  "Middle East": { lat: 30, lon: 50 },         // Persian Gulf
  "Scandinavia": { lat: 60, lon: 20 },         // Stockholm area
  "Central Europe": { lat: 48, lon: 16 },      // Vienna area
  "Pacific": { lat: 20, lon: -160 },            // Hawaii area
};

// Targets are named like real engagement scope: an org plus the role the box
// actually plays on the network. A practitioner should recognize each as a
// plausible asset (mail relay, jump host, object store, substation gateway...).
const hostTemplates = [
  {
    id: "hq-node",
    label: "Meridian Logistics — mail relay",
    region: "North America",
  },
  {
    id: "orbital",
    label: "Orbital Freight — telemetry API",
    region: "Europe",
  },
  {
    id: "aurora",
    label: "Aurora Diagnostics — lab LIMS",
    region: "Asia",
  },
  {
    id: "charon",
    label: "Charon Industrial — SCADA historian",
    region: "Africa",
  },
  {
    id: "iris",
    label: "Iris Backups — object store",
    region: "Oceania",
  },
  {
    id: "helix",
    label: "Helix Genomics — sequencing cluster",
    region: "South America",
  },
  {
    id: "polaris",
    label: "Polaris Capital — settlement mesh",
    region: "Middle East",
  },
  {
    id: "solstice",
    label: "Solstice Grid Ops — substation gateway",
    region: "Scandinavia",
  },
  {
    id: "mosaic",
    label: "Mosaic Media — CDN origin",
    region: "Central Europe",
  },
  {
    id: "axion",
    label: "Axion Research — HPC login node",
    region: "Pacific",
  },
];

const proxyTemplates = Array.from({ length: 15 }).map((_, index) => ({
  id: `proxy-${index + 1}`,
  label: [`Atlas`, `Nebula`, `Ghost`, `Circuit`, `Phantom`, `Fuse`, `Pulse`, `Boreal`, `Tidal`, `Beacon`, `Harbor`, `Echo`, `Lumen`, `Shard`, `Nova`][index % 15],
}));

const serviceRoster: Service[][] = [
  [
    { port: 22, proto: "tcp", name: "ssh", banner: "OpenSSH 8.5", exposure: 0.4, accessRules: { requiresCreds: true } },
    { port: 80, proto: "tcp", name: "http", banner: "nginx/1.24", exposure: 0.5, accessRules: {} },
    { port: 443, proto: "tcp", name: "https", banner: "nginx/1.24 TLS", exposure: 0.3, accessRules: { multiFactor: true } },
  ],
  [
    { port: 3306, proto: "tcp", name: "db", banner: "MariaDB 10.7", exposure: 0.6, accessRules: { requiresCreds: true } },
    { port: 25, proto: "tcp", name: "mail", banner: "Postfix 3.6", exposure: 0.2, accessRules: {} },
    { port: 8080, proto: "tcp", name: "http", banner: "Kestrel", exposure: 0.3, accessRules: { multiFactor: true } },
  ],
  [
    { port: 22, proto: "tcp", name: "ssh", banner: "OpenSSH 9.0", exposure: 0.4, accessRules: { requiresCreds: true } },
    { port: 443, proto: "tcp", name: "https", banner: "Caddy 2", exposure: 0.3, accessRules: {} },
    { port: 9090, proto: "tcp", name: "http", banner: "FastAPI", exposure: 0.35, accessRules: {} },
  ],
];

// Credible-but-abstract artifacts — the kind of internal file an operator would
// actually pull. No real secrets, creds, or anything that transfers to reality.
const rootFiles: FileSystemEntry[] = [
  {
    path: "/secrets.txt",
    name: "asset_register.txt",
    type: "file" as const,
    content:
      "INTERNAL // restricted\nendpoints: 412  privileged_accounts: 9\noffsite_backup: iris-objstore\nowner: secops@meridian.example",
  },
  {
    path: "/payload.bin",
    name: "vault_export.enc",
    type: "file" as const,
    content: "[encrypted container — 4.2 MB, AES-256-GCM]",
  },
  { path: "/logs", name: "logs", type: "dir" as const },
  {
    path: "/logs/manifest.log",
    name: "manifest.log",
    type: "file" as const,
    content: "window=nominal state=scheduled seq=0x1f checksum=ok",
  },
  {
    path: "/data/vault.txt",
    name: "ledger_snapshot.txt",
    type: "file" as const,
    content: "ledger snapshot 2026-Q1 — 1,284 entries — reconciled",
  },
];

const makeLogs = (label: string, now: number) =>
  Array.from({ length: 3 }).map((_, index) => ({
    timestamp: now - index * 1000 * 60,
    level: index === 2 ? "warning" : "info",
    message: `${label} audit record ${index}`,
  }));

// Specific geographic locations for each host - no randomness, real places
const hostLocations: Record<string, { lat: number; lon: number }> = {
  "hq-node": { lat: 40.7, lon: -74.0 },           // New York, USA
  "orbital": { lat: 51.5, lon: -0.1 },            // London, UK
  "aurora": { lat: 35.7, lon: 139.7 },            // Tokyo, Japan
  "charon": { lat: -26.2, lon: 28.0 },            // Johannesburg, South Africa
  "iris": { lat: -33.9, lon: 151.2 },             // Sydney, Australia
  "helix": { lat: -23.5, lon: -46.6 },            // São Paulo, Brazil
  "polaris": { lat: 25.2, lon: 55.3 },            // Dubai, UAE
  "solstice": { lat: 59.3, lon: 18.1 },           // Stockholm, Sweden
  "mosaic": { lat: 48.2, lon: 16.4 },             // Vienna, Austria
  "axion": { lat: 21.3, lon: -157.8 },            // Honolulu, Hawaii
};

// --- procedural-skin pools (selected by the seeded RNG) ---
const handlePool = [
  "nullbyte", "r3dwire", "ghoststack", "packetwitch", "coldboot", "drift0",
  "m4yhem", "sl0wloris", "binwalker", "tracepop", "kr4ken", "blu3jay",
  "ferrous", "quietfox", "ampersand", "lasthop", "deaddrop", "vlan0",
];
const tzByRegion: Record<string, string> = {
  "North America": "UTC-5", "Europe": "UTC+0", "Asia": "UTC+9", "Africa": "UTC+2",
  "Oceania": "UTC+11", "South America": "UTC-3", "Middle East": "UTC+4",
  "Scandinavia": "UTC+1", "Central Europe": "UTC+1", "Pacific": "UTC-10",
};
const rfBands = ["2.4 GHz", "900 MHz", "5.8 GHz", "433 MHz", "1.2 GHz"];
const rfModulation = ["FHSS", "DSSS", "OFDM", "FSK", "GFSK"];
const rfDuty = ["bursty", "continuous", "low duty", "periodic beacon"];

const pick = <T>(arr: T[], rng: Rng): T => arr[Math.floor(rng() * arr.length)];
const hex = (rng: Rng, n: number) =>
  Array.from({ length: n }, () => Math.floor(rng() * 16).toString(16)).join("");

const orgSlug = (label: string) =>
  label.split("—")[0].trim().toLowerCase().replace(/[^a-z]+/g, "");

function makePerson(host: Host, index: number, rng: Rng): Person {
  const handle = `${pick(handlePool, rng)}${Math.floor(rng() * 90 + 10)}`;
  const slug = orgSlug(host.label);
  const tz = tzByRegion[host.geo.region] ?? "UTC+0";
  const facts: PersonFact[] = [
    { kind: "handle", label: "online handle", value: handle, passive: true },
    { kind: "email", label: "work email", value: `${handle}@${slug}.example`, passive: true },
    { kind: "employer", label: "employer", value: host.label, passive: true },
    { kind: "timezone", label: "active hours", value: tz, passive: true },
    { kind: "breach", label: "breach record", value: `appears in the 2023 forum dump`, passive: false },
    { kind: "device", label: "device MAC", value: `${hex(rng, 2)}:${hex(rng, 2)}:${hex(rng, 2)}:${hex(rng, 2)}`, passive: false },
    { kind: "location", label: "frequent location", value: `${host.geo.region} metro`, passive: false },
  ];
  return {
    id: `person-${host.id}`,
    label: handle,
    geo: { ...host.geo },
    org: host.label,
    timezone: tz,
    watched: index % 3 === 0, // a third are actively monitored
    facts,
  };
}

function makeEmitter(host: Host, rng: Rng): RfEmitter {
  return {
    id: `emitter-${host.id}`,
    label: `${orgSlug(host.label)}-site-rf`,
    geo: { ...host.geo },
    band: pick(rfBands, rng),
    signature: `${pick(rfModulation, rng)}, ${pick(rfDuty, rng)}`,
    siteHostId: host.id,
  };
}

export function generateWorld(now: number = Date.now(), seed?: number): World {
  const rng = mulberry32(seed ?? hashSeed(String(now)));
  const hosts: Record<string, Host> = {};
  hostTemplates.forEach((template, index) => {
    const services = serviceRoster[index % serviceRoster.length];
    // Use specific location for each host
    const location = hostLocations[template.id] || regionCoords[template.region] || { lat: 0, lon: 0 };
    hosts[template.id] = {
      id: template.id,
      label: template.label,
      geo: {
        lat: location.lat,
        lon: location.lon,
        region: template.region
      },
      // seeded jitter so monitoring posture varies run to run
      monitoring: Math.min(0.95, 0.15 + (index % 3) * 0.2 + rng() * 0.12),
      services,
      filesystem: rootFiles.map((entry) => ({ ...entry })) as FileSystemEntry[],
      logs: makeLogs(template.label, now),
      flags: { honeypot: index === 3, rateLimited: index % 4 === 0 },
    } as Host;
  });

  // People (footprint targets) and RF emitters (collection targets), one per site.
  const people: Record<string, Person> = {};
  const emitters: Record<string, RfEmitter> = {};
  hostTemplates.forEach((template, index) => {
    const host = hosts[template.id];
    const person = makePerson(host, index, rng);
    people[person.id] = person;
    const emitter = makeEmitter(host, rng);
    emitters[emitter.id] = emitter;
  });

  const proxies: Record<string, ProxyNode> = {};
  // Distribute proxies globally - DIFFERENT locations from hosts, spread evenly
  const proxyLocations = [
    { lat: 45.5, lon: -73.6, name: "Montreal" },
    { lat: 34.1, lon: -118.2, name: "Los Angeles" },
    { lat: 41.9, lon: -87.6, name: "Chicago" },
    { lat: 50.1, lon: 8.7, name: "Frankfurt" },
    { lat: 52.4, lon: 4.9, name: "Amsterdam" },
    { lat: 55.8, lon: 37.6, name: "Moscow" },
    { lat: 39.9, lon: 116.4, name: "Beijing" },
    { lat: 31.2, lon: 121.5, name: "Shanghai" },
    { lat: 37.6, lon: 127.0, name: "Seoul" },
    { lat: 1.3, lon: 103.8, name: "Singapore" },
    { lat: 22.3, lon: 114.2, name: "Hong Kong" },
    { lat: 28.6, lon: 77.2, name: "Delhi" },
    { lat: 19.1, lon: 72.9, name: "Mumbai" },
    { lat: -34.6, lon: -58.4, name: "Buenos Aires" },
    { lat: 30.0, lon: 31.2, name: "Cairo" },
  ];
  
  // Assign each proxy to a unique location
  proxyTemplates.forEach((proxy, index) => {
    const location = proxyLocations[index % proxyLocations.length];
    proxies[proxy.id] = {
      id: proxy.id,
      label: `${proxy.label}-${index + 1}`,
      geo: { 
        lat: location.lat, 
        lon: location.lon, 
        region: "global" 
      },
      stability: 0.5 + (index % 5) * 0.1,
      anonymity: 0.3 + ((index + 2) % 4) * 0.15,
      heat: 0,
      costPerUse: 8 + (index % 5) * 5,
    };
  });

  return {
    hosts,
    proxies,
    people,
    emitters,
  };
}
