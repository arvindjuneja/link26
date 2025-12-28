import { Host, ProxyNode, Service, FileSystemEntry, World } from "@/types/game";

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

const hostTemplates = [
  {
    id: "hq-node",
    label: "Nova Satellite HQ",
    region: "North America",
  },
  {
    id: "orbital",
    label: "Orbital Data Exchange",
    region: "Europe",
  },
  {
    id: "aurora",
    label: "Aurora Bioware Labs",
    region: "Asia",
  },
  {
    id: "charon",
    label: "Charon Defense Grid",
    region: "Africa",
  },
  {
    id: "iris",
    label: "Iris Cloud Archive",
    region: "Oceania",
  },
  {
    id: "helix",
    label: "Helix Genomics",
    region: "South America",
  },
  {
    id: "polaris",
    label: "Polaris Financial Mesh",
    region: "Middle East",
  },
  {
    id: "solstice",
    label: "Solstice Power Grid",
    region: "Scandinavia",
  },
  {
    id: "mosaic",
    label: "Mosaic Media Nest",
    region: "Central Europe",
  },
  {
    id: "axion",
    label: "Axion Research Cluster",
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

const rootFiles: FileSystemEntry[] = [
  { path: "/secrets.txt", name: "secrets.txt", type: "file" as const, content: "TOP SECRET: Prototype diagnostics" },
  { path: "/payload.bin", name: "payload.bin", type: "file" as const, content: "[binary blob]" },
  { path: "/logs", name: "logs", type: "dir" as const },
  { path: "/data/vault.txt", name: "vault.txt", type: "file" as const, content: "Ledger entries: 42" },
];

const makeLogs = (label: string) =>
  Array.from({ length: 3 }).map((_, index) => ({
    timestamp: Date.now() - index * 1000 * 60,
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

export function generateWorld(): World {
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
      monitoring: 0.15 + (index % 3) * 0.2,
      services,
      filesystem: rootFiles.map((entry) => ({ ...entry })) as FileSystemEntry[],
      logs: makeLogs(template.label),
      flags: { honeypot: index === 3, rateLimited: index % 4 === 0 },
    } as Host;
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
  };
}
