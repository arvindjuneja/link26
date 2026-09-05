// The first-shift case pack. Three verified archetypes (encoded PowerShell, auth
// brute-force, DNS C2 — the only ones soc-tier1-research.md surfaced with verified
// procedural detail), each appearing as a malicious AND an authorized/false-positive
// variant so the player learns the thesis: the SAME detection resolves to a
// different verdict depending on context. The queue tilts toward FP/benign (4 of 7)
// — real triage is mostly not-a-threat, and the skill is not rubber-stamping it.
//
// GUARDRAIL: every "log line" here is plausible-but-fictional and describes a
// PATTERN, never a working command/payload. We teach the analyst's read, not an
// attack. MITRE IDs are codex-lookup labels only.

import type { DataSource, SocCase } from "@/app/lib/soc/types";
import { RED_RUNS, caseFromRedRun } from "@/app/lib/soc/handoff";

// A shared catalogue so a given source reads the same across cases (the UI feels
// like one console). Each carries the QUESTION it answers — the log-to-question model.
const S: Record<string, DataSource> = {
  edrTree: {
    id: "edr-process-tree",
    label: "EDR — process tree & lineage",
    question: "what spawned this, and what did it do after?",
    cost: 10,
  },
  decode: {
    id: "decoded-command",
    label: "Decode the command",
    question: "what does the encoded blob actually say?",
    cost: 10,
  },
  authLogs: {
    id: "auth-logs",
    label: "Auth logs (4624 / 4625 / 4672)",
    question: "what's the logon pattern, and from where?",
    cost: 8,
  },
  dnsLogs: {
    id: "dns-logs",
    label: "DNS query logs",
    question: "what's the timing, entropy and resolution of the queries?",
    cost: 8,
  },
  geoVpn: {
    id: "geo-vpn",
    label: "VPN / geo-IP",
    question: "where did this originate, and does it fit the user?",
    cost: 6,
  },
  privEvents: {
    id: "privilege-events",
    label: "Privilege assignment (4672)",
    question: "were special privileges granted, and to whom?",
    cost: 6,
  },
  netProxy: {
    id: "network-proxy",
    label: "Firewall / proxy logs",
    question: "did it call out, and to what?",
    cost: 8,
  },
  threatIntel: {
    id: "threat-intel",
    label: "Threat-intel enrichment",
    question: "is this indicator known-bad?",
    cost: 5,
  },
  changeTickets: {
    id: "change-tickets",
    label: "Change tickets / asset register",
    question: "was this activity authorized or scheduled?",
    cost: 6,
  },
  helpdesk: {
    id: "it-helpdesk",
    label: "IT helpdesk tickets",
    question: "did the user report anything?",
    cost: 5,
  },
  hrDirectory: {
    id: "hr-directory",
    label: "HR directory / calendar",
    question: "should this account even be active right now?",
    cost: 5,
  },
  // ── round-2 sources (docs/research/soc-tier1-cases-round2.md) ──
  emailAuth: {
    id: "email-auth",
    label: "Email authentication (SPF/DKIM/DMARC)",
    question: "did it authenticate and align with the From domain?",
    cost: 6,
  },
  senderRep: {
    id: "sender-reputation",
    label: "Sender & URL reputation",
    question: "is the sender domain or link known-bad / a look-alike?",
    cost: 5,
  },
  awareness: {
    id: "awareness-campaign",
    label: "Security-awareness campaign register",
    question: "is this part of an authorized phishing simulation?",
    cost: 5,
  },
  urlDetonation: {
    id: "url-detonation",
    label: "URL / attachment detonation",
    question: "what does the link or attachment actually do?",
    cost: 10,
  },
  signinLogs: {
    id: "signin-logs",
    label: "Entra sign-in logs",
    question: "where from, which device, which app, what user-agent?",
    cost: 8,
  },
  entraRisk: {
    id: "entra-risk",
    label: "Entra ID Protection risk detections",
    question: "which risk detection fired, and what's the user risk?",
    cost: 6,
  },
  namedLocations: {
    id: "named-locations",
    label: "Named locations / VPN register",
    question: "is this IP a corporate VPN or known duty location?",
    cost: 5,
  },
  mfaLogs: {
    id: "mfa-logs",
    label: "MFA / auth-method logs",
    question: "did the user initiate or deny the prompts?",
    cost: 6,
  },
  alertEvidence: {
    id: "alert-evidence",
    label: "EDR AlertEvidence (Advanced Hunting)",
    question: "what file/device, and the detection + quarantine state?",
    cost: 8,
  },
  dlpHits: {
    id: "dlp-hits",
    label: "DLP policy hits",
    question: "what data matched which policy, and how much?",
    cost: 6,
  },
  cloudActivity: {
    id: "cloud-activity",
    label: "Cloud-app / egress activity",
    question: "what process sent how much, and to where?",
    cost: 8,
  },
  // ── round-3 sources (docs/research/soc-tier1-cases-round3.md) ──
  lockout: {
    id: "lockout-events",
    label: "Account-lockout events (4740)",
    question: "which account locked, how often — and is the caller machine even populated?",
    cost: 6,
  },
  authFail: {
    id: "auth-failures",
    label: "Kerberos / NTLM failures (4771 / 4776)",
    question: "where are the bad passwords actually coming from?",
    cost: 8,
  },
  // ── round-4 sources (docs/research/soc-tier1-cases-round4.md) ──
  insiderRisk: {
    id: "insider-risk",
    label: "Insider-risk score & history",
    question: "how risky is this user, and does it correlate with employment status?",
    cost: 6,
  },
  roleScope: {
    id: "role-scope",
    label: "Role & entitlement context",
    question: "is this data in scope for the user's job?",
    cost: 5,
  },
};

const HAND_AUTHORED_CASES: SocCase[] = [
  // ── A1 · Encoded PowerShell — MALICIOUS (the thesis case) ──────────────────
  {
    id: "soc-ps-cradle",
    archetype: "encoded-powershell",
    alertTitle: "Encoded PowerShell on a finance workstation",
    detectionRule: "EDR · powershell.exe launched with -EncodedCommand",
    toolSeverity: "High",
    trigger: "powershell.exe spawned with -EncodedCommand on FIN-WS-04 at 02:14 local — off-hours.",
    asset: "FIN-WS-04 · user jdoe (Finance)",
    sources: [S.edrTree, S.decode, S.netProxy, S.changeTickets, S.threatIntel, S.helpdesk],
    keySourceIds: ["edr-process-tree", "decoded-command", "change-tickets"],
    evidence: [
      {
        id: "a1-tree",
        sourceId: "edr-process-tree",
        label: "Parent is WINWORD.EXE",
        detail: "Lineage: WINWORD.EXE → cmd.exe → powershell.exe. A document spawned a shell — not how IT runs scripts.",
        weight: "decisive",
      },
      {
        id: "a1-decode",
        sourceId: "decoded-command",
        label: "Decodes to a download-cradle",
        detail: "Decoded blob is an in-memory downloader: pull a follow-on script from a remote host and run it without writing to disk.",
        weight: "decisive",
      },
      {
        id: "a1-net",
        sourceId: "network-proxy",
        label: "Immediate outbound to a fresh domain",
        detail: "Within 2s of execution: outbound HTTPS to a domain in no proxy category, first-seen org-wide.",
        weight: "supporting",
      },
      {
        id: "a1-ticket",
        sourceId: "change-tickets",
        label: "No change ticket",
        detail: "No maintenance window, no change record for FIN-WS-04. jdoe is Finance, not IT — no reason to run admin scripts.",
        weight: "decisive",
      },
      {
        id: "a1-intel",
        sourceId: "threat-intel",
        label: "Domain registered 3 days ago",
        detail: "The callout domain was registered 72h ago; one feed already tags it suspicious.",
        weight: "supporting",
      },
      {
        id: "a1-help",
        sourceId: "it-helpdesk",
        label: "Phishy invoice email just before",
        detail: "jdoe received an 'overdue invoice' attachment 9 minutes before execution. Plausible initial-access vector.",
        weight: "supporting",
      },
    ],
    truth: "true-positive",
    correctDisposition: "escalate-ir-isolate",
    acceptableDispositions: ["escalate-tier2"],
    why:
      "Encoding was never the threat — the LINEAGE and BEHAVIOUR are. A Word document spawned PowerShell, the decoded payload is an in-memory download-cradle, there's a live outbound to a 3-day-old domain, and no change ticket on a finance host off-hours. That's an active initial-access chain: isolate the host and escalate to IR.",
    learn: {
      concept:
        "Encoded ≠ malicious. Decode it, then read the parent process and what it did. Office → PowerShell → outbound is a classic initial-access chain; a sanctioned tool with a change ticket is not.",
      mitre: { id: "T1059.001", name: "Command and Scripting Interpreter: PowerShell" },
      pointer: "MITRE ATT&CK T1059.001 · LetsDefend 'Detecting Malicious PowerShell'",
    },
  },

  // ── B2 · Auth burst→success — FALSE POSITIVE (looks like B1, isn't) ────────
  {
    id: "soc-auth-reset",
    archetype: "auth-bruteforce",
    alertTitle: "Failed-logon burst then success — user rkhan",
    detectionRule: "SIEM · ≥10× 4625 then a 4624 from the same source within 5m",
    toolSeverity: "Medium",
    trigger: "12× failed logons (4625) then a success (4624) for rkhan at 09:05, Monday morning.",
    asset: "account rkhan · workstation MKT-WS-03",
    sources: [S.authLogs, S.geoVpn, S.helpdesk, S.privEvents, S.threatIntel, S.changeTickets],
    keySourceIds: ["auth-logs", "it-helpdesk"],
    evidence: [
      {
        id: "b2-auth",
        sourceId: "auth-logs",
        label: "All from rkhan's own workstation",
        detail: "Every 4625 originates from MKT-WS-03 (corporate subnet), clustered in 90s, logon type 2 (interactive at the keyboard). Then a clean 4624.",
        weight: "decisive",
      },
      {
        id: "b2-help",
        sourceId: "it-helpdesk",
        label: "Helpdesk ticket: forgot password",
        detail: "Ticket from rkhan at 09:03: 'forgot my password after the weekend forced reset.' Two minutes before the success.",
        weight: "decisive",
      },
      {
        id: "b2-geo",
        sourceId: "geo-vpn",
        label: "No remote access",
        detail: "Source is the office LAN; rkhan's normal location. No VPN, no foreign IP, no impossible travel.",
        weight: "supporting",
      },
      {
        id: "b2-priv",
        sourceId: "privilege-events",
        label: "No privilege events",
        detail: "No 4672. rkhan is a standard user; nothing elevated.",
        weight: "neutral",
      },
      {
        id: "b2-intel",
        sourceId: "threat-intel",
        label: "Internal IP — nothing to enrich",
        detail: "Source is an RFC1918 corporate address; no external reputation to look up.",
        weight: "neutral",
      },
      {
        id: "b2-noise",
        sourceId: "threat-intel",
        label: "Old lookalike-domain report",
        detail: "A months-old phishing report mentions a domain resembling the company's. It pattern-matches if you squint, but it has nothing to do with this logon — a red herring.",
        weight: "noise",
      },
      {
        id: "b2-ticket",
        sourceId: "change-tickets",
        label: "Reset — not a grant",
        detail: "Org-wide weekend password reset was scheduled (CHG-2270) — it explains the failures; it authorizes nothing.",
        weight: "supporting",
      },
    ],
    truth: "false-positive",
    correctDisposition: "close-false-positive",
    why:
      "Same shape as a password-guessing hit — failures then a success — but the SOURCE and CONTEXT flip the verdict. The failures are fat-fingered attempts from the user's OWN keyboard right after a scheduled weekend reset, with a helpdesk ticket to match, then a normal interactive logon. The rule matched the shape, but nobody was guessing — what it hunts for never happened. Close FP.",
    learn: {
      concept:
        "The 4625-burst → 4624 pattern is only a threat when the source/time/account don't fit the user. Always check WHERE it came from before escalating — same detection, opposite verdict.",
      mitre: { id: "T1110", name: "Brute Force" },
      pointer: "Windows Security event-log analysis · tune the rule to exclude same-host interactive failures",
    },
  },

  // ── A2 · Encoded PowerShell — BENIGN TRUE POSITIVE (the subtle third call) ──
  {
    id: "soc-ps-patch",
    archetype: "encoded-powershell",
    alertTitle: "Encoded PowerShell on a patch server",
    detectionRule: "EDR · powershell.exe launched with -EncodedCommand",
    toolSeverity: "High",
    trigger: "powershell.exe -EncodedCommand on SRV-PATCH-02 at 03:00 — inside the nightly maintenance window.",
    asset: "SRV-PATCH-02 · service account svc-sccm",
    sources: [S.edrTree, S.decode, S.changeTickets, S.netProxy, S.threatIntel, S.hrDirectory],
    keySourceIds: ["edr-process-tree", "change-tickets"],
    evidence: [
      {
        id: "a2-tree",
        sourceId: "edr-process-tree",
        label: "Parent is the SCCM agent",
        detail: "Lineage: ccmexec.exe (SCCM/patch-management agent) → powershell.exe, under service account svc-sccm. A known IT automation tool, not a document.",
        weight: "decisive",
      },
      {
        id: "a2-decode",
        sourceId: "decoded-command",
        label: "Decodes to an inventory script",
        detail: "Decoded blob enumerates installed updates and reports compliance — a routine patch/inventory task.",
        weight: "supporting",
      },
      {
        id: "a2-ticket",
        sourceId: "change-tickets",
        label: "Approved change CHG-2291",
        detail: "Standing change CHG-2291 authorizes automated nightly patching on SRV-PATCH-02 in this exact window.",
        weight: "decisive",
      },
      {
        id: "a2-net",
        sourceId: "network-proxy",
        label: "Outbound to internal WSUS only",
        detail: "Connections go to the internal update server (known-good); no external callouts.",
        weight: "supporting",
      },
      {
        id: "a2-intel",
        sourceId: "threat-intel",
        label: "Nothing flagged",
        detail: "No external indicators; all destinations internal and reputable.",
        weight: "neutral",
      },
      {
        id: "a2-hr",
        sourceId: "hr-directory",
        label: "Service account, not a person",
        detail: "svc-sccm is a non-interactive service account scoped to patch management.",
        weight: "neutral",
      },
    ],
    truth: "benign-true-positive",
    correctDisposition: "close-benign",
    why:
      "The detection was RIGHT — that really is encoded PowerShell — but the parent is the patch-management agent and a standing change ticket authorizes it. That's a Benign True Positive, not a False Positive: the rule didn't misfire, the activity was simply sanctioned. Closing it as 'FP' would be wrong reasoning (and would tempt someone to suppress the rule that correctly catches the malicious version in A1).",
    learn: {
      concept:
        "Benign True Positive = correct detection of AUTHORIZED activity. Separate it from a False Positive — there, the flagged behaviour never happened at all, so no ticket could sanction it. Don't suppress a rule just because today's hit was sanctioned.",
      mitre: { id: "T1059.001", name: "Command and Scripting Interpreter: PowerShell" },
      pointer: "Microsoft Defender alert classification · TP vs FP vs Benign-TP",
    },
  },

  // ── C1 · DNS beaconing — MALICIOUS ─────────────────────────────────────────
  {
    id: "soc-dns-beacon",
    archetype: "dns-c2",
    alertTitle: "Periodic DNS to high-entropy domains",
    detectionRule: "SIEM · regular-interval DNS to algorithmically-generated domains (DGA heuristic)",
    toolSeverity: "High",
    trigger: "ENG-LAP-09 queries a rotating set of long, random-looking domains every ~60s, around the clock.",
    asset: "ENG-LAP-09 · user mlopez (Engineering)",
    sources: [S.dnsLogs, S.edrTree, S.netProxy, S.threatIntel, S.changeTickets],
    keySourceIds: ["dns-logs", "edr-process-tree"],
    evidence: [
      {
        id: "c1-dns",
        sourceId: "dns-logs",
        label: "Fixed-interval, high-entropy, NXDOMAIN bursts",
        detail: "Queries fire on a near-exact 60s cadence; labels are long high-entropy strings across many unrelated registrations; most return NXDOMAIN with the occasional resolve; rare TLDs (.top/.xyz).",
        weight: "decisive",
      },
      {
        id: "c1-tree",
        sourceId: "edr-process-tree",
        label: "A temp-path binary, not a browser",
        detail: "The queries come from an unsigned binary running out of %TEMP% — not the system resolver, not a browser.",
        weight: "decisive",
      },
      {
        id: "c1-net",
        sourceId: "network-proxy",
        label: "Small, regular, equal-sized POSTs",
        detail: "After each resolve: a small fixed-size outbound POST. The hallmark of a beacon check-in, not human browsing.",
        weight: "supporting",
      },
      {
        id: "c1-intel",
        sourceId: "threat-intel",
        label: "One domain on a C2 feed",
        detail: "Of the resolving domains, one matches a tracked C2 infrastructure feed.",
        weight: "supporting",
      },
      {
        id: "c1-ticket",
        sourceId: "change-tickets",
        label: "No authorized tooling",
        detail: "No change/asset record for this binary; software inventory shows it isn't an approved application.",
        weight: "supporting",
      },
    ],
    truth: "true-positive",
    correctDisposition: "escalate-ir-isolate",
    acceptableDispositions: ["escalate-tier2"],
    why:
      "Fixed-interval queries (beaconing), high-entropy domains across many registrations (DGA), NXDOMAIN bursts, rare TLDs — and crucially the queries come from an unsigned temp-path binary with small regular outbound POSTs. That's command-and-control, not browsing. Isolate the host and escalate.",
    learn: {
      concept:
        "DNS C2 tells: regular timing (beaconing), long high-entropy domains (DGA), NXDOMAIN bursts, rare TLDs — but always confirm the PROCESS making the queries isn't a browser or the resolver. Behaviour, then attribution.",
      mitre: { id: "T1071.004", name: "Application Layer Protocol: DNS" },
      pointer: "MITRE ATT&CK T1071.004 · DNS log analysis, entropy/DGA detection",
    },
  },

  // ── B1 · Auth burst→success — MALICIOUS (account compromise) ───────────────
  {
    id: "soc-auth-bruteforce",
    archetype: "auth-bruteforce",
    alertTitle: "Failed-logon burst then success — user msmith",
    detectionRule: "SIEM · ≥20× 4625 then a 4624 from the same source within 5m",
    toolSeverity: "High",
    trigger: "37× failed logons (4625) then a success (4624) for msmith from a foreign ASN at 03:40.",
    asset: "account msmith · via VPN-GW",
    sources: [S.authLogs, S.geoVpn, S.privEvents, S.threatIntel, S.changeTickets, S.hrDirectory],
    keySourceIds: ["auth-logs", "geo-vpn", "change-tickets"],
    evidence: [
      {
        id: "b1-auth",
        sourceId: "auth-logs",
        label: "Brute-force burst then a hit",
        detail: "37× 4625 against this one account from a single external IP in 4 minutes — guessing in depth — then a 4624 success, logon type 3 (network) over the VPN.",
        weight: "decisive",
      },
      {
        id: "b1-geo",
        sourceId: "geo-vpn",
        label: "Impossible travel",
        detail: "Source IP geolocates to a country msmith has never used; the success lands minutes apart from msmith's last normal logon in the home country — too far to travel between the two. Impossible travel.",
        weight: "decisive",
      },
      {
        id: "b1-priv",
        sourceId: "privilege-events",
        label: "4672 right after success",
        detail: "Minutes after the logon, a 4672 (special privileges assigned) fires for msmith — an account that shouldn't be elevating.",
        weight: "supporting",
      },
      {
        id: "b1-intel",
        sourceId: "threat-intel",
        label: "Source IP on a brute-force list",
        detail: "The external IP appears on a known brute-force / password-guessing feed.",
        weight: "supporting",
      },
      {
        id: "b1-ticket",
        sourceId: "change-tickets",
        label: "No authorized testing",
        detail: "No pentest authorization or RoE covering credential testing against VPN-GW this window.",
        weight: "decisive",
      },
      {
        id: "b1-hr",
        sourceId: "hr-directory",
        label: "User is on PTO",
        detail: "HR calendar shows msmith on leave all week — shouldn't be logging in at all.",
        weight: "supporting",
      },
    ],
    truth: "true-positive",
    correctDisposition: "escalate-ir-isolate",
    acceptableDispositions: ["escalate-tier2"],
    why:
      "A 4625 burst → 4624 success from a foreign IP, impossible travel (two logons too far apart to be one person), a 4672 elevation right after, source IP on a brute-force feed, no authorized-testing ticket, and the user is on PTO. That's a confirmed account compromise — disable the account / isolate the session and escalate to IR now.",
    learn: {
      concept:
        "4625 = failed logon (a deep burst against one account = brute-force/password-guessing), 4624 = success, 4672 = special privileges. The signature is burst→success from an anomalous source/time. Correlate source IP / time / account — and check whether the user should even be active.",
      mitre: { id: "T1110.001", name: "Brute Force: Password Guessing" },
      pointer: "MITRE ATT&CK T1110.001 · Splunk/Sentinel auth detections",
    },
  },

  // ── C2 · DNS DGA heuristic — FALSE POSITIVE (CDN noise) ─────────────────────
  {
    id: "soc-dns-cdn",
    archetype: "dns-c2",
    alertTitle: "DGA heuristic fired on marketing laptop",
    detectionRule: "SIEM · regular-interval DNS to algorithmically-generated domains (DGA heuristic)",
    toolSeverity: "Medium",
    trigger: "MKT-WS-12 makes frequent queries to long, random-looking subdomains.",
    asset: "MKT-WS-12 · user dpark (Marketing)",
    sources: [S.dnsLogs, S.edrTree, S.threatIntel, S.netProxy, S.changeTickets],
    keySourceIds: ["dns-logs", "edr-process-tree"],
    evidence: [
      {
        id: "c2-dns",
        sourceId: "dns-logs",
        label: "Subdomains of ONE reputable CDN",
        detail: "The random-looking labels are all subdomains of a single well-known CDN / anti-bot parent domain. Every query resolves cleanly — no NXDOMAIN bursts — and timing is bursty with user activity, not a fixed beacon.",
        weight: "decisive",
      },
      {
        id: "c2-tree",
        sourceId: "edr-process-tree",
        label: "It's the browser",
        detail: "The queries come from chrome.exe and a known analytics SDK — normal web components, not an unknown binary.",
        weight: "decisive",
      },
      {
        id: "c2-intel",
        sourceId: "threat-intel",
        label: "Parent domain is clean",
        detail: "The CDN parent domain has a long history and clean reputation across feeds.",
        weight: "supporting",
      },
      {
        id: "c2-noise",
        sourceId: "threat-intel",
        label: "One historical IP overlap",
        detail: "Months ago, one of the CDN's many shared IPs also hosted something later flagged. That's shared-hosting coincidence, not this host's traffic — tempting, irrelevant.",
        weight: "noise",
      },
      {
        id: "c2-net",
        sourceId: "network-proxy",
        label: "Ordinary web traffic",
        detail: "Variable-sized HTTPS tied to page loads; no fixed-size periodic check-ins.",
        weight: "supporting",
      },
      {
        id: "c2-ticket",
        sourceId: "change-tickets",
        label: "n/a",
        detail: "No change relevant; this is end-user browsing.",
        weight: "neutral",
      },
    ],
    truth: "false-positive",
    correctDisposition: "close-false-positive",
    why:
      "The 'high-entropy domains' are CDN / anti-bot subdomains under one reputable parent, resolving cleanly, queried irregularly by a browser. That's ordinary modern web traffic — the DGA heuristic over-fired. The discriminators against C1: one parent vs many registrations, clean resolution vs NXDOMAIN bursts, browser vs temp-path binary, activity-driven vs fixed interval.",
    learn: {
      concept:
        "DGA heuristics over-fire on CDNs and anti-bot subdomains. Discriminate: one parent domain vs many registrations, clean resolution vs NXDOMAIN bursts, browser vs unknown process, activity-driven vs fixed-interval timing. Then tune the rule.",
      mitre: { id: "T1071.004", name: "Application Layer Protocol: DNS" },
      pointer: "Entropy/DGA detection · allow-list known CDN parents to cut the noise",
    },
  },

  // ── B3 · Auth spray — BENIGN TRUE POSITIVE (the same-board, two-seats bridge) ─
  {
    id: "soc-auth-pentest",
    archetype: "auth-bruteforce",
    alertTitle: "Credential spray across many accounts",
    detectionRule: "SIEM · 4625 across ≥15 accounts from one source, with some 4624 successes",
    toolSeverity: "Critical",
    trigger: "A spray across 23 accounts then 3 successes, all from one internal host, 14:00 on a Wednesday.",
    asset: "multiple accounts · source host PENTEST-01",
    sources: [S.authLogs, S.changeTickets, S.geoVpn, S.threatIntel, S.hrDirectory],
    keySourceIds: ["auth-logs", "change-tickets"],
    evidence: [
      {
        id: "b3-auth",
        sourceId: "auth-logs",
        label: "Textbook spray — and it worked",
        detail: "One internal source, 23 accounts, one password each, then 3 successes. This IS attack behaviour — the detection is correct.",
        weight: "supporting",
      },
      {
        id: "b3-ticket",
        sourceId: "change-tickets",
        label: "Approved pentest CHG-2310",
        detail: "Authorization CHG-2310 / signed RoE covers credential testing from PENTEST-01 this week. Deconfliction note names the testing team.",
        weight: "decisive",
      },
      {
        id: "b3-geo",
        sourceId: "geo-vpn",
        label: "Internal source",
        detail: "PENTEST-01 is an internal, inventoried host on the security team's segment.",
        weight: "supporting",
      },
      {
        id: "b3-intel",
        sourceId: "threat-intel",
        label: "Nothing external",
        detail: "Internal source; no external reputation in play.",
        weight: "neutral",
      },
      {
        id: "b3-hr",
        sourceId: "hr-directory",
        label: "Testing window confirmed",
        detail: "Security calendar shows an authorized engagement running this week.",
        weight: "supporting",
      },
    ],
    truth: "benign-true-positive",
    correctDisposition: "close-benign",
    why:
      "This looks exactly like an attack because it IS attack behaviour — but there's a signed pentest authorization covering this host and window. That's the cleanest Benign True Positive there is: a correct detection of AUTHORIZED activity. (It's also the bridge between the two seats — a red-team run, seen from the blue chair, is a Benign-TP.) Escalating it wastes IR; isolating PENTEST-01 would blow up a sanctioned engagement. Confirm the RoE, note it on the ticket, close benign.",
    learn: {
      concept:
        "Authorized attack activity (a sanctioned pentest) is a Benign True Positive, not a False Positive and not something to escalate. Check for a deconfliction / RoE record before you act — and document it so the next analyst doesn't re-fire on the same engagement.",
      mitre: { id: "T1110.003", name: "Brute Force: Password Spraying" },
      pointer: "Purple-team deconfliction · 'is this us or someone else?'",
    },
  },

  // ════ ROUND 2 — phishing / identity / EDR / exfil ════════════════════════════
  // Grounded in docs/research/soc-tier1-cases-round2.md. Same "same detection,
  // opposite verdict" thesis: each archetype ships a malicious AND an
  // authorized/false-positive variant.

  // ── Phishing — MALICIOUS (credential harvest) ──────────────────────────────
  {
    id: "soc-phish-harvest",
    archetype: "phishing",
    alertTitle: "Reported phishing — credential harvest impersonating IT",
    detectionRule: "Defender for Office 365 · user-reported + URL re-scored suspicious",
    toolSeverity: "High",
    trigger: "A user forwarded an 'IT: your mailbox is over quota — verify now' email; the gateway re-scored the link as suspicious.",
    asset: "user pdavis (Sales) · sender it-support@m1crosoft-helpdesk.co",
    sources: [S.emailAuth, S.senderRep, S.urlDetonation, S.awareness, S.threatIntel, S.signinLogs],
    keySourceIds: ["email-auth", "sender-reputation", "url-detonation"],
    evidence: [
      {
        id: "ph1-auth",
        sourceId: "email-auth",
        label: "Doesn't align with the brand it imitates",
        detail: "SPF fail, DKIM none, DMARC none/fail — the visible From impersonates a trusted brand but aligns with nothing that authenticated it. (Corroborates the look-alike; a look-alike can pass its OWN auth, so this isn't the verdict by itself.)",
        weight: "supporting",
      },
      {
        id: "ph1-sender",
        sourceId: "sender-reputation",
        label: "Week-old look-alike domain",
        detail: "Sender domain registered 6 days ago — a look-alike of the brand it imitates, not the corporate mail domain.",
        weight: "decisive",
      },
      {
        id: "ph1-url",
        sourceId: "url-detonation",
        label: "Credential-harvesting landing page",
        detail: "The link resolves to a fake corporate-login page — a form that captures whatever's typed and sends it onward. A harvester, not a real portal.",
        weight: "decisive",
      },
      {
        id: "ph1-intel",
        sourceId: "threat-intel",
        label: "Landing domain on phishing feeds",
        detail: "The harvester domain appears on two phishing-URL feeds.",
        weight: "supporting",
      },
      {
        id: "ph1-signin",
        sourceId: "signin-logs",
        label: "No creds entered (yet)",
        detail: "pdavis reported it before clicking; no anomalous sign-in for the account. Caught early.",
        weight: "supporting",
      },
      {
        id: "ph1-noise",
        sourceId: "awareness-campaign",
        label: "There IS an awareness campaign…",
        detail: "A security-awareness phishing simulation runs this quarter — but its register shows no send to pdavis and a different sending platform. Tempting, but not this.",
        weight: "noise",
      },
    ],
    truth: "true-positive",
    correctDisposition: "escalate-tier2",
    why:
      "Nothing authenticated the message (SPF/DKIM/DMARC all fail, From unaligned), the sender is a week-old look-alike, and the link is a live credential-harvesting page on two phishing feeds. It is NOT the sanctioned simulation — that campaign never targeted this user and uses a different platform. Real phish, no creds entered yet: escalate, block the sender/URL, and hunt for anyone who did click.",
    learn: {
      concept:
        "Authentication answers 'did the From domain authenticate ITSELF' — not 'is this safe'. The decisive tells are the look-alike domain + the credential-harvest page + that it's in no campaign register; SPF/DKIM authenticate and DMARC governs disposition + From-alignment, but a look-alike can pass its own auth. (The visible From check is DMARC alignment, not raw SPF/DKIM.)",
      mitre: { id: "T1566", name: "Phishing" },
      pointer: "MITRE ATT&CK T1566 · LetsDefend 'Phishing Email Analysis'",
    },
  },

  // ── Identity — FALSE POSITIVE (impossible travel = corporate VPN) ──────────
  {
    id: "soc-id-vpn",
    archetype: "impossible-travel",
    alertTitle: "Atypical travel — sign-in from two countries",
    detectionRule: "Entra ID Protection · risky sign-in (unlikelyTravel)",
    toolSeverity: "Medium",
    trigger: "rwong signed in from the office, then from a neighbouring country the account has never used before — flagged as atypical travel.",
    asset: "account rwong (Engineering)",
    sources: [S.entraRisk, S.signinLogs, S.namedLocations, S.threatIntel, S.hrDirectory],
    keySourceIds: ["signin-logs", "named-locations"],
    evidence: [
      {
        id: "id1-named",
        sourceId: "named-locations",
        label: "It's the corporate VPN egress",
        detail: "The 'foreign' IP belongs to the company VPN egress range — already used by dozens of staff, just never added to Named locations.",
        weight: "decisive",
      },
      {
        id: "id1-signin",
        sourceId: "signin-logs",
        label: "Same device, app, user-agent",
        detail: "Both sign-ins are from rwong's registered, compliant laptop, the normal client app and the usual user-agent. Only the egress IP differs.",
        weight: "decisive",
      },
      {
        id: "id1-risk",
        sourceId: "entra-risk",
        label: "Atypical travel, in learning window",
        detail: "Detection is unlikelyTravel (Entra-native), risk Medium; the account is still inside its 14-day / 10-login learning window where these FPs are expected.",
        weight: "supporting",
      },
      {
        id: "id1-intel",
        sourceId: "threat-intel",
        label: "VPN IP is clean",
        detail: "The egress IP has clean reputation.",
        weight: "neutral",
      },
      {
        id: "id1-noise",
        sourceId: "hr-directory",
        label: "Upcoming trip abroad",
        detail: "rwong has an approved trip abroad next month — unrelated to today's sign-in.",
        weight: "noise",
      },
    ],
    truth: "false-positive",
    correctDisposition: "close-false-positive",
    why:
      "Same shape as a compromise, but the 'impossible' location is the corporate VPN egress: a registered, compliant device, normal app and user-agent — only the IP differs — and the account is still in its learning window. Confirm the sign-in safe and add the VPN range to Named locations so it stops firing. The detection misfired; close FP.",
    learn: {
      concept:
        "Atypical/impossible travel over-fires on VPNs and during the 14-day/10-login learning period. Validate the sign-in fields — registered device, app, location, IP, user-agent — before you call it; a corporate VPN egress → confirm safe + add to Named locations.",
      mitre: { id: "T1078.004", name: "Valid Accounts: Cloud Accounts" },
      pointer: "Entra ID Protection investigate-risk · Named locations",
    },
  },

  // ── EDR — BENIGN TRUE POSITIVE (authorized red-team tool) ──────────────────
  {
    id: "soc-edr-test",
    archetype: "edr-malware",
    alertTitle: "EDR: offensive-security tool detected",
    detectionRule: "Defender for Endpoint · 'hacktool' / behavioral detection",
    toolSeverity: "High",
    trigger: "Defender flagged a known offensive-security tool running on SEC-LAB-02.",
    asset: "SEC-LAB-02 · security-team segment",
    sources: [S.changeTickets, S.alertEvidence, S.edrTree, S.threatIntel, S.hrDirectory],
    keySourceIds: ["change-tickets", "alert-evidence"],
    evidence: [
      {
        id: "ed2-ticket",
        sourceId: "change-tickets",
        label: "Approved red-team engagement",
        detail: "Change CHG-3120 authorizes a red-team engagement on SEC-LAB-02 this week; the tool and host are named in the signed RoE / deconfliction note.",
        weight: "decisive",
      },
      {
        id: "ed2-evidence",
        sourceId: "alert-evidence",
        label: "Security-team lab box",
        detail: "AlertEvidence: the binary is a well-known security-testing tool, on the security team's lab host SEC-LAB-02, run by a security-team account.",
        weight: "decisive",
      },
      {
        id: "ed2-tree",
        sourceId: "edr-process-tree",
        label: "Launched interactively by the tester",
        detail: "Lineage shows an interactive launch by the tester — not spawned from a document or a temp-path dropper.",
        weight: "supporting",
      },
      {
        id: "ed2-intel",
        sourceId: "threat-intel",
        label: "Dual-use, not malware-by-author",
        detail: "The hash is 'known', but it's a legitimate dual-use offensive-security utility, not malware.",
        weight: "neutral",
      },
      {
        id: "ed2-hr",
        sourceId: "hr-directory",
        label: "Security-team account",
        detail: "The account belongs to the security team.",
        weight: "neutral",
      },
    ],
    truth: "benign-true-positive",
    correctDisposition: "close-benign",
    why:
      "The detection is correct — that really is an offensive-security tool — but it's running inside an authorized red-team engagement on the security team's own lab box, named in the change ticket and RoE. That's Defender's 'Informational, expected activity' / Benign-TP: classify benign and suppress for the engagement window; don't escalate (you'd burn IR and blow the test), and don't permanently whitelist the rule. Isolating SEC-LAB-02 would break a sanctioned exercise. (Your own red-seat run, seen from the blue chair.)",
    learn: {
      concept:
        "An authorized red-team / security-test tool is a Benign True Positive ('Informational, expected activity'), not malware to escalate. Check the engagement/change ticket and deconfliction note first; suppress for the window — don't kill the rule that catches the real thing.",
      mitre: { id: "T1204", name: "User Execution" },
      pointer: "Defender for Endpoint classification: Informational, expected activity (Security test)",
    },
  },

  // ── Identity — MALICIOUS (MFA fatigue / prompt bombing) ────────────────────
  {
    id: "soc-id-mfa",
    archetype: "mfa-fatigue",
    alertTitle: "User reported suspicious MFA activity",
    detectionRule: "Entra ID Protection · userReportedSuspiciousActivity",
    toolSeverity: "High",
    trigger: "tkaur tapped 'No, it's not me' on a flood of MFA push prompts at 01:50 that she never started, and reported them.",
    asset: "account tkaur (Finance)",
    sources: [S.mfaLogs, S.entraRisk, S.signinLogs, S.threatIntel, S.namedLocations],
    keySourceIds: ["mfa-logs", "entra-risk"],
    evidence: [
      {
        id: "id2-mfa",
        sourceId: "mfa-logs",
        label: "Prompt bombing, denied + reported",
        detail: "A burst of MFA push prompts to tkaur's authenticator at 01:50, none tied to a sign-in she started; she denied and reported them. Classic MFA fatigue.",
        weight: "decisive",
      },
      {
        id: "id2-risk",
        sourceId: "entra-risk",
        label: "passwordSpray means the password is known",
        detail: "Alongside it, a passwordSpray detection on tkaur — which fires ONLY once the attacker has validated the correct password. The credential is already compromised.",
        weight: "decisive",
      },
      {
        id: "id2-signin",
        sourceId: "signin-logs",
        label: "Anonymized IP, unregistered device",
        detail: "The attempts driving the prompts come from an anonymized IP on an unregistered device, off-hours.",
        weight: "supporting",
      },
      {
        id: "id2-intel",
        sourceId: "threat-intel",
        label: "Source on a credential-attack feed",
        detail: "The source IP is on a credential-attack feed.",
        weight: "supporting",
      },
      {
        id: "id2-named",
        sourceId: "named-locations",
        label: "Not a known VPN/duty IP",
        detail: "The source isn't a sanctioned VPN or a known duty location.",
        weight: "supporting",
      },
    ],
    truth: "true-positive",
    correctDisposition: "escalate-ir-isolate",
    acceptableDispositions: ["escalate-tier2"],
    why:
      "She denied and reported prompts she never started — MFA fatigue — and the paired passwordSpray detection only fires once the attacker has the correct password, so the credential is already compromised and they're hammering MFA to get in. Confirm compromised: disable the account, force a reset, revoke sessions, escalate to IR. (Number-matching / login-context in Authenticator is what stops the fatigue working.)",
    learn: {
      concept:
        "MFA fatigue = unsolicited prompt-bombing hoping the user taps approve. 'User reported suspicious activity' fires on a denied+reported prompt; a paired passwordSpray means the password is already known. Treat as compromise — reset + revoke, don't just dismiss the prompts.",
      mitre: { id: "T1621", name: "Multi-Factor Authentication Request Generation" },
      pointer: "MITRE T1621 / T1078 · enable Authenticator number-matching",
    },
  },

  // ── Exfil — BENIGN TRUE POSITIVE (sanctioned nightly backup) ───────────────
  {
    id: "soc-exfil-backup",
    archetype: "data-exfil",
    alertTitle: "Large outbound transfer to cloud storage",
    detectionRule: "DLP / proxy · high-volume egress to cloud storage",
    toolSeverity: "Medium",
    trigger: "A service account moved a large volume of data to cloud storage overnight.",
    asset: "SRV-BACKUP-01 · service account svc-backup",
    sources: [S.changeTickets, S.cloudActivity, S.dlpHits, S.edrTree, S.threatIntel],
    keySourceIds: ["change-tickets", "cloud-activity"],
    evidence: [
      {
        id: "ex2-ticket",
        sourceId: "change-tickets",
        label: "Standing backup change CHG-2980",
        detail: "A standing change authorizes nightly backup of this share to the CORPORATE cloud tenant in exactly this window.",
        weight: "decisive",
      },
      {
        id: "ex2-cloud",
        sourceId: "cloud-activity",
        label: "Backup agent → corporate tenant",
        detail: "The transfer is the sanctioned backup product (not an ad-hoc script), under svc-backup, to the corporate tenant — not a personal account.",
        weight: "decisive",
      },
      {
        id: "ex2-dlp",
        sourceId: "dlp-hits",
        label: "Matched on volume, approved target",
        detail: "DLP matched on volume/class, but the destination is the approved corporate backup target.",
        weight: "supporting",
      },
      {
        id: "ex2-tree",
        sourceId: "edr-process-tree",
        label: "Signed, scheduled backup binary",
        detail: "The process is the backup product's signed binary, on its schedule.",
        weight: "supporting",
      },
      {
        id: "ex2-intel",
        sourceId: "threat-intel",
        label: "Corporate tenant, clean",
        detail: "Destination is the corporate cloud tenant; clean reputation.",
        weight: "neutral",
      },
    ],
    truth: "benign-true-positive",
    correctDisposition: "close-benign",
    why:
      "Same DLP/egress trigger as exfil, opposite verdict: it's the sanctioned nightly backup — the approved backup agent under the backup service account, to the CORPORATE tenant, covered by a standing change ticket. Correct detection of authorized activity = Benign-TP. Note it and close benign; escalating would page IR for a backup. Tells vs real exfil: signed backup product (not ad-hoc script), corporate destination (not personal), and a change ticket.",
    learn: {
      concept:
        "A scheduled backup or sanctioned cloud-sync to the CORPORATE tenant is a Benign-TP, not exfil. Discriminate on process (backup product vs ad-hoc script), destination (corporate vs personal cloud), and a change ticket — then add a DLP exclusion for the approved path.",
      mitre: { id: "T1567.002", name: "Exfiltration to Cloud Storage" },
      pointer: "DLP exclusions · authorized-backup path",
    },
  },

  // ── EDR — MALICIOUS (loader that executed + persistence + C2) ──────────────
  {
    id: "soc-edr-loader",
    archetype: "edr-malware",
    alertTitle: "EDR: malware that executed on an endpoint",
    detectionRule: "Defender for Endpoint · behavioral + AV detection",
    toolSeverity: "High",
    trigger: "Defender flagged a suspicious binary on ENG-WS-21; AlertEvidence shows it ran and is not yet contained.",
    asset: "ENG-WS-21 · user nbianchi (Engineering)",
    sources: [S.alertEvidence, S.edrTree, S.netProxy, S.changeTickets, S.threatIntel, S.hrDirectory],
    keySourceIds: ["alert-evidence", "edr-process-tree"],
    evidence: [
      {
        id: "ed1-evidence",
        sourceId: "alert-evidence",
        label: "Unsigned temp-path binary, NOT quarantined",
        detail: "AlertEvidence (DetectionSource=Antivirus, ServiceSource=Defender for Endpoint): an unsigned binary in %TEMP%, status NOT quarantined — it executed.",
        weight: "decisive",
      },
      {
        id: "ed1-tree",
        sourceId: "edr-process-tree",
        label: "Mail attachment → persistence",
        detail: "Lineage: a mail attachment → the binary → it wrote a Run key and a scheduled task, then reached out. Persistence established.",
        weight: "decisive",
      },
      {
        id: "ed1-net",
        sourceId: "network-proxy",
        label: "Beaconing to a fresh domain",
        detail: "Regular-interval outbound to a first-seen domain right after execution — beacon-like.",
        weight: "supporting",
      },
      {
        id: "ed1-intel",
        sourceId: "threat-intel",
        label: "Hash + domain known-bad",
        detail: "Both the file hash and the callout domain are on malware feeds.",
        weight: "supporting",
      },
      {
        id: "ed1-ticket",
        sourceId: "change-tickets",
        label: "No change, not a test box",
        detail: "No change record; ENG-WS-21 isn't a security/test host and nbianchi isn't IT.",
        weight: "decisive",
      },
      {
        id: "ed1-noise",
        sourceId: "hr-directory",
        label: "Recently changed teams",
        detail: "nbianchi changed teams recently — irrelevant to the detection.",
        weight: "noise",
      },
    ],
    truth: "true-positive",
    correctDisposition: "escalate-ir-isolate",
    acceptableDispositions: ["escalate-tier2"],
    why:
      "An unsigned temp-path binary that actually executed (not quarantined), spawned from a mail attachment, set up persistence (Run key + scheduled task), and is beaconing to a flagged domain — hash and domain both known-bad, no change ticket. That's a live infection: isolate the host and escalate to IR. (Most EDR remediation is reversible — you can restore a quarantined file later if it turns out benign.)",
    learn: {
      concept:
        "EDR triage: read AlertEvidence for the file + quarantine state, then the process tree for lineage and persistence (Run keys / scheduled tasks), then network for C2. 'Not quarantined' + persistence + beacon = it executed and is live → isolate.",
      mitre: { id: "T1204", name: "User Execution" },
      pointer: "MITRE ATT&CK · Defender for Endpoint AlertEvidence table",
    },
  },

  // ── Phishing — BENIGN TRUE POSITIVE (sanctioned simulation) ────────────────
  {
    id: "soc-phish-sim",
    archetype: "phishing",
    alertTitle: "Reported phishing — 'Q3 bonus, confirm details'",
    detectionRule: "Defender for Office 365 · user-reported",
    toolSeverity: "Medium",
    trigger: "Several users reported a 'Q3 bonus — confirm your details' email with a login link.",
    asset: "multiple users · sender rewards@hr-yourco-bonus.com",
    sources: [S.awareness, S.emailAuth, S.senderRep, S.urlDetonation, S.threatIntel],
    keySourceIds: ["awareness-campaign", "email-auth"],
    evidence: [
      {
        id: "ph2-aware",
        sourceId: "awareness-campaign",
        label: "Active authorized simulation",
        detail: "The awareness register shows an ACTIVE authorized phishing-simulation campaign this week, from the sanctioned platform, targeting exactly this user group — subject 'Q3 bonus'.",
        weight: "decisive",
      },
      {
        id: "ph2-auth",
        sourceId: "email-auth",
        label: "Authenticates to the sim platform",
        detail: "SPF/DKIM/DMARC pass for the simulation platform's domain — consistent with the register. (Auth-pass alone never proves benign; the register makes the call.)",
        weight: "supporting",
      },
      {
        id: "ph2-sender",
        sourceId: "sender-reputation",
        label: "Vendor lure domain, not a look-alike",
        detail: "The lure domain is owned by the awareness vendor — not a look-alike of a real corporate brand.",
        weight: "supporting",
      },
      {
        id: "ph2-url",
        sourceId: "url-detonation",
        label: "Training 'gotcha' page",
        detail: "The link goes to the training platform's tracking/teaching page, not a live credential harvester.",
        weight: "supporting",
      },
      {
        id: "ph2-intel",
        sourceId: "threat-intel",
        label: "No malicious indicators",
        detail: "No external malicious indicators.",
        weight: "neutral",
      },
    ],
    truth: "benign-true-positive",
    correctDisposition: "close-benign",
    why:
      "The reporters were right — it IS a phishing-shaped email. But it's the org's own sanctioned awareness simulation: the register shows an active authorized run from the training platform to this exact group, and the mail authenticates to that platform. Correct detection of authorized activity = Benign-TP. Don't escalate (you'd waste IR and tip off the test); note it and close benign — and the reports are exactly the behaviour the simulation trains.",
    learn: {
      concept:
        "A sanctioned phishing simulation is a Benign True Positive: the email really is phishing-shaped, but it's authorized. The campaign register is the proof — NOT the auth result (a real phish can pass its own auth, and sims are often allow-listed while failing it). Check the register before escalating user reports — and still credit the report.",
      mitre: { id: "T1566", name: "Phishing" },
      pointer: "Microsoft Attack Simulation Training / KnowBe4 · TP vs B-TP",
    },
  },

  // ── Exfil — MALICIOUS (sensitive data to personal cloud) ───────────────────
  {
    id: "soc-exfil-cloud",
    archetype: "data-exfil",
    alertTitle: "Possible exfiltration to personal cloud storage",
    detectionRule: "Defender for Cloud Apps / DLP · unusual upload to cloud storage",
    toolSeverity: "High",
    trigger: "Off-hours, a script on FIN-WS-08 read a large batch of classified finance files and POSTed them to a personal cloud-storage account.",
    asset: "FIN-WS-08 · user jmensah (Finance)",
    sources: [S.cloudActivity, S.dlpHits, S.edrTree, S.changeTickets, S.threatIntel],
    keySourceIds: ["cloud-activity", "dlp-hits"],
    evidence: [
      {
        id: "ex1-cloud",
        sourceId: "cloud-activity",
        label: "Ad-hoc process → personal cloud",
        detail: "An unusual process (powershell.exe) read large local files at 02:30, then made HTTPS POSTs to a PERSONAL cloud-storage account — not the corporate tenant.",
        weight: "decisive",
      },
      {
        id: "ex1-dlp",
        sourceId: "dlp-hits",
        label: "Classified data, far above baseline",
        detail: "The files matched the 'PII / financial-records' DLP policy; the volume is far above this user's normal.",
        weight: "decisive",
      },
      {
        id: "ex1-tree",
        sourceId: "edr-process-tree",
        label: "Not a backup product",
        detail: "powershell.exe wasn't launched by a backup product — it's an ad-hoc script, off-hours.",
        weight: "supporting",
      },
      {
        id: "ex1-intel",
        sourceId: "threat-intel",
        label: "No business relationship",
        detail: "The destination is a personal cloud-storage endpoint with no business relationship to the company.",
        weight: "supporting",
      },
      {
        id: "ex1-ticket",
        sourceId: "change-tickets",
        label: "No backup/migration change",
        detail: "No backup or data-migration change record covers this transfer.",
        weight: "decisive",
      },
    ],
    truth: "true-positive",
    correctDisposition: "escalate-ir-isolate",
    acceptableDispositions: ["escalate-tier2"],
    why:
      "Hallmark exfil: an unusual process (powershell, not a backup product) reading large classified files off-hours and POSTing them to a PERSONAL cloud account with no business relationship, far above baseline, no change ticket. Adversaries hide exfil in cloud storage the host already uses — but the personal destination + DLP class + volume give it away. Contain and escalate to IR.",
    learn: {
      concept:
        "Exfil to cloud storage (T1567.002) blends into normal cloud traffic — a common cloud service, often a personal account the host doesn't normally use. The read: unusual process + large reads + HTTPS POST to cloud storage + off-hours + DLP class + above baseline. The discriminator vs a benign backup is destination (personal vs corporate) and whether a backup/sync is authorized.",
      mitre: { id: "T1567.002", name: "Exfiltration to Cloud Storage" },
      pointer: "MITRE ATT&CK T1567.002 · Defender for Cloud Apps anomaly alerts",
    },
  },

  // ════ ROUND 3 — account lockout (docs/research/soc-tier1-cases-round3.md) ═════
  // The archetype where MOST alerts are benign misconfiguration, not a threat: the
  // #1 real cause is a device caching an OLD password after a reset. Event 4740's
  // "Caller Computer Name" is often blank — the read is to correlate 4771/4776.

  // ── Account lockout — FALSE POSITIVE (stale cached credential — the #1 cause) ──
  {
    id: "soc-lockout-stale",
    archetype: "account-lockout",
    alertTitle: "Repeated account lockouts — user achen",
    detectionRule: "SIEM · Event 4740 (account locked out) ×6 in an hour",
    toolSeverity: "Medium",
    trigger: "achen's account has locked out six times since the weekend password reset.",
    asset: "account achen (Marketing)",
    sources: [S.authFail, S.helpdesk, S.lockout, S.changeTickets, S.threatIntel, S.hrDirectory],
    keySourceIds: ["auth-failures", "it-helpdesk"],
    evidence: [
      {
        id: "al2-fail",
        sourceId: "auth-failures",
        label: "Bad passwords come from achen's OWN devices",
        detail: "Correlating 4771/4776: every failure traces to achen's phone (ActiveSync) and a mapped drive — both still submitting the OLD password from before the weekend reset.",
        weight: "decisive",
      },
      {
        id: "al2-help",
        sourceId: "it-helpdesk",
        label: "Helpdesk ticket: 'keeps locking'",
        detail: "Ticket from achen right after the scheduled weekend reset: 'my account keeps locking every few minutes.'",
        weight: "decisive",
      },
      {
        id: "al2-lockout",
        sourceId: "lockout-events",
        label: "4740 fires, Caller Computer Name blank",
        detail: "The 4740s repeat, but the Caller Computer Name is blank — the true source only shows once you correlate 4771/4776.",
        weight: "supporting",
      },
      {
        id: "al2-ticket",
        sourceId: "change-tickets",
        label: "Weekend reset explains the timing",
        detail: "The org-wide weekend password reset (CHG-4102) lines up with when the lockouts started — timing, not authorization.",
        weight: "supporting",
      },
      {
        id: "al2-intel",
        sourceId: "threat-intel",
        label: "All internal",
        detail: "Every source is internal; nothing external to enrich.",
        weight: "neutral",
      },
      {
        id: "al2-noise",
        sourceId: "auth-failures",
        label: "One failure from an odd subnet",
        detail: "A single failure once came from an unfamiliar subnet — but it resolves to the corporate VPN pool, not an attacker.",
        weight: "noise",
      },
      {
        id: "al2-hr",
        sourceId: "hr-directory",
        label: "User active, in office",
        detail: "HR calendar shows achen on a normal in-office day — nothing anomalous about the account being in use.",
        weight: "neutral",
      },
    ],
    truth: "false-positive",
    correctDisposition: "close-false-positive",
    why:
      "The #1 real cause of lockouts, and it looks alarming until you read it right. Event 4740's Caller Computer Name is blank, so you correlate 4771/4776 — and the bad passwords all come from achen's OWN phone and a mapped drive, still submitting the pre-reset password after the weekend change. No attack; a stale cached credential. Close FP, and have the user update the stored password everywhere it's cached.",
    learn: {
      concept:
        "Most account lockouts aren't an attack — a device caching an OLD password after a change. Event 4740's Caller Computer Name is often blank; correlate Kerberos 4771 / NTLM 4776 to find the true source. Escalate only when that source is anomalous/external.",
      mitre: { id: "T1110", name: "Brute Force" },
      pointer: "Microsoft event-4740 · 4771/4776 correlation to find the lockout source",
    },
  },

  // ── Account lockout — MALICIOUS (spray causing lockouts) ───────────────────
  {
    id: "soc-lockout-attack",
    archetype: "account-lockout",
    alertTitle: "Account lockouts across many users",
    detectionRule: "SIEM · Event 4740 across ≥10 accounts within minutes",
    toolSeverity: "High",
    trigger: "Ten accounts locked out within a few minutes, all failing from one source.",
    asset: "multiple accounts · via VPN-GW",
    sources: [S.authFail, S.changeTickets, S.threatIntel, S.lockout, S.geoVpn, S.hrDirectory],
    keySourceIds: ["auth-failures", "change-tickets"],
    evidence: [
      {
        id: "al1-fail",
        sourceId: "auth-failures",
        label: "Failures across 10+ accounts from one external IP",
        detail: "4771/4776 failures across 10+ accounts from a single external IP in minutes — a credential attack noisy enough to trip each account's lockout threshold. The lockouts are collateral of the attack.",
        weight: "decisive",
      },
      {
        id: "al1-ticket",
        sourceId: "change-tickets",
        label: "No authorized testing",
        detail: "No penetration-test authorization or credential-testing RoE covers this window.",
        weight: "decisive",
      },
      {
        id: "al1-intel",
        sourceId: "threat-intel",
        label: "Source on a credential-attack feed",
        detail: "The external source IP appears on a credential-attack feed.",
        weight: "supporting",
      },
      {
        id: "al1-lockout",
        sourceId: "lockout-events",
        label: "Many accounts, near-simultaneous",
        detail: "4740 across many accounts within the same short window — not one user's device.",
        weight: "supporting",
      },
      {
        id: "al1-geo",
        sourceId: "geo-vpn",
        label: "Foreign origin",
        detail: "The source geolocates to a country none of these users log in from.",
        weight: "supporting",
      },
      {
        id: "al1-hr",
        sourceId: "hr-directory",
        label: "Targeted users are active",
        detail: "The affected accounts are a spread of active users, none on leave — not one person's cached device.",
        weight: "supporting",
      },
    ],
    truth: "true-positive",
    correctDisposition: "escalate-ir-isolate",
    acceptableDispositions: ["escalate-tier2"],
    why:
      "Not a stale-cred misconfig: the 4771/4776 failures span 10+ accounts from a single external IP flagged on a credential-attack feed, foreign, with no authorized-testing ticket — noisy enough to lock each account. That's an active credential attack, and the lockouts are collateral. Escalate to IR and block the source. The tell vs the stale-cred case: MANY accounts from ONE external source, not one user's own device.",
    learn: {
      concept:
        "A credential attack noisy enough to lock accounts hits MANY accounts from ONE source — vs the single-user stale-cred case. Correlate 4771/4776 to the source: external + many accounts + no RoE = active attack, not a misconfigured device.",
      mitre: { id: "T1110", name: "Brute Force" },
      pointer: "MITRE ATT&CK T1110 · lockout as spray collateral",
    },
  },

  // ── Account lockout — BENIGN TRUE POSITIVE (sanctioned pentest spray) ───────
  {
    id: "soc-lockout-pentest",
    archetype: "account-lockout",
    alertTitle: "Lockouts across accounts from an internal host",
    detectionRule: "SIEM · Event 4740 across ≥15 accounts from one source",
    toolSeverity: "High",
    trigger: "A burst of lockouts across 18 accounts, all failing from one internal host.",
    asset: "multiple accounts · source PENTEST-01",
    sources: [S.changeTickets, S.authFail, S.lockout, S.threatIntel, S.hrDirectory],
    keySourceIds: ["change-tickets", "auth-failures"],
    evidence: [
      {
        id: "al3-ticket",
        sourceId: "change-tickets",
        label: "Approved pentest RoE CHG-4130",
        detail: "A signed pentest RoE covers credential testing from PENTEST-01 this week — lockouts are noted as an accepted side-effect.",
        weight: "decisive",
      },
      {
        id: "al3-fail",
        sourceId: "auth-failures",
        label: "Spray from the internal test host",
        detail: "4771/4776 failures across 18 accounts from PENTEST-01 (internal, security-team segment) — a spray, which is exactly what the engagement does.",
        weight: "decisive",
      },
      {
        id: "al3-lockout",
        sourceId: "lockout-events",
        label: "Source correlates to PENTEST-01",
        detail: "4740 across many accounts; correlation points at the internal test host, not an external attacker.",
        weight: "supporting",
      },
      {
        id: "al3-intel",
        sourceId: "threat-intel",
        label: "Internal source",
        detail: "Internal source; nothing external in play.",
        weight: "neutral",
      },
      {
        id: "al3-hr",
        sourceId: "hr-directory",
        label: "Engagement window on the calendar",
        detail: "The security calendar shows an authorized engagement running this week — consistent with the RoE.",
        weight: "supporting",
      },
    ],
    truth: "benign-true-positive",
    correctDisposition: "close-benign",
    why:
      "It looks exactly like the malicious case — a spray causing lockouts across 18 accounts — and it IS spray behaviour, so the detection is correct. But the source is the security team's internal test host, and a signed pentest RoE covers it (lockouts noted as an accepted side-effect). Correct detection of authorized activity = Benign-TP: confirm the RoE, note it, close benign. Escalating would burn IR on a sanctioned test.",
    learn: {
      concept:
        "A sanctioned pentest can trip lockouts too — real spray behaviour, but authorized. Check the RoE / deconfliction before escalating a mass-lockout event; source-internal + a signed engagement = Benign-TP, same detection as the malicious spray.",
      mitre: { id: "T1110", name: "Brute Force" },
      pointer: "Purple-team deconfliction · 'is this us or someone else?'",
    },
  },

  // ════ ROUND 4 — insider threat (docs/research/soc-tier1-cases-round4.md) ══════
  // The subtlest archetype: the SAME action is malicious or benign depending on
  // intent / authorization / ROLE — not the action. And the disposition inverts the
  // usual instinct: you ESCALATE (hand up to insider-risk / HR / legal), you do NOT
  // isolate or confront — that's an HR/legal matter, and acting alone burns the case.

  // ── Insider — MALICIOUS (departing employee, data theft) ───────────────────
  {
    id: "soc-insider-departing",
    archetype: "insider-threat",
    alertTitle: "Insider risk — departing-employee data theft",
    detectionRule: "Purview IRM · 'Data theft by departing users' (High)",
    toolSeverity: "High",
    trigger: "IRM flagged jwalsh (resignation on file, last day Friday): a spike of SharePoint bulk-downloads and copies to a personal cloud account this week.",
    asset: "user jwalsh (Sales) · resignation on file",
    sources: [S.hrDirectory, S.cloudActivity, S.changeTickets, S.dlpHits, S.roleScope, S.threatIntel],
    keySourceIds: ["hr-directory", "change-tickets", "cloud-activity"],
    evidence: [
      {
        id: "in1-hr",
        sourceId: "hr-directory",
        label: "Departing — last day Friday",
        detail: "HR: jwalsh resigned; last working day is Friday. IRM's departing-user policy is scoring exfiltration indicators against that end date.",
        weight: "decisive",
      },
      {
        id: "in1-cloud",
        sourceId: "cloud-activity",
        label: "Download-then-exfiltrate to a PERSONAL account",
        detail: "A sequence: bulk SharePoint downloads, then copies to a personal cloud account and a USB, this week — well above jwalsh's 90-day baseline.",
        weight: "decisive",
      },
      {
        id: "in1-ticket",
        sourceId: "change-tickets",
        label: "No authorized export",
        detail: "No approved bulk-export, data-migration, or offboarding-handover ticket covers this activity.",
        weight: "decisive",
      },
      {
        id: "in1-dlp",
        sourceId: "dlp-hits",
        label: "Sensitive customer data, above norm",
        detail: "The files match the customer-list / pricing DLP policy — sensitive, and far above a Sales rep's normal export volume.",
        weight: "supporting",
      },
      {
        id: "in1-role",
        sourceId: "role-scope",
        label: "Some access is out of scope",
        detail: "Several accessed folders sit outside jwalsh's team's normal scope.",
        weight: "supporting",
      },
      {
        id: "in1-neutral",
        sourceId: "threat-intel",
        label: "Nothing external to enrich",
        detail: "No external indicators — this is a trusted insider, not an outside attacker. That's exactly why it's hard: the account is legitimate.",
        weight: "neutral",
      },
    ],
    truth: "true-positive",
    correctDisposition: "escalate-tier2",
    why:
      "The subtlest archetype: the SAME bulk-download is theft or business-as-usual depending on AUTHORIZATION and ROLE. Here every discriminator points to theft — jwalsh resigned (last day Friday), there's a download-then-exfiltrate sequence to a personal cloud + USB well above baseline, on sensitive customer data, with no authorized-export ticket. Escalate to the insider-risk / HR / legal program — and do NOT unilaterally isolate or confront: that's an HR/legal matter, and tipping them off or acting alone destroys the case. Hand it up; preserve the evidence.",
    learn: {
      concept:
        "Insider threat is the archetype where the action alone tells you nothing — the same download is malicious or benign depending on intent, authorization and role. Read CONTEXT: employment status (departing?), an authorized-export ticket, and whether the data is in scope. And the disposition inverts the usual instinct: ESCALATE to a multi-stakeholder insider-risk / HR / legal program — do NOT isolate or confront. A Tier-1 hands it up.",
      mitre: { id: "T1567", name: "Exfiltration Over Web Service" },
      pointer: "Microsoft Purview Insider Risk Management · CISA Insider Threat Mitigation Guide",
    },
  },

  // ── Insider — FALSE POSITIVE (data-heavy role's baseline) ──────────────────
  {
    id: "soc-insider-baseline",
    archetype: "insider-threat",
    alertTitle: "Insider risk — bulk dataset access, user rmehta",
    detectionRule: "Purview IRM · anomalous activity above baseline (Medium)",
    toolSeverity: "Medium",
    trigger: "IRM flagged rmehta for a spike in large dataset downloads this week.",
    asset: "user rmehta (Data Science)",
    sources: [S.roleScope, S.insiderRisk, S.cloudActivity, S.hrDirectory, S.changeTickets, S.dlpHits],
    keySourceIds: ["role-scope", "insider-risk"],
    evidence: [
      {
        id: "in2-role",
        sourceId: "role-scope",
        label: "Large dataset access IS the job",
        detail: "rmehta is a data scientist — large dataset access is squarely in scope. A data-heavy role has a high normal, so this isn't actually anomalous for them.",
        weight: "decisive",
      },
      {
        id: "in2-risk",
        sourceId: "insider-risk",
        label: "Within their 90-day baseline",
        detail: "rmehta's 90-day baseline already includes regular large pulls; this week is within their normal range, prior history clean, no employment-status change.",
        weight: "decisive",
      },
      {
        id: "in2-cloud",
        sourceId: "cloud-activity",
        label: "Stays in the corporate environment",
        detail: "Everything stays in the corporate analytics environment — no USB, no personal cloud, no external sharing.",
        weight: "supporting",
      },
      {
        id: "in2-hr",
        sourceId: "hr-directory",
        label: "Long-tenured, not departing",
        detail: "A long-tenured active employee; no resignation or end-date signal.",
        weight: "supporting",
      },
      {
        id: "in2-ticket",
        sourceId: "change-tickets",
        label: "In-role work, no special ticket needed",
        detail: "Routine analytics; no special ticket, but none is needed for in-role access.",
        weight: "neutral",
      },
      {
        id: "in2-dlp",
        sourceId: "dlp-hits",
        label: "Matched on volume",
        detail: "DLP matched on volume — which is what tripped the anomaly — but volume alone isn't the story for this role.",
        weight: "noise",
      },
    ],
    truth: "false-positive",
    correctDisposition: "close-false-positive",
    why:
      "The mirror of the departing-employee case: the SAME bulk access, opposite verdict. rmehta is a data scientist — large dataset access is their JOB, in scope, and within their 90-day baseline; it stays in the corporate environment; they're not departing. The UEBA 'anomaly' misfired because a data-heavy role has a high normal. Close FP and tune the baseline for the role. The action told you nothing — role and context did.",
    learn: {
      concept:
        "UEBA insider anomalies over-fire on data-heavy roles — a data scientist's 'anomalous' bulk access is their baseline. Read role/scope + the user's own 90-day norm, not the raw volume. Same action, opposite verdict from the departing-employee case.",
      mitre: { id: "T1078", name: "Valid Accounts" },
      pointer: "Purview IRM · behavioral baselines · tune per-role thresholds",
    },
  },

  // ── Insider — BENIGN TRUE POSITIVE (sanctioned migration/export) ───────────
  {
    id: "soc-insider-migration",
    archetype: "insider-threat",
    alertTitle: "Insider risk — large export to cloud, user tokafor",
    detectionRule: "Purview IRM · 'Data leaks' (High-severity DLP)",
    toolSeverity: "High",
    trigger: "IRM flagged tokafor for a large one-off export of a records set to cloud storage.",
    asset: "user tokafor (IT · Migrations)",
    sources: [S.changeTickets, S.cloudActivity, S.roleScope, S.hrDirectory, S.dlpHits, S.insiderRisk],
    keySourceIds: ["change-tickets", "cloud-activity"],
    evidence: [
      {
        id: "in3-ticket",
        sourceId: "change-tickets",
        label: "Approved migration CHG-5330",
        detail: "An approved data-migration change authorizes moving this records set to the new CORPORATE cloud tenant this week; tokafor is the assigned migration engineer.",
        weight: "decisive",
      },
      {
        id: "in3-cloud",
        sourceId: "cloud-activity",
        label: "To the corporate tenant, not personal",
        detail: "The export goes to the corporate tenant (the migration target), not a personal account — a real bulk export, but the sanctioned one.",
        weight: "decisive",
      },
      {
        id: "in3-role",
        sourceId: "role-scope",
        label: "Migrations engineer, in scope",
        detail: "tokafor is on the migrations team; this records set is in scope for the project.",
        weight: "supporting",
      },
      {
        id: "in3-hr",
        sourceId: "hr-directory",
        label: "Active, not departing",
        detail: "Active employee; no resignation or end-date signal.",
        weight: "supporting",
      },
      {
        id: "in3-dlp",
        sourceId: "dlp-hits",
        label: "Correctly matched — it IS a big export",
        detail: "DLP matched on volume/class correctly: it genuinely is a large sensitive export (the detection is right).",
        weight: "neutral",
      },
      {
        id: "in3-risk",
        sourceId: "insider-risk",
        label: "No prior risk history",
        detail: "No prior insider-risk history; nothing correlating with employment status.",
        weight: "neutral",
      },
    ],
    truth: "benign-true-positive",
    correctDisposition: "close-benign",
    why:
      "Unlike the role-baseline FP, this IS a real, above-baseline bulk export — the detection is correct — but it's the sanctioned migration: an approved change ticket, tokafor is the assigned engineer, and the destination is the CORPORATE tenant, not a personal account. Correct detection of authorized activity = Benign-TP: confirm the ticket, note it, close benign. The discriminators vs the departing-employee theft: authorization + corporate destination + in-role, and the user isn't leaving.",
    learn: {
      concept:
        "A sanctioned bulk export / migration is a Benign-TP: the detection correctly fires on a real large transfer, but a change ticket authorizes it and the destination is corporate, not personal. Distinguish the three: role-baseline (FP — the anomaly never happened) vs authorized migration (Benign-TP — it happened, and a ticket sanctioned it) vs departing-employee theft (TP — unauthorized, personal destination, leaving).",
      mitre: { id: "T1567", name: "Exfiltration Over Web Service" },
      pointer: "Purview IRM · authorized-export / migration exclusion",
    },
  },
];

// Cases GENERATED from red-seat runs (the "same board, two seats" handoff). Pure +
// deterministic — they play like any hand-authored case, and carry a `handoff` marker.
export const HANDOFF_CASES: SocCase[] = RED_RUNS.map((r) => caseFromRedRun(r, S));

export const SOC_CASES: SocCase[] = [...HAND_AUTHORED_CASES, ...HANDOFF_CASES];

export const SOC_CASES_BY_ID: Record<string, SocCase> = Object.fromEntries(
  SOC_CASES.map((c) => [c.id, c])
);

// The ordered first shift: open on the thesis TP, immediately follow with the
// look-alike FP, then the subtle Benign-TP — so the player feels "same detection,
// different verdict" early — then the rest, closing on the pentest Benign-TP bridge.
export const FIRST_SHIFT_CASE_IDS: string[] = [
  "soc-ps-cradle", // TP   — encoding ≠ threat; read the lineage
  "soc-auth-reset", // FP  — looks like a hit, it's a password reset
  "soc-ps-patch", // Benign — correct detection, authorized
  "soc-dns-beacon", // TP  — real C2 beacon
  "soc-auth-bruteforce", // TP — account compromise
  "soc-dns-cdn", // FP   — DGA heuristic over-fires on a CDN
  "soc-auth-pentest", // Benign — sanctioned spray (the bridge)
];

// A second shift over the round-2 archetypes (phishing / identity / EDR / exfil).
// Opens on a clear phish (TP), then the look-alike FP, then the subtle authorized-
// tool Benign-TP — same "different verdict" rhythm — pairing each archetype's
// malicious and not-a-threat variants across the shift.
export const SECOND_SHIFT_CASE_IDS: string[] = [
  "soc-phish-harvest", // TP     — real credential-harvest phish
  "soc-id-vpn", // FP            — impossible travel = corporate VPN
  "soc-edr-test", // Benign      — authorized red-team tool
  "soc-id-mfa", // TP            — MFA-fatigue + password compromise
  "soc-exfil-backup", // Benign  — sanctioned nightly backup
  "soc-edr-loader", // TP        — malware that executed + persistence + C2
  "soc-phish-sim", // Benign     — sanctioned phishing simulation
  "soc-exfil-cloud", // TP       — exfil to personal cloud
];

// The lockout queue — deliberately FP/benign-heavy: most real lockouts are a device
// caching an old password, not an attack. Opens on that #1 benign cause, then the
// look-alike real spray, then the sanctioned-pentest Benign-TP.
export const LOCKOUT_SHIFT_CASE_IDS: string[] = [
  "soc-lockout-stale", // FP     — stale cached credential (the #1 real cause)
  "soc-lockout-attack", // TP    — spray causing lockouts
  "soc-lockout-pentest", // Benign — sanctioned pentest spray
];

// The insider desk — the archetype where CONTEXT (intent/authorization/role), not the
// action, decides the call, and the disposition is escalate-and-hand-up, never isolate.
export const INSIDER_SHIFT_CASE_IDS: string[] = [
  "soc-insider-departing", // TP     — departing-employee data theft
  "soc-insider-baseline", // FP      — data-heavy role's baseline (anomaly = the norm)
  "soc-insider-migration", // Benign — sanctioned migration/export
];

/** The playable shifts. `unlockStanding` gates them so they aren't all open from
 *  scratch — you earn access up the ladder (see app/lib/career/state.ts). */
export interface ShiftDef {
  id: string;
  label: string;
  caseIds: string[];
  unlockStanding: number; // ⬢ standing required to open this queue
  requiresRedRun?: boolean; // also needs ≥1 completed red-seat run (a cross-seat gate)
  note?: string; // flavour shown on a locked card
}
export const SHIFTS: ShiftDef[] = [
  { id: "first-shift", label: "Shift 1 · fundamentals", caseIds: FIRST_SHIFT_CASE_IDS, unlockStanding: 0 },
  { id: "second-shift", label: "Shift 2 · phishing · identity · EDR · exfil", caseIds: SECOND_SHIFT_CASE_IDS, unlockStanding: 40 },
  { id: "lockout-shift", label: "Shift 3 · the lockout queue (mostly not a threat)", caseIds: LOCKOUT_SHIFT_CASE_IDS, unlockStanding: 90 },
  {
    id: "handoff-shift",
    label: "Shift 4 · the other chair (your red runs)",
    caseIds: HANDOFF_CASES.map((c) => c.id),
    unlockStanding: 90,
    requiresRedRun: true,
    note: "Adjudicate your own tradecraft from the blue side — run a red-seat mission to open it.",
  },
  {
    id: "insider-shift",
    label: "Shift 5 · the insider desk (context is the call)",
    caseIds: INSIDER_SHIFT_CASE_IDS,
    unlockStanding: 210,
  },
];
