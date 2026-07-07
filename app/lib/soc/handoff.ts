// The Red↔Blue handoff — "same board, two seats" made mechanical.
//
// A run the player performed in the RED seat (recon → access → action → exfil)
// leaves a trail. That trail IS the blue seat's evidence: the operator's tradecraft
// becomes the analyst's log signals. The pivotal question is the same one the whole
// blue seat turns on — was it AUTHORIZED? A sanctioned red-team run, seen from the
// blue chair, is a Benign True Positive; the identical tradecraft with no engagement
// behind it is a True Positive. The only difference is the RoE.
//
// Pure + deterministic: caseFromRedRun maps a RedRun to a SocCase that plays in the
// console like any hand-authored case. Guardrail-safe — every signal is an analyst
// READ (a pattern / an event id), never a working technique.

import type { DataSource, Disposition, SocCase, SocEvidence, SocVerdict } from "@/app/lib/soc/types";

// The tradecraft an operator can leave behind (a superset of the red seat's verbs).
export type RedTradecraft =
  | "osint" // external recon — little host telemetry
  | "cred-spray" // acquire --spray: a 4625 burst → 4624
  | "proxy-chain" // route through anonymizing hops
  | "session" // connect: a new session
  | "exfil-copy" // cp: scoped read → egress
  | "log-edit" // edit: a surgical file/manifest change
  | "log-wipe" // wipe logs: the audit log cleared (1102)
  | "rf-collect"; // off-host RF collection — invisible to the blue log estate

export interface RedRun {
  id: string;
  operator: string; // the handle
  targetLabel: string;
  objective: "exfil" | "modify" | "identify" | "characterize";
  tradecraft: RedTradecraft[];
  authorized: boolean; // did a scoped engagement / RoE cover it?
  roeRef?: string; // the engagement reference, if authorized
  quiet: boolean; // clean (quiet) exit vs loud
}

interface Signal {
  sourceKey: string; // key into the shared source catalogue
  label: string;
  detail: string;
  weight: SocEvidence["weight"];
}

// Each tradecraft → the blue signal it leaves, and which source reveals it. `null`
// means it leaves no meaningful host-side telemetry (external recon / off-host RF).
const TRADECRAFT_SIGNAL: Record<RedTradecraft, Signal | null> = {
  "cred-spray": {
    sourceKey: "authLogs",
    label: "Password spray → 4624 success",
    detail: "A spray of 4625 failures across many accounts from one source, then a 4624 success — the access step of the operator's run.",
    weight: "decisive",
  },
  "proxy-chain": {
    sourceKey: "signinLogs",
    label: "Source chains through proxies",
    detail: "The session's source routes through anonymizing hops (anonymized-IP style) — no single clean origin.",
    weight: "supporting",
  },
  session: {
    sourceKey: "signinLogs",
    label: "New session, unfamiliar host",
    detail: "A new session from a device and user-agent not seen for this account before.",
    weight: "supporting",
  },
  "exfil-copy": {
    sourceKey: "dlpHits",
    label: "Scoped files read, then egress",
    detail: "A read of the exact files named in scope, followed by an outbound transfer — the objective itself.",
    weight: "decisive",
  },
  "log-edit": {
    sourceKey: "alertEvidence",
    label: "Manifest/log entry modified",
    detail: "A single, surgical edit to a log/manifest on the target — precise, not bulk.",
    weight: "supporting",
  },
  "log-wipe": {
    sourceKey: "alertEvidence",
    label: "Audit log cleared (Event ID 1102)",
    detail: "The security audit log was cleared — a 1102 event. Cleanup or anti-forensics depends entirely on who did it, and whether they were allowed to.",
    weight: "decisive",
  },
  osint: null,
  "rf-collect": null,
};

interface Primary {
  archetype: SocCase["archetype"];
  mitre?: { id: string; name: string };
  alertTitle: string;
  detectionRule: string;
}

// Resolve ONE coherent "primary technique" that drives archetype, title, rule AND
// MITRE together — centred on the run's IMPACT (its objective), so the headline and
// the taught technique never diverge. Secondary tradecraft still shows up as evidence.
function resolvePrimary(run: RedRun): Primary {
  const has = (t: RedTradecraft) => run.tradecraft.includes(t);
  if (run.objective === "exfil" || has("exfil-copy"))
    return {
      archetype: "data-exfil",
      mitre: { id: "T1567.002", name: "Exfiltration to Cloud Storage" },
      alertTitle: `Data accessed and moved off ${run.targetLabel}`,
      detectionRule: "DLP / Cloud Apps · scoped read + egress",
    };
  if (run.objective === "modify" || has("log-wipe") || has("log-edit"))
    return {
      archetype: "edr-malware",
      mitre: has("log-wipe")
        ? { id: "T1070.001", name: "Indicator Removal: Clear Windows Event Logs" }
        : { id: "T1070", name: "Indicator Removal" },
      alertTitle: `Log/integrity tampering on ${run.targetLabel}`,
      detectionRule: "SIEM · audit log cleared (1102) + file modification",
    };
  if (has("cred-spray"))
    return {
      archetype: "auth-bruteforce",
      mitre: { id: "T1110.003", name: "Brute Force: Password Spraying" },
      alertTitle: `Credential attack then access — ${run.targetLabel}`,
      detectionRule: "SIEM · password spray → 4624 success",
    };
  if (has("session") || has("proxy-chain"))
    return {
      archetype: "impossible-travel",
      mitre: { id: "T1078", name: "Valid Accounts" },
      alertTitle: `Anomalous access to ${run.targetLabel}`,
      detectionRule: "Entra ID Protection · anomalous sign-in",
    };
  // off-host recon only (osint / rf-collect leave no host telemetry, no host technique)
  return {
    archetype: "impossible-travel",
    mitre: undefined,
    alertTitle: `External reconnaissance against ${run.targetLabel}`,
    detectionRule: "Recon telemetry · minimal host footprint",
  };
}

/**
 * Map a red-seat run to a blue-seat case. Pure — pass the shared source catalogue
 * so the generated case's sources read identically to the hand-authored ones.
 */
export function caseFromRedRun(run: RedRun, sources: Record<string, DataSource>): SocCase {
  const signals = run.tradecraft
    .map((t) => TRADECRAFT_SIGNAL[t])
    .filter((s): s is Signal => s !== null);

  // Sources this case exposes = the ones its signals touch, plus change-tickets
  // (authorization is always the pivotal thing to check). Every sourceKey is a known
  // constant in the catalogue, so we deref directly (fail fast if one is ever missing).
  const usedKeys = new Set<string>(signals.map((s) => s.sourceKey));
  usedKeys.add("changeTickets");
  const caseSources: DataSource[] = [...usedKeys].map((k) => sources[k]);

  const evidence: SocEvidence[] = signals.map((s, i) => ({
    id: `${run.id}-sig${i}`,
    sourceId: sources[s.sourceKey].id,
    label: s.label,
    detail: s.detail,
    weight: s.weight,
  }));

  // The pivotal finding: is there an engagement behind it?
  evidence.push(
    run.authorized
      ? {
          id: `${run.id}-roe`,
          sourceId: sources.changeTickets.id,
          label: `Approved engagement ${run.roeRef ?? ""}`.trim(),
          detail: `An authorized engagement / RoE (${run.roeRef ?? "on file"}) covers this operator, target and window. The activity is real attack behaviour — but sanctioned.`,
          weight: "decisive",
        }
      : {
          id: `${run.id}-noroe`,
          sourceId: sources.changeTickets.id,
          label: "No engagement covers this",
          detail: "No RoE, change ticket, or authorized-testing record covers this operator, target or window.",
          weight: "decisive",
        }
  );

  const primary = resolvePrimary(run);
  const truth: SocVerdict = run.authorized ? "benign-true-positive" : "true-positive";
  const correctDisposition: Disposition = run.authorized ? "close-benign" : "escalate-ir-isolate";

  // Key sources = authorization (the crux) + every source carrying a DECISIVE signal
  // (falling back to the first signal if none is decisive), so the debrief's
  // "you pulled the sources that answer this" credits the logs that actually matter.
  const decisiveKeys = [...new Set(signals.filter((s) => s.weight === "decisive").map((s) => s.sourceKey))];
  const keyKeys = decisiveKeys.length ? decisiveKeys : signals[0] ? [signals[0].sourceKey] : [];
  const keySourceIds = [sources.changeTickets.id, ...keyKeys.map((k) => sources[k].id)];

  const traded = signals.map((s) => s.label).join("; ");
  const tradedPhrase = traded || "off-host reconnaissance only — little host telemetry";
  // Surface a layered anti-forensics tell in prose when log-clearing isn't the headline.
  const wipeNote =
    run.tradecraft.includes("log-wipe") && primary.mitre?.id !== "T1070.001"
      ? " They also cleared the audit log (a 1102) on the way out — anti-forensics layered on top."
      : "";

  const why = run.authorized
    ? `This alert IS a run you performed in the red seat — the same board, from the blue chair. The tradecraft (${tradedPhrase}) is genuine attack behaviour and the detection is CORRECT, but an authorized engagement (${run.roeRef ?? "RoE on file"}) covers this operator, target and window.${wipeNote} That's a Benign True Positive: verify the RoE / deconfliction, note it, close benign. Escalating would page IR for a sanctioned test; isolating would blow up the engagement.`
    : `The same tradecraft a sanctioned run leaves (${tradedPhrase}) — but nothing authorizes this one: no RoE, no change ticket, no engagement.${wipeNote} Correct detection of REAL, unauthorized attack activity → a True Positive. Contain and escalate to IR. The ONLY thing separating this from a Benign-TP is the missing authorization — not who ran it.`;

  return {
    id: `soc-handoff-${run.id}`,
    archetype: primary.archetype,
    alertTitle: primary.alertTitle,
    detectionRule: primary.detectionRule,
    toolSeverity: run.quiet ? "Medium" : "High",
    trigger: `${run.operator}'s session ${run.quiet ? "moved quietly through" : "was noisy on"} ${run.targetLabel}: ${tradedPhrase}.`,
    asset: `${run.targetLabel} · operator ${run.operator}`,
    sources: caseSources,
    keySourceIds,
    evidence,
    truth,
    correctDisposition,
    acceptableDispositions: run.authorized ? undefined : ["escalate-tier2"],
    why,
    learn: {
      concept:
        "Same board, two seats: a red-team run seen from the blue chair. The ONLY thing separating a Benign-TP from a TP is authorization — check for the engagement / RoE / deconfliction record before you act, not who the tradecraft looks like. That's exactly why those records exist.",
      mitre: primary.mitre,
      pointer: "Purple-team deconfliction · 'is this us or someone else?'",
    },
    handoff: { fromRun: run.id, operator: run.operator },
  };
}

// A curated set of runs (referencing the red campaign's shape): two authorized
// engagements → Benign-TP, and one unsanctioned run with identical tradecraft → TP.
// Same behaviour, opposite verdict — the bridge in one shift.
export const RED_RUNS: RedRun[] = [
  {
    id: "the-key",
    operator: "ghost_0x2A",
    targetLabel: "Polaris Capital settlement mesh",
    objective: "exfil",
    tradecraft: ["osint", "cred-spray", "proxy-chain", "session", "exfil-copy"],
    authorized: true,
    roeRef: "RoE-PLR-14",
    quiet: true,
  },
  {
    id: "burn-notice",
    operator: "ghost_0x2A",
    targetLabel: "Charon substation historian",
    objective: "modify",
    tradecraft: ["proxy-chain", "session", "log-edit", "log-wipe"],
    authorized: true,
    roeRef: "RoE-CHR-09",
    quiet: false,
  },
  {
    // You, off-book — the blackhat path. Your handle, but NO engagement behind it.
    // Identical tradecraft to the sanctioned runs, opposite verdict: authorization,
    // not authorship, is what makes it a True Positive.
    id: "unsanctioned",
    operator: "ghost_0x2A",
    targetLabel: "Aurora Labs LIMS",
    objective: "exfil",
    tradecraft: ["proxy-chain", "cred-spray", "session", "exfil-copy", "log-wipe"],
    authorized: false,
    quiet: false,
  },
];
