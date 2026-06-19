// The campaign spine — Act I: "The Scared Freelancer".
//
// A short, ordered narrative arc that teaches the verbs in-world (Mercer talks
// you through the first job) and gives the sandbox a thread to pull on. Each
// chapter is a normal Mission tagged with chapterIndex; finishing one unlocks
// the next and surfaces Mercer's payoff. The freeform contract board lives
// alongside it.

import type { Mission, MissionObjective } from "@/types/game";

export interface CampaignChapter {
  id: string;
  act: string;
  title: string;
  /** Mercer's briefing — sets the stakes and teaches the verb. */
  intro: string;
  objective: MissionObjective;
  reward: { cash: number; reputation: number };
  scopeNote: string;
  /** Mercer's payoff after a successful exit. */
  outro: string;
}

export const CAMPAIGN: CampaignChapter[] = [
  {
    id: "ch-first-light",
    act: "I",
    title: "First Light",
    intro:
      "First job, so listen. Meridian's mail relay holds an asset register a client wants eyes on. You do NOT connect raw — build a proxy route first ('route add <proxy>'), then 'scan hq-node', 'connect', and 'cp /secrets.txt @local'. Get out before the trace climbs. Go quiet.",
    objective: { type: "exfil", hostId: "hq-node", targetPath: "/secrets.txt" },
    reward: { cash: 1800, reputation: 16 },
    scopeNote: "In scope: hq-node read paths only, this window. Read-only — leave no write artifacts.",
    outro:
      "Clean. You're steadier than most first-timers I've buried. Money's in your account — don't spend it being stupid.",
  },
  {
    id: "ch-paper-trail",
    act: "I",
    title: "Paper Trail",
    intro:
      "Someone at Orbital Freight is leaking routing manifests. I need a name behind the handle. This is OSINT, not intrusion — 'osint person-orbital --active' until you've tied a handle, an email and a breach record to the same person. Active probing writes to FOOTPRINT, so pace it.",
    objective: {
      type: "identify",
      hostId: "orbital",
      targetPersonId: "person-orbital",
      requiredKinds: ["handle", "email", "breach"],
    },
    reward: { cash: 2200, reputation: 20 },
    scopeNote: "In scope: person-orbital OSINT only. No touching the live freight API.",
    outro:
      "That's our leak. The client will handle it the boring legal way. You footprinted a human being and left no mark on them — that's the job done right.",
  },
  {
    id: "ch-dead-air",
    act: "I",
    title: "Dead Air",
    intro:
      "Charon runs a substation historian under heavy watch — too hot to touch directly. But there's an unlabeled emitter humming next to the control cage. Task a remote sensor: 'collect rf charon'. Band and signature only. We listen; we never knock.",
    objective: { type: "characterize", hostId: "charon", emitterId: "emitter-charon" },
    reward: { cash: 2000, reputation: 18 },
    scopeNote: "In scope: emitter-charon RF characterization only. No host contact.",
    outro:
      "Signature logged. Turns out their 'air-gapped' cage has a radio on it after all. That's how you map a target without ever being on it.",
  },
  {
    id: "ch-the-key",
    act: "I",
    title: "The Key",
    intro:
      "Polaris Capital's settlement mesh. We're going to do this like professionals: surface a breach record on their operator ('osint person-polaris --active'), then 'acquire polaris' to try those creds. If it takes, 'connect' authenticates quiet and you 'cp /secrets.txt @local'. Cold pops are for amateurs.",
    objective: { type: "exfil", hostId: "polaris", targetPath: "/secrets.txt" },
    reward: { cash: 2800, reputation: 24 },
    scopeNote: "In scope: polaris, credentialed access preferred. Read-only exfil.",
    outro:
      "In and out on borrowed keys. No alarms, no kicked-in doors. The good operators are the ones nobody can prove were ever there.",
  },
  {
    id: "ch-ghost",
    act: "I",
    title: "Ghost",
    intro:
      "Last one of the set, and it's the one that matters. Aurora's lab LIMS. I don't just want the data — I want a GHOST exit, every channel calm when you leave. Route deep, move slow, buy a quieter rig from 'market' if you have to. Make it like you were never there.",
    objective: { type: "exfil", hostId: "aurora", targetPath: "/data/vault.txt" },
    reward: { cash: 3400, reputation: 30 },
    scopeNote: "In scope: aurora LIMS read paths. The bonus is in the silence — exit clean.",
    outro:
      "Silence. Not a single tracer, not a flag. That's the work. You came in scared and you're leaving a ghost. Act I's done — but the network knows your handle now, and that changes the game. Act II when you're ready.",
  },

  // --- Act II: "The Operator" — you're known now; ATTRIBUTION is the new fear ---
  {
    id: "ch-known-quantity",
    act: "II",
    title: "Known Quantity",
    intro:
      "Word's out that you're good — and that cuts both ways. People watch HOW you work now. Pull the register off Helix's sequencing cluster, but mind your ATTRIBUTION: reusing the same proxy hops over and over builds a profile of you. Rotate your infrastructure.",
    objective: { type: "exfil", hostId: "helix", targetPath: "/secrets.txt" },
    reward: { cash: 3000, reputation: 24 },
    scopeNote: "In scope: helix read paths. Watch ATTRIBUTION — rotate proxies, don't reuse the same chain.",
    outro:
      "Got it. Notice how the ATTRIBUTION bar barely fell afterward? That one doesn't forget. Every job you do leaves a little more of a shape they can recognize.",
  },
  {
    id: "ch-crossed-wires",
    act: "II",
    title: "Crossed Wires",
    intro:
      "Mosaic's CDN origin has an emitter on the rack that shouldn't be there — someone's exfiltrating over RF. Characterize it: 'collect rf mosaic'. Use 'sweep' first to find it on the waterfall if you like.",
    objective: { type: "characterize", hostId: "mosaic", emitterId: "emitter-mosaic" },
    reward: { cash: 2600, reputation: 22 },
    scopeNote: "In scope: emitter-mosaic characterization. Passive listen only.",
    outro:
      "That signature matches a known smuggling rig. The client now knows their 'secure' origin has been leaking for months. Good ear.",
  },
  {
    id: "ch-the-tell",
    act: "II",
    title: "The Tell",
    intro:
      "Polaris Capital has an operator moving money they shouldn't. Build the full dossier — handle, email, breach AND device. That's a deep active sweep ('osint person-polaris --active'); it'll cost FOOTPRINT, so route deep and pace it.",
    objective: {
      type: "identify",
      hostId: "polaris",
      targetPersonId: "person-polaris",
      requiredKinds: ["handle", "email", "breach", "device"],
    },
    reward: { cash: 3400, reputation: 28 },
    scopeNote: "In scope: person-polaris OSINT, passive + active. Full attribution package required.",
    outro:
      "Four corroborating data points on one human. That holds up. The client has what they need and you never went near their network.",
  },
  {
    id: "ch-burn-notice",
    act: "II",
    title: "Burn Notice",
    intro:
      "Charon's historian again — the hot one. We need a manifest entry doctored ('edit /logs/manifest.log'). If your ATTRIBUTION is already high, this is exactly the job that gets you made. If it is, consider burning your identity first ('churn') — fresh start, steep price.",
    objective: { type: "modify", hostId: "charon", targetPath: "/logs/manifest.log" },
    reward: { cash: 3800, reputation: 30 },
    scopeNote: "In scope: charon single manifest edit. High monitoring — go quiet, exit fast.",
    outro:
      "Done, and you're still a rumour instead of a name. That's the whole game in Act II: the better you get, the harder you have to work to stay nobody.",
  },
  {
    id: "ch-operator",
    act: "II",
    title: "Operator",
    intro:
      "Last of the set. Axion's HPC login node — the crown jewel. I want the vault AND a ghost exit, every channel calm, ATTRIBUTION included. Route deep, churn first if you have to, buy a quiet rig. Show me you're not just good — you're an operator.",
    objective: { type: "exfil", hostId: "axion", targetPath: "/data/vault.txt" },
    reward: { cash: 4800, reputation: 40 },
    scopeNote: "In scope: axion read paths. The mark of an operator is the silence — exit clean on every channel.",
    outro:
      "Clean. Across every vector, including the one that follows you home. You're not the scared freelancer who took First Light. You're an operator now — and the network still doesn't have a name. That's the job. Mercer out.",
  },
];

/** Build the campaign chapters as Missions; only `currentChapter` is unlocked. */
export function buildCampaignMissions(now: number, currentChapter: number): Mission[] {
  return CAMPAIGN.map((c, index) => {
    const status =
      index < currentChapter ? "completed" : index === currentChapter ? "available" : "locked";
    return {
      id: `campaign-${c.id}`,
      title: `${c.title}  ·  Act ${c.act}`,
      description: c.intro,
      reward: c.reward,
      targetHost: c.objective.hostId ?? c.objective.targetPersonId ?? c.objective.emitterId ?? "—",
      deadline: now + (index + 2) * 1000 * 60 * 60 * 24, // generous; campaign isn't timed
      status,
      objective: c.objective,
      completed: index < currentChapter,
      scopeNote: c.scopeNote,
      chapterIndex: index,
    } satisfies Mission;
  });
}
