// AUTO-GENERATED baked content pack (link26-content-pack workflow).
// Generated once, served offline at zero per-play LLM cost. The free tier runs
// entirely on this; live LLM generation is the paid delighter (see docs).
// Hand-edit sparingly; prefer regenerating via the workflow.

import type { MissionObjective, MissionReward } from "@/types/game";

export interface PackMission {
  id: string;
  title: string;
  description: string;
  objective: MissionObjective;
  reward: MissionReward;
  scopeNote?: string;
}

export interface CodexCard {
  id: string;
  domain: string;
  title: string;
  concept: string;
  whyItMatters: string;
  ethics: string;
  attackTechniqueId?: string;
}

export interface MercerLine {
  situation: string;
  text: string;
}

export const PACK_MISSIONS: PackMission[] = [
  {
    "id": "mission-coldfront",
    "title": "Cold Front",
    "description": "Meridian's mail relay holds an asset register the client wants eyes on. Slip in clean, copy /secrets.txt to @local with cp, and back out leaving no write artifacts behind.",
    "objective": {
      "type": "exfil",
      "hostId": "hq-node",
      "targetPath": "/secrets.txt"
    },
    "reward": {
      "cash": 2200,
      "reputation": 19
    },
    "scopeNote": "In scope: hq-node read paths only, this 60-minute window. Read-only — any write trips the deal."
  },
  {
    "id": "mission-paperweight",
    "title": "Paperweight",
    "description": "A rival wants the relay's delivery manifest to lie. Edit /logs/manifest.log in place so the disputed batch reads as undelivered — surgical, single entry, then ghost out.",
    "objective": {
      "type": "modify",
      "hostId": "hq-node",
      "targetPath": "/logs/manifest.log"
    },
    "reward": {
      "cash": 2600,
      "reputation": 23
    },
    "scopeNote": "In scope: hq-node /logs only, 90-minute window. One entry — no broad rewrites, no second pass."
  },
  {
    "id": "mission-letterhead",
    "title": "Letterhead",
    "description": "We need attribution on the operator running Meridian's relay desk. Work the trail with osint --active until you can put a handle, a work email, an employer and a breach record against the same person.",
    "objective": {
      "type": "identify",
      "hostId": "hq-node",
      "targetPersonId": "person-hq-node",
      "requiredKinds": [
        "handle",
        "email",
        "employer",
        "breach"
      ]
    },
    "reward": {
      "cash": 3000,
      "reputation": 27
    },
    "scopeNote": "In scope: person-hq-node OSINT only — passive and active queries. No touching live relay assets."
  },
  {
    "id": "mission-driftwood",
    "title": "Driftwood",
    "description": "Orbital Freight's telemetry API quietly logs every freight handoff before it hits the books. Slip onto the box, pull the asset register, and copy it to @local — read-only, no write artifacts. scan orbital, route through a chain, connect, then cp /secrets.txt @local.",
    "objective": {
      "type": "exfil",
      "hostId": "orbital",
      "targetPath": "/secrets.txt"
    },
    "reward": {
      "cash": 1900,
      "reputation": 16
    },
    "scopeNote": "In-scope: orbital telemetry API host only, read paths. No writes, no lateral movement. 48h window."
  },
  {
    "id": "mission-paper-comet",
    "title": "Paper Comet",
    "description": "A client wants one container's chain-of-custody to read clean. Get onto Orbital Freight's telemetry node and doctor the manifest in place so the flagged entry never raises an exception. Tamper surgically with edit on /logs/manifest.log — leave the surrounding lines intact.",
    "objective": {
      "type": "modify",
      "hostId": "orbital",
      "targetPath": "/logs/manifest.log"
    },
    "reward": {
      "cash": 2400,
      "reputation": 21
    },
    "scopeNote": "In-scope: orbital host, single manifest edit. No exfil beyond verification read. 36h window."
  },
  {
    "id": "mission-tradewind",
    "title": "Tradewind",
    "description": "We have a handle posting Orbital Freight's internal routing screenshots to a logistics forum. Attribute the operator: tie the handle to a work email, an employer, and a breach record. This one's watched, so active probing will spike FOOTPRINT — pace it. osint <handle> --active.",
    "objective": {
      "type": "identify",
      "hostId": "orbital",
      "targetPersonId": "person-orbital",
      "requiredKinds": [
        "handle",
        "email",
        "employer",
        "breach"
      ]
    },
    "reward": {
      "cash": 2900,
      "reputation": 26
    },
    "scopeNote": "In-scope: passive OSINT plus measured active probing of person-orbital. No host intrusion. 72h window."
  },
  {
    "id": "mission-palebeacon",
    "title": "Pale Beacon",
    "description": "Aurora Diagnostics' LIMS holds a chain-of-custody ledger our client says was doctored. Scan the lab subnet, connect to the historian share, and cp the vault out clean — no writes, leave the timestamps breathing.",
    "objective": {
      "type": "exfil",
      "hostId": "aurora",
      "targetPath": "/data/vault.txt"
    },
    "reward": {
      "cash": 1400,
      "reputation": 13
    },
    "scopeNote": "ROE: aurora LIMS file shares only, read-only, 02:00-04:00 maintenance window. No lateral movement."
  },
  {
    "id": "mission-quietamber",
    "title": "Quiet Amber",
    "description": "We need a name behind the lab tech who signs off on Aurora's overnight assay runs. Run osint --active against person-aurora and build the dossier — handle, employer, working hours, and whether they show in any breach corpus.",
    "objective": {
      "type": "identify",
      "hostId": "aurora",
      "targetPersonId": "person-aurora",
      "requiredKinds": [
        "handle",
        "employer",
        "timezone",
        "breach"
      ]
    },
    "reward": {
      "cash": 2100,
      "reputation": 19
    },
    "scopeNote": "ROE: passive OSINT plus active enrichment on person-aurora only. No contact, no pretexting."
  },
  {
    "id": "mission-severgrove",
    "title": "Sever Grove",
    "description": "A whistleblower claims Aurora rewrites the manifest log to scrub failed sample IDs. Get in, edit /logs/manifest.log to seed a marked canary entry, and back out before the integrity sweep notices. Surgical only — one line, then dark.",
    "objective": {
      "type": "modify",
      "hostId": "aurora",
      "targetPath": "/logs/manifest.log"
    },
    "reward": {
      "cash": 2900,
      "reputation": 26
    },
    "scopeNote": "ROE: aurora only, single authorized log mutation, exit before the 05:00 integrity sweep. No destructive edits."
  },
  {
    "id": "mission-coldfront-x",
    "title": "Coldfront",
    "description": "Charon's historian is a SCADA archive under heavy watch — assume every keystroke is logged. Slip onto the box, copy the vault dump to @local, and break contact before the monitoring window cycles (scan charon, connect, cp /data/vault.txt @local). Read-only. Leave no write artifacts.",
    "objective": {
      "type": "exfil",
      "hostId": "charon",
      "targetPath": "/data/vault.txt"
    },
    "reward": {
      "cash": 3100,
      "reputation": 27
    },
    "scopeNote": "RoE: charon historian only, /data/vault.txt read-only; off-hours maintenance window, no persistence."
  },
  {
    "id": "mission-deadhand",
    "title": "Deadhand",
    "description": "The night-shift controller behind the Charon historian is our pivot point. Build an attribution package on them — handle, work email, and employer — using passive sweeps only so we never tip the high-monitoring host (osint person-charon, no --active). Tradecraft over speed.",
    "objective": {
      "type": "identify",
      "hostId": "charon",
      "targetPersonId": "person-charon",
      "requiredKinds": [
        "handle",
        "email",
        "employer"
      ]
    },
    "reward": {
      "cash": 2100,
      "reputation": 19
    },
    "scopeNote": "RoE: person-charon, passive OSINT only; no active probes against the historian."
  },
  {
    "id": "mission-tundra",
    "title": "Tundra",
    "description": "There's an unlabeled emitter humming next to the Charon control cage. Sit on it from a distance and characterize the carrier — band and signature, nothing more (collect rf charon). Stay passive; the historian must never know we listened.",
    "objective": {
      "type": "characterize",
      "hostId": "charon",
      "emitterId": "emitter-charon"
    },
    "reward": {
      "cash": 1500,
      "reputation": 14
    },
    "scopeNote": "RoE: emitter-charon RF capture only, characterization not collection; no host contact."
  },
  {
    "id": "mission-coldvault",
    "title": "Cold Vault",
    "description": "Iris keeps the offsite backup cradle for half the network — and the asset register lives unencrypted in the cold tier. Scan, connect, then cp /secrets.txt to @local. Read-only; do not leave a write artifact in the audit trail.",
    "objective": {
      "type": "exfil",
      "hostId": "iris",
      "targetPath": "/secrets.txt"
    },
    "reward": {
      "cash": 1900,
      "reputation": 17
    },
    "scopeNote": "In scope: iris object store, /secrets.txt only, this maintenance window. No writes, no lateral movement to mirrored peers."
  },
  {
    "id": "mission-snowblind",
    "title": "Snowblind",
    "description": "A retention manifest on the object store proves a backup set existed that the client needs to disappear. Edit /logs/manifest.log in place so the snapshot reads expired-and-purged. Make the tamper read clean, like a scheduled lifecycle event.",
    "objective": {
      "type": "modify",
      "hostId": "iris",
      "targetPath": "/logs/manifest.log"
    },
    "reward": {
      "cash": 2400,
      "reputation": 21
    },
    "scopeNote": "In scope: iris, /logs/manifest.log only. Single in-place edit during the window. Leave checksums elsewhere untouched."
  },
  {
    "id": "mission-driftsignal",
    "title": "Drift Signal",
    "description": "We have a handle tied to the Iris backup admin but no body behind it. Run osint --active and assemble enough to put a name, a region, and a prior exposure on them. Build the dossier; don't burn the handle.",
    "objective": {
      "type": "identify",
      "hostId": "iris",
      "targetPersonId": "person-iris",
      "requiredKinds": [
        "handle",
        "employer",
        "timezone",
        "breach"
      ]
    },
    "reward": {
      "cash": 2800,
      "reputation": 26
    },
    "scopeNote": "In scope: passive and active OSINT on person-iris. Dossier assembly only — no contact, no host access."
  },
  {
    "id": "mission-doublehelix",
    "title": "Double Helix",
    "description": "Helix Genomics keeps its raw sequencing vault behind the cluster's login node. Get in clean and lift /data/vault.txt to @local — read-only, no write artifacts, walk it back out the way you came in.",
    "objective": {
      "type": "exfil",
      "hostId": "helix",
      "targetPath": "/data/vault.txt"
    },
    "reward": {
      "cash": 2600,
      "reputation": 22
    },
    "scopeNote": "RoE: helix sequencing cluster only, /data/vault.txt in scope; copy-out via cp, no writes to the host. 60-minute window."
  },
  {
    "id": "mission-chimera",
    "title": "Chimera",
    "description": "A client wants one sample's chain-of-custody to read clean. Tamper the run manifest in place with edit so the flagged batch shows as validated — surgical, one entry, nothing else touched.",
    "objective": {
      "type": "modify",
      "hostId": "helix",
      "targetPath": "/logs/manifest.log"
    },
    "reward": {
      "cash": 1900,
      "reputation": 16
    },
    "scopeNote": "RoE: in-place edit of /logs/manifest.log on helix; alter the single flagged batch line only, leave timestamps coherent. 45-minute window."
  },
  {
    "id": "mission-karyotype",
    "title": "Karyotype",
    "description": "Attribute the lead operator running the Helix sequencing cluster. Build a clean profile from passive sources, then go active to pin a breach record — handle, work email, employer, and the breach (osint <handle> --active).",
    "objective": {
      "type": "identify",
      "hostId": "helix",
      "targetPersonId": "person-helix",
      "requiredKinds": [
        "handle",
        "email",
        "employer",
        "breach"
      ]
    },
    "reward": {
      "cash": 3100,
      "reputation": 27
    },
    "scopeNote": "RoE: OSINT against person-helix; passive enrichment plus one active breach lookup. No contact with the subject. Open-ended window."
  },
  {
    "id": "mission-deaddrop",
    "title": "Dead Drop",
    "description": "Polaris Capital runs a settlement mesh that reconciles overnight. Get in clean, locate the vault ledger at /data/vault.txt and pull it before the morning close. Connect, map the share, cp the file out the same path you came in.",
    "objective": {
      "type": "exfil",
      "hostId": "polaris",
      "targetPath": "/data/vault.txt"
    },
    "reward": {
      "cash": 2900,
      "reputation": 26
    },
    "scopeNote": "ROE: settlement mesh host polaris only; exfil /data/vault.txt during the overnight reconciliation window. No lateral movement."
  },
  {
    "id": "mission-tideglass",
    "title": "Tideglass",
    "description": "We need a read on the operator behind Polaris settlements before the next contract. Run osint --active against person-polaris and bring back enough to put a name, an inbox, and a payroll to the keyboard. Light touch, but go active where you must.",
    "objective": {
      "type": "identify",
      "hostId": "polaris",
      "targetPersonId": "person-polaris",
      "requiredKinds": [
        "handle",
        "email",
        "employer"
      ]
    },
    "reward": {
      "cash": 1800,
      "reputation": 16
    },
    "scopeNote": "ROE: person-polaris only; active OSINT permitted on handle, email, and employer pivots. No breach or device probing."
  },
  {
    "id": "mission-greymeridian",
    "title": "Grey Meridian",
    "description": "Client wants the shape of the Polaris settlement mesh, not its contents. Scan and connect, then characterize the host: posture, monitoring cadence, how it breathes. Polaris watches its perimeter, so move like you belong. No data leaves.",
    "objective": {
      "type": "characterize",
      "hostId": "polaris",
      "emitterId": "emitter-polaris"
    },
    "reward": {
      "cash": 2300,
      "reputation": 21
    },
    "scopeNote": "ROE: characterize host polaris from inside the perimeter; profiling only, zero exfil or modification."
  },
  {
    "id": "mission-dead-bus",
    "title": "Dead Bus",
    "description": "Solstice runs a substation gateway with hot monitoring, so move quiet. Route in, lift the relay-protection config off /data/vault.txt to @local, and leave no write artifacts. Scan, connect, cp — read-only.",
    "objective": {
      "type": "exfil",
      "hostId": "solstice",
      "targetPath": "/data/vault.txt"
    },
    "reward": {
      "cash": 2600,
      "reputation": 24
    },
    "scopeNote": "RoE: solstice gateway only, /data/vault.txt read-only. Off-hours window, no writes, no lateral movement."
  },
  {
    "id": "mission-phantom-load",
    "title": "Phantom Load",
    "description": "The substation historian's event manifest needs a quiet edit — bury one breaker-trip entry so the load profile reads clean. Tamper /logs/manifest.log in place with edit, then back out before the dwell clock closes.",
    "objective": {
      "type": "modify",
      "hostId": "solstice",
      "targetPath": "/logs/manifest.log"
    },
    "reward": {
      "cash": 3000,
      "reputation": 27
    },
    "scopeNote": "RoE: solstice gateway, /logs/manifest.log in-place modify only. Short maintenance window, single entry, no payload drop."
  },
  {
    "id": "mission-grounding-fault",
    "title": "Grounding Fault",
    "description": "Attribute the duty engineer behind the Solstice grid-ops handle. Stitch a handle, a work email and an employer to one operator, then pin their timezone for shift mapping. Run osick passive then osint --active to close the breach line.",
    "objective": {
      "type": "identify",
      "hostId": "solstice",
      "targetPersonId": "person-solstice",
      "requiredKinds": [
        "handle",
        "email",
        "employer",
        "timezone"
      ]
    },
    "reward": {
      "cash": 1900,
      "reputation": 18
    },
    "scopeNote": "RoE: person-solstice attribution only. Passive recon first; one active osint pass authorized to confirm. No host intrusion."
  },
  {
    "id": "mission-greyscale",
    "title": "Greyscale",
    "description": "Mosaic Media's CDN origin is leaking more than cat videos. Get in quiet, scan the perimeter, connect through the edge, and cp /data/vault.txt before their ops crew rotates the caches. In and out before the logs settle.",
    "objective": {
      "type": "exfil",
      "hostId": "mosaic",
      "targetPath": "/data/vault.txt"
    },
    "reward": {
      "cash": 1600,
      "reputation": 15
    },
    "scopeNote": "ROE: mosaic origin node only; data-plane read paths in-scope; 02:00-04:00 maintenance window."
  },
  {
    "id": "mission-paperghost",
    "title": "Paper Ghost",
    "description": "Client wants the human behind person-mosaic, not the box. Stay passive — osint the public surface, no active touch. Build us a clean dossier: handle, employer, and the timezone they actually keep. Whisper-quiet collection only.",
    "objective": {
      "type": "identify",
      "hostId": "mosaic",
      "targetPersonId": "person-mosaic",
      "requiredKinds": [
        "handle",
        "employer",
        "timezone"
      ]
    },
    "reward": {
      "cash": 1350,
      "reputation": 13
    },
    "scopeNote": "ROE: passive OSINT against person-mosaic only; no active probing or contact; open-source surface in-scope."
  },
  {
    "id": "mission-broadcast",
    "title": "Broadcast",
    "description": "We need the shape of emitter-mosaic, not its contents. Collect rf across the band, characterize the origin's broadcast signature — duty cycle, channel posture, how it behaves under load. Sit on it long enough to be sure, then fade.",
    "objective": {
      "type": "characterize",
      "hostId": "mosaic",
      "emitterId": "emitter-mosaic"
    },
    "reward": {
      "cash": 2400,
      "reputation": 22
    },
    "scopeNote": "ROE: passive RF collection on emitter-mosaic only; characterization, no injection; standoff posture."
  },
  {
    "id": "mission-coldfront-x-x",
    "title": "Cold Front",
    "description": "Axion's HPC login node fronts the whole compute fabric. Slip in over the jump host, pull the vault export read-only, and cp it to @local — touch nothing, leave no write artifacts. The box is a chokepoint, so keep the route long and quiet.",
    "objective": {
      "type": "exfil",
      "hostId": "axion",
      "targetPath": "/payload.bin"
    },
    "reward": {
      "cash": 2600,
      "reputation": 22
    },
    "scopeNote": "ROE: in-scope is axion's /payload.bin only, read-only exfil; 6-hour window, no destructive ops."
  },
  {
    "id": "mission-paperweight-x",
    "title": "Paperweight",
    "description": "The client wants Axion's batch-job manifest to read clean on the next reconciliation pass. Get on the node and tamper the manifest in place with edit — flip the state field, leave the checksum looking plausible. Surgical, then off.",
    "objective": {
      "type": "modify",
      "hostId": "axion",
      "targetPath": "/logs/manifest.log"
    },
    "reward": {
      "cash": 1900,
      "reputation": 16
    },
    "scopeNote": "ROE: modify axion:/logs/manifest.log in place only; 4-hour window, no exfil, restore on contact loss."
  },
  {
    "id": "mission-driftwood-x",
    "title": "Driftwood",
    "description": "We have a loose handle tied to the Axion compute desk and need attribution before the client moves. Footprint the operator with osint --active until you've pinned an identity, a work email, and a fresh breach hit. Active recon spikes FOOTPRINT — pace it.",
    "objective": {
      "type": "identify",
      "hostId": "axion",
      "targetPersonId": "person-axion",
      "requiredKinds": [
        "handle",
        "email",
        "breach"
      ]
    },
    "reward": {
      "cash": 2400,
      "reputation": 24
    },
    "scopeNote": "ROE: person-axion only; assemble handle + email + breach cards via active OSINT; expect elevated FOOTPRINT."
  }
];

export const CODEX: CodexCard[] = [
  {
    "id": "recon-01",
    "domain": "network recon & access",
    "title": "Passive Recon: Listening Before Touching",
    "concept": "Before an operator ever sends a packet at a target, they assemble a picture from sources that never touch the target's own infrastructure: public registration records, certificate transparency logs, archived pages, leaked-credential corpora, and employees' own published footprints. The mental model is that an organization radiates information into the world for free, and a careful adversary reconstructs the org chart, tech stack, and trust relationships purely from that exhaust. Nothing is probed, so nothing is logged on the target side.",
    "whyItMatters": "Defenders who only watch their own logs are blind to this phase entirely; reducing public exposure (attack-surface management) is the only counter, because you cannot detect what you cannot see.",
    "ethics": "Aggregating public data is lawful, but the moment collection is used to target an organization without authorization the intent crosses into reconnaissance for an attack.",
    "attackTechniqueId": "T1592"
  },
  {
    "id": "recon-02",
    "domain": "network recon & access",
    "title": "Active Scanning: The Tradeoff Between Knowing and Being Seen",
    "concept": "Active recon means actually sending traffic to a target to learn which hosts are alive, which ports answer, and what software sits behind them. The core tension is fidelity versus stealth: loud, fast, comprehensive sweeps yield rich maps but light up every sensor, while slow, distributed, low-and-slow probing trades completeness for staying under detection thresholds. Every response, banner, and timing quirk is a data point that narrows the guess about what's really running.",
    "whyItMatters": "Scan signatures are one of the most reliable early-warning signals a SOC has; understanding the stealth-versus-coverage curve helps defenders tune detection so they catch the patient adversary, not just the noisy one.",
    "ethics": "Even read-only scanning of systems you don't own or have written permission to test is unauthorized access in many jurisdictions, regardless of whether anything breaks.",
    "attackTechniqueId": "T1595"
  },
  {
    "id": "recon-03",
    "domain": "network recon & access",
    "title": "Service Fingerprinting: Inference From Behavior",
    "concept": "An open port only tells you something is listening; fingerprinting is the art of inferring what it is and which version, often without being told. Operators read subtle tells - response ordering, error phrasing, default headers, protocol-handshake idiosyncrasies - and match them against known behavioral profiles. The mental model is that software has an accent: even when it tries to hide its name, the way it speaks gives it away, and a version guess maps directly to a list of known weaknesses.",
    "whyItMatters": "Banner-grabbing and version inference are precisely what lets an adversary skip blind guessing; defenders counter with banner suppression, deception, and patching the things their own external fingerprint reveals.",
    "ethics": "Fingerprinting blurs into intrusion preparation; doing it against systems outside an authorized scope is the legally meaningful step, not a harmless curiosity.",
    "attackTechniqueId": "T1046"
  },
  {
    "id": "recon-04",
    "domain": "network recon & access",
    "title": "Initial Access: The Front Door Is Usually a Person",
    "concept": "Despite the imagery of breaking through firewalls, the most common way in is a valid credential or a tricked human, not a clever exploit. The mental model is that authentication is a trust assertion, and adversaries prefer to inherit trust rather than defeat it - phishing a login, reusing a credential exposed elsewhere, or abusing a legitimate remote-access path. Exploiting a software flaw is a fallback, used when no easier path through existing trust exists.",
    "whyItMatters": "It reframes defense from 'patch everything' to 'assume credentials leak' - driving MFA, phishing-resistant auth, and least privilege, which blunt the dominant access vector rather than the rare one.",
    "ethics": "Testing initial-access vectors against real people or accounts without explicit, scoped authorization is both unlawful and a breach of the trust those people extend to their employer.",
    "attackTechniqueId": "T1078"
  },
  {
    "id": "recon-05",
    "domain": "network recon & access",
    "title": "The Attack Surface Is a Set of Assumptions",
    "concept": "An attack surface is not just a list of exposed services - it's every assumption an organization makes about who can reach what, and under which conditions those assumptions silently fail. Forgotten subdomains, a vendor's over-broad access, a test box that outlived its purpose, a trust relationship between two systems nobody re-examines: each is a place where reality drifted from the diagram. Recon, fundamentally, is the disciplined search for the gap between the intended architecture and the deployed one.",
    "whyItMatters": "Defenders win this phase through inventory and continuous discovery, because an adversary only needs to find one stale assumption while the defender must account for all of them.",
    "ethics": "Mapping someone else's drift to exploit it is an attack; mapping your own, or a client's with a signed scope, is the legitimate mirror image of the same skill.",
    "attackTechniqueId": "T1590"
  },
  {
    "id": "osint-01",
    "domain": "OSINT & attribution",
    "title": "The Attack Surface You Published Yourself",
    "concept": "Open-source intelligence treats an organization's public exhaust as a single coherent picture rather than scattered facts. Job postings reveal the tech stack, conference talks reveal architecture, employee bios reveal org structure, and certificate transparency logs reveal hostnames nobody meant to advertise. No system is touched and no law is bent; the work is correlation, not intrusion. The skill is not finding data but knowing which fragments, joined together, become a map.",
    "whyItMatters": "Defenders who never audit their own public footprint are graded on a test they never see. Knowing what an adversary can assemble for free lets you decide what is genuinely worth scrubbing versus accepting.",
    "ethics": "Collecting public data is lawful, but aggregating it into a dossier on individuals can cross into harassment and privacy violations regardless of source legality.",
    "attackTechniqueId": "T1593"
  },
  {
    "id": "osint-02",
    "domain": "OSINT & attribution",
    "title": "Pivoting: One Selector, A Whole Graph",
    "concept": "Investigation rarely starts with the answer; it starts with one selector — an email handle, a reused avatar, a registrant detail — and expands outward. Each confirmed link becomes a new starting point, growing a graph of related accounts and infrastructure. The danger is the false pivot: a shared hosting provider or a common username is correlation, not identity. Disciplined analysts weight each edge by how uniquely it ties two nodes together.",
    "whyItMatters": "Both defenders mapping a threat actor and operators mapping a target rely on pivoting, so understanding its failure modes is what separates a sound lead from a confidently wrong one.",
    "ethics": "Pivoting on a person rather than infrastructure demands a legitimate, documented purpose; idle curiosity about an individual is where ethical investigation quietly becomes stalking.",
    "attackTechniqueId": "T1591"
  },
  {
    "id": "osint-03",
    "domain": "OSINT & attribution",
    "title": "Attribution Is A Confidence Level, Not A Name",
    "concept": "Attribution answers 'who did this' as a probability statement, never a certainty. Analysts weigh tooling overlap, infrastructure reuse, language and timezone artifacts, and target selection — then assign confidence (low, moderate, high) with explicit reasoning. The mature posture is layered: the same operator may be tracked as a technical cluster long before anyone names a sponsor. Collapsing those layers into a headline is how analysis becomes folklore.",
    "whyItMatters": "Treating a named actor as fact rather than assessment leads organizations to build defenses against a story instead of the behaviors actually hitting them.",
    "ethics": "Publicly naming a culprit on thin evidence can defame the innocent and provoke real-world retaliation, so confidence language is an ethical obligation, not academic hedging.",
    "attackTechniqueId": "T1591"
  },
  {
    "id": "osint-04",
    "domain": "OSINT & attribution",
    "title": "False Flags And The Deception Layer",
    "concept": "Sophisticated actors know they are being attributed and feed the process deliberately. They plant another group's tooling, mimic foreign keyboard layouts, register infrastructure to look like someone else, or operate in borrowed working hours. The lesson is epistemic: every indicator is also a potential plant, and the cheapest signals to fake are the loudest in naive reports. Analysts counter this by weighting hard-to-forge behavioral patterns over easy-to-spoof artifacts.",
    "whyItMatters": "An adversary who can shape your attribution can steer your response, your public statements, and even your diplomatic posture — making the investigator a target of manipulation.",
    "ethics": "Recognizing deception is defensive analysis; manufacturing false flags to frame a third party is information warfare and squarely off-limits.",
    "attackTechniqueId": "T1036"
  },
  {
    "id": "osint-05",
    "domain": "OSINT & attribution",
    "title": "The Observer Effect: Collection Leaves Tracks",
    "concept": "OSINT feels passive, but it is rarely invisible. Visiting a niche page, resolving a hostname, or querying a record can register on infrastructure the target controls, and a sudden spike of interest is itself a signal. Counterintelligence-minded operators seed canary documents and watering-hole tells precisely to learn who is looking. The mental model: there is a spectrum from truly passive (third-party archives) to semi-active (direct lookups), and the line matters more than it looks.",
    "whyItMatters": "Defenders can detect reconnaissance by watching for these tells, while anyone gathering intelligence must understand that the act of looking can tip off the very party they hoped to study quietly.",
    "ethics": "There is a real legal boundary between observing public data and probing systems you have no authorization to touch; staying on the passive side of that line is what keeps research lawful.",
    "attackTechniqueId": "T1597"
  },
  {
    "id": "rf-001",
    "domain": "RF collection",
    "title": "The Spectrum Is the Map",
    "concept": "Every wireless emitter — a fob, a meter, a sensor mesh — carves out a slice of the radio spectrum at a given frequency, bandwidth, and modulation. A collector's first job is never decoding; it is cartography: sweeping a band to learn what is even transmitting, when, and how often. Energy where you expect silence is itself intelligence. The emitter's mere existence, its 'electromagnetic shadow', often tells you more than its contents.",
    "whyItMatters": "Defenders who only think about payloads miss that simply broadcasting reveals presence, vendor, and rhythm. Knowing your own emission footprint is the first step to controlling it.",
    "ethics": "Passively listening to spectrum you are not authorized to monitor still crosses legal lines in most jurisdictions, even if you never decode a thing."
  },
  {
    "id": "rf-002",
    "domain": "RF collection",
    "title": "Passive vs. Active: The Quiet Line",
    "concept": "Collection splits into passive (you only receive, emitting nothing, leaving no trace) and active (you transmit to probe, interrogate, or stimulate a response — and in doing so announce yourself). Passive work is patient and deniable but limited to what targets volunteer. Active work is faster and richer but radiates, meaning a defender with the right ear can detect the collector. The whole discipline is a negotiation between curiosity and exposure.",
    "whyItMatters": "Understanding that probing is detectable lets blue teams hunt for the unusual interrogations and reflections that betray an adversary's active reconnaissance.",
    "ethics": "Active probing transmits onto bands and devices you may not own — that emission can itself be an unauthorized intrusion, not mere observation.",
    "attackTechniqueId": "T1595"
  },
  {
    "id": "rf-003",
    "domain": "RF collection",
    "title": "Metadata Outlives Encryption",
    "concept": "Even when a link is perfectly encrypted, the externals leak: who talks to whom, packet sizes, timing, retransmission patterns, and signal strength. This 'traffic analysis' is the oldest trick in signals work because it survives crypto entirely. A burst of activity at an odd hour, or two emitters that always wake together, can reconstruct a relationship or an event without a single plaintext byte.",
    "whyItMatters": "Teams often equate encryption with privacy; in reality, patterns of life remain exposed, so padding, cover traffic, and constant-rate channels matter as much as the cipher.",
    "ethics": "Building behavioral profiles from emissions, even unencrypted ones, can constitute surveillance and must respect consent and legal authority."
  },
  {
    "id": "rf-004",
    "domain": "RF collection",
    "title": "Every Transmitter Has a Fingerprint",
    "concept": "No two radios are identical. Minute imperfections in oscillators, power amplifiers, and filters imprint a stable, hard-to-fake signature on the waveform itself — the 'RF fingerprint' — independent of any address or identifier the device advertises. This is why spoofing a MAC or device ID does not necessarily change who you are at the physical layer; the hardware's analog quirks persist beneath the digital costume.",
    "whyItMatters": "Physical-layer fingerprinting both empowers defenders to detect rogue or cloned devices and warns operators that changing logical identifiers alone is not true anonymity.",
    "ethics": "Fingerprinting can re-identify individuals' devices across contexts, so its use demands the same care as any biometric-grade identifier."
  },
  {
    "id": "rf-005",
    "domain": "RF collection",
    "title": "Geometry Turns Signal Into Location",
    "concept": "A single antenna hears a voice; multiple antennas hear a direction. By comparing the angle a wave arrives from, or the tiny differences in when the same burst reaches separated receivers, collectors triangulate an emitter in space — direction-finding and time-difference geolocation. The signal need not be understood at all; physics and geometry alone convert 'something is transmitting' into 'it is over there'.",
    "whyItMatters": "It reframes a transmitter as a beacon that betrays position, reminding operators that the only truly safe emission is the one you never send.",
    "ethics": "Geolocating a person's device traces their movements and presence — functionally tracking, which is lawful only under strict authority and consent."
  },
  {
    "id": "elint-01",
    "domain": "ELINT signal characterization",
    "title": "A Signal Is a Fingerprint, Not Just a Frequency",
    "concept": "Every emitter leaves a measurable identity beyond the channel it sits on. Carrier frequency tells you where to listen; the real story lives in the parameters around it: pulse width, pulse repetition interval, modulation type, scan pattern, and rise-time. Characterization is the discipline of measuring those parameters precisely enough that two emitters of the same model can be told apart. The intercepted waveform is treated as evidence to be described, not a door to be opened.",
    "whyItMatters": "Defenders who understand that their own emitters are uniquely describable stop assuming that hiding the frequency hides the platform. Spectrum hygiene is an identity problem, not just a tuning problem.",
    "ethics": "Characterization observes emissions already in the open air and never justifies injecting, jamming, or interfering with a signal you do not own."
  },
  {
    "id": "elint-02",
    "domain": "ELINT signal characterization",
    "title": "The Parameter Vector and the Library",
    "concept": "Raw intercepts are reduced to a structured descriptor, sometimes called a parameter vector, that captures the stable features of an emitter. That descriptor is matched against a reference library of previously characterized signals to assign identity and intent. The hard part is not the match; it is deciding which features are stable across conditions and which are noise, drift, or deliberate variation. A good library encodes uncertainty, not just labels.",
    "whyItMatters": "It mirrors how any detection program works: the quality of your reference corpus and your feature stability assumptions determine whether you classify confidently or fool yourself with false matches.",
    "ethics": "Reference libraries describe device behavior in the abstract; they are not a roster of people or a tool for targeting individuals."
  },
  {
    "id": "elint-03",
    "domain": "ELINT signal characterization",
    "title": "Deinterleaving: Separating Many Voices in One Room",
    "concept": "A real spectral environment is a dense overlap of pulses from many emitters arriving jumbled in time. Deinterleaving is the analytic step of sorting that mixture back into per-emitter streams using consistencies in timing, angle of arrival, and amplitude. It is fundamentally a clustering problem under heavy ambiguity, and it degrades gracefully rather than failing cleanly. The skill is reasoning about which separations are real versus artifacts of a crowded scene.",
    "whyItMatters": "The same mental model applies to log correlation and event reconstruction: when many sources interleave, your confidence comes from independent corroborating dimensions, not any single field.",
    "ethics": "Sorting emitters is an analysis of aggregate spectrum, not a license to single out or geolocate a specific operator."
  },
  {
    "id": "elint-04",
    "domain": "ELINT signal characterization",
    "title": "Intentional Modulation on Pulse — the Unintended Tell",
    "concept": "Beyond the parameters an emitter is designed to broadcast, manufacturing tolerances leave subtle, unintended imperfections in each transmission. These minute fingerprints can persist even when an operator changes settings to look like something else. Characterizing them is a probabilistic claim about hardware identity, always expressed with a confidence level, never as certainty. The discipline respects the gap between a strong correlation and proof.",
    "whyItMatters": "It is the RF analogue of device fingerprinting: defenders learn that even normalized, spoofed traffic can carry residual hardware tells, and that such tells are evidence to weigh, not verdicts.",
    "ethics": "Hardware-level identification stays at the level of equipment classes and is never used to attribute actions to a named person without due process."
  },
  {
    "id": "elint-05",
    "domain": "ELINT signal characterization",
    "title": "Passive by Doctrine, Lawful by Mandate",
    "concept": "ELINT characterization is defined by listening without ever transmitting; the analyst is a silent observer who changes nothing in the environment. That passivity is both a technical posture and a legal boundary. Authority to collect, where you may collect, and what you may retain are set by mandate and oversight, not by capability. The professional reflex is to ask whether collection is authorized before asking whether it is possible.",
    "whyItMatters": "It reframes the whole domain for practitioners: the constraint that matters is governance, and the most senior signal of competence is knowing what you are not permitted to touch.",
    "ethics": "Spectrum monitoring is lawful only within a defined mandate and oversight regime; capability never substitutes for authorization."
  },
  {
    "id": "opsec-01",
    "domain": "operational security (OPSEC)",
    "title": "The Indicator Lifecycle",
    "concept": "OPSEC begins by inverting the analyst's lens: you study your own operation the way an adversary would, hunting for indicators — small, observable fragments that, aggregated over time, reconstruct intent. No single breadcrumb is damning; the danger is correlation. A login hour, a writing cadence, a recurring tool fingerprint, a habit of working holidays — each is noise alone and signal in aggregate. Mature OPSEC treats every observable as something with a lifespan that must be managed, not just hidden once.",
    "whyItMatters": "Defenders win by collecting and correlating, so operators and protectors alike must reason about which crumbs accumulate into a pattern long before any single one looks alarming.",
    "ethics": "Studying your own footprint is hygiene; harvesting another person's footprint without authorization crosses into surveillance and is off-limits."
  },
  {
    "id": "opsec-02",
    "domain": "operational security (OPSEC)",
    "title": "Attribution Lives in the Mistakes",
    "concept": "Sophisticated actors are rarely unmasked by their best work; they are unmasked by the one moment they forgot which identity they were wearing. Attribution is built from cross-contamination: a persona that reuses a phrase from real life, an account that touches both a clean and a dirty context, a timezone that leaks through localized timestamps. The mental model is compartmentalization — identities, infrastructure, and devices kept in sealed lanes that never see each other — and the discipline is accepting that one lapse can retroactively connect everything you ever did.",
    "whyItMatters": "Threat-intel teams build entire actor profiles from these slip-ups, so understanding how lanes leak teaches defenders where to look and reminds operators that consistency, not cleverness, is the real cost.",
    "ethics": "De-anonymizing a real individual outside an authorized, scoped engagement is harassment or worse, never a flex."
  },
  {
    "id": "opsec-03",
    "domain": "operational security (OPSEC)",
    "title": "The Human Is the Side Channel",
    "concept": "Tooling can be hardened to near-perfection while the operator quietly leaks everything through behavior. People are creatures of pattern: they brag, they reuse passphrases conceptually, they answer pretext questions to be polite, they cannot resist confirming a guess. Social engineering does not defeat encryption — it routes around it through the trusting human in the loop. Good OPSEC therefore models the operator's own ego, fatigue, and helpfulness as exploitable attack surface, and builds rituals that don't depend on perfect willpower in a bad moment.",
    "whyItMatters": "Most real-world compromises start with a person, not a zero-day, so defenders who train the human layer and operators who distrust their own impulses close the widest gap.",
    "ethics": "Pretexting and manipulation against real people without consent is fraud; the only legitimate practice is authorized, scoped, and debriefed."
  },
  {
    "id": "opsec-04",
    "domain": "operational security (OPSEC)",
    "title": "Metadata Outlives the Message",
    "concept": "You can encrypt the contents of a conversation and still surrender the most valuable intelligence in the envelope around it. Who talked to whom, when, how often, from where, and for how long — the pattern-of-life — frequently matters more than what was said. Metadata is sticky: it is generated automatically, retained by intermediaries you don't control, and resists deletion because copies exist everywhere the signal traveled. The mental model is that confidentiality of content and confidentiality of the relationship graph are two separate problems, and the second is usually the harder one.",
    "whyItMatters": "Network and traffic analysis can map an entire organization without ever reading a payload, so both blue and red sides must reason about exposure that survives encryption.",
    "ethics": "Mapping a real person's contacts or movements without authorization is surveillance and strictly out of scope."
  },
  {
    "id": "opsec-05",
    "domain": "operational security (OPSEC)",
    "title": "OPSEC Decays Without a Threat Model",
    "concept": "OPSEC is not a checklist of paranoid habits; it is a rational allocation of effort against a defined adversary. Without naming who you are defending against, what they can observe, and what they are willing to spend, every control is either theater or overkill — and overkill itself becomes an indicator, since unusual caution is conspicuous. The discipline is to blend in rather than stand out, to right-size protections to a stated capability, and to revisit the model as the adversary, the operation, and your own habits drift over time.",
    "whyItMatters": "A threat model turns scattered precautions into defensible decisions, and it keeps teams from burning trust and budget guarding against the wrong opponent.",
    "ethics": "A threat model is a defensive planning tool; it is never a license to act against a real party outside lawful, authorized boundaries."
  },
  {
    "id": "roe-01",
    "domain": "rules of engagement & red-team ethics",
    "title": "The Engagement Letter Is the Operation",
    "concept": "A red-team engagement exists only inside a signed scope document: named asset ranges, a time window, allowed techniques, and a person with the legal authority to grant access. The same action is sanctioned testing inside that boundary and a crime one inch outside it — intent and skill change nothing, only authorization does. The document is not paperwork wrapped around the work; it is the thing that makes the work lawful at all.",
    "whyItMatters": "Defenders and operators who internalize this never improvise scope mid-op, because they understand the contract is their only legal cover and the client's only guarantee.",
    "ethics": "Acting outside the written authorization is not 'gray area' — it is unauthorized access, regardless of how benign the intent."
  },
  {
    "id": "roe-02",
    "domain": "rules of engagement & red-team ethics",
    "title": "Authorization Is Layered, Not Singular",
    "concept": "The party who hires you may not own everything you can technically reach: cloud tenants, payment processors, upstream SaaS, and shared landlords each have their own consent boundary. A signature from one stakeholder does not extend to third parties whose systems merely sit in the blast radius. Mapping who can lawfully say yes to each asset is part of planning, not an afterthought.",
    "whyItMatters": "Pivoting through a legitimately-owned box into a third party's tenant is how an authorized test silently becomes a multi-party incident with no consent behind it.",
    "ethics": "Consent must be obtained from each entity whose systems are touched; one client's permission cannot grant access to someone else's property."
  },
  {
    "id": "roe-03",
    "domain": "rules of engagement & red-team ethics",
    "title": "Deconfliction and the Get-Out-of-Jail Channel",
    "concept": "A mature engagement establishes a trusted-agent line and a deconfliction protocol before anything starts: a small group who know the test is live, an authorization letter operators carry, and a way to instantly distinguish red-team noise from a real intruder. When the blue team detects activity, deconfliction answers one question fast — is this us or someone else? — so the client never burns an incident response on a sanctioned ghost.",
    "whyItMatters": "Without it, a successful red team can trigger costly real-world escalations, legal calls, or law-enforcement involvement against its own operators.",
    "ethics": "Operators carry written proof of authorization and a named contact precisely so a tense moment resolves through a phone call, not a misunderstanding."
  },
  {
    "id": "roe-04",
    "domain": "rules of engagement & red-team ethics",
    "title": "Minimize Impact, Preserve the Patient",
    "concept": "The objective is to demonstrate risk, not to realize it. That means proving you could exfiltrate without hauling out real sensitive records, showing privilege without trashing the environment, and treating production stability and personal data as constraints rather than collateral. Skilled teams capture enough evidence to prove the finding and then stop, because the deliverable is insight, not damage.",
    "whyItMatters": "A client measures a red team by clarity of findings and trust earned, not by destruction; reckless impact destroys both the relationship and the program's mandate.",
    "ethics": "Even when in-scope, you avoid unnecessary harm to data, availability, and bystanders — proof of risk never requires inflicting the loss."
  },
  {
    "id": "roe-05",
    "domain": "rules of engagement & red-team ethics",
    "title": "Handle, Report, and Forget",
    "concept": "Whatever an operator sees during an engagement — credentials, customer data, embarrassing internal facts — is held in trust, encrypted in transit and at rest, and destroyed on a defined schedule once reporting is done. Findings flow to the authorized recipients through agreed channels, not to social feeds or résumés. The chain of custody and a duty of confidentiality outlive the engagement window itself.",
    "whyItMatters": "A red team's entire value rests on being trusted with the keys; one leaked artifact or loose disclosure ends careers and contracts.",
    "ethics": "Discovered data is the client's property under NDA — it is reported responsibly, never retained, sold, bragged about, or weaponized."
  }
];

export const MERCER_LINES: MercerLine[] = [
  {
    "situation": "intro",
    "text": "Mercer. I run your line. You don't know my face, I don't want yours. We move quiet, we get paid, nobody remembers we were there."
  },
  {
    "situation": "intro",
    "text": "New on the wire? Rule one: the job's done when you're gone, not when you're in. Anyone can break a door. Pros close it behind them."
  },
  {
    "situation": "intro",
    "text": "I'm your handler. I scope targets, you do the work, we both stay breathing. First mistake's free. After that I start charging interest."
  },
  {
    "situation": "clean_exit",
    "text": "In and out, no trail. That's the job. Logs scrubbed, session torn down. You were never on that box. Good."
  },
  {
    "situation": "clean_exit",
    "text": "Clean. Nothing left ringing, nothing flagged. That's how you keep doing this past thirty. Stand down."
  },
  {
    "situation": "clean_exit",
    "text": "No alarms, no residue, no story for their SOC to tell Monday. Textbook. Wipe your hands and walk."
  },
  {
    "situation": "hot_exit",
    "text": "You're out, but you left it warm. Somebody's going to notice that session next sweep. Move addresses before they correlate it back."
  },
  {
    "situation": "hot_exit",
    "text": "Got what we needed, but that exit was loud. Don't go home in a straight line. Burn the staging hop and lay low."
  },
  {
    "situation": "hot_exit",
    "text": "Pulled it, but the timestamps will scream once they pull logs. We've got hours, not days. Cool off and stay dark."
  },
  {
    "situation": "burned",
    "text": "They made you. Your handle's poison now, the box is locked, and there's a ticket with your fingerprints on it. Kill the link and don't reuse it."
  },
  {
    "situation": "burned",
    "text": "Burned. They saw the door swing. Drop everything tied to this op, rotate every identity, assume the channel's read. Move."
  },
  {
    "situation": "burned",
    "text": "That's a blown approach. Their side's awake and looking. No heroics — pull the plug, scatter the trail, we regroup cold."
  },
  {
    "situation": "no_route_warning",
    "text": "You're reaching straight at it with nothing in between. One hop, one log line, and it's a map to your door. Build a path first."
  },
  {
    "situation": "no_route_warning",
    "text": "No relays, no cutouts. That's not bold, that's naked. Lay down some distance before you touch anything that bites."
  },
  {
    "situation": "no_route_warning",
    "text": "Direct line to the target means a direct line back. Stand up a chain of hops or don't knock at all."
  },
  {
    "situation": "watched_entity_warning",
    "text": "That name's flagged. Somebody upstream is already watching it — vendor, fed, rival, doesn't matter. Touch it and you join the list."
  },
  {
    "situation": "watched_entity_warning",
    "text": "Heads up — that asset's under a microscope. Traffic to it gets reviewed by people who do this for a living. Slow down."
  },
  {
    "situation": "watched_entity_warning",
    "text": "That target's wired with eyes. Tripwires, honeyed accounts, the works. Assume every move you make there is being scored."
  },
  {
    "situation": "high_attribution",
    "text": "You're shedding signature everywhere — reused handles, sloppy timing, patterns a junior analyst could braid into a name. Tighten it."
  },
  {
    "situation": "high_attribution",
    "text": "Too much of you in this. Your tradecraft's got a fingerprint and you're pressing it on every surface. Vary it or get traced."
  },
  {
    "situation": "high_attribution",
    "text": "Attribution's climbing. Keep this up and someone draws a straight line from the work to a face. Mix your methods, kill the tells."
  },
  {
    "situation": "idle_nudge",
    "text": "You still on the line? Open sessions rot. Either work it or close it — sitting parked is just free evidence for them."
  },
  {
    "situation": "idle_nudge",
    "text": "Clock's running and you're not. Every minute idle is a minute their side might glance at the right log. Move or fold."
  },
  {
    "situation": "idle_nudge",
    "text": "You've gone quiet. I don't like quiet. Make a call — push forward or tear it down. Limbo gets people caught."
  },
  {
    "situation": "mission_accepted",
    "text": "Job's yours. Scope's tight, window's narrow. Get in, take only what's on the sheet, leave the rest untouched. Don't improvise."
  },
  {
    "situation": "mission_accepted",
    "text": "Contract's live. I've fed you the brief — read it twice. Stick to the objective and we both get paid clean."
  },
  {
    "situation": "mission_accepted",
    "text": "You're on. Targets, timing, exit — it's all in the packet. Patience over flash. Call me if it goes sideways."
  },
  {
    "situation": "mission_complete",
    "text": "Objective met, ground covered, no loose threads. That's a paid job and a closed door. Good work — now disappear."
  },
  {
    "situation": "mission_complete",
    "text": "Done and clean. Payload's where it needs to be, you're nowhere near it. This is what the trade looks like done right."
  },
  {
    "situation": "mission_complete",
    "text": "Mission's closed. You hit the mark and left no echo. Take the win, kill the channel, we never spoke."
  }
];
