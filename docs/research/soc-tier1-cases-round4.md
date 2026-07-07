# SOC Tier-1 cases — research round 4 (the insider-threat archetype)

> Fourth research pass (2026-07-04) grounding the **insider-threat** archetype that round 3
> flagged as a GAP (no surviving claim). Primary sources: **Microsoft Purview Insider Risk
> Management (IRM)** product docs and **CISA** insider-threat guidance. Same bar/guardrail as
> rounds 1–3 (analyst *read* / detection *patterns* only — the USB-copy / staging / upload
> actions are behavioral indicators, never a how-to).
>
> **Method:** deep-research harness — 5 angles → 20 sources → 95 claims → 25 to 3-vote
> adversarial verification → **23 confirmed (mostly 3-0), 2 killed.** Insider mechanics rest on
> current (2025-26) Microsoft Learn + CISA primaries. No salary figures asserted.

## Insider threat  *(VERIFIED — Microsoft Purview IRM + CISA)*

- **Trigger / detection source:** **Microsoft Purview Insider Risk Management (IRM)**. Two
  relevant policy templates (verbatim): **"Data theft by departing users"** and **"Data
  leaks."** The departing-users template scores exfiltration indicators — *downloading files
  from SharePoint Online, printing files, copying data to personal cloud/storage services* —
  **near an employee's resignation and end dates**, driven by an **HR-connector
  resignation/termination-date signal OR a Microsoft Entra account-deletion trigger** (not
  strictly "required" to be the HR connector — *that specific claim was refuted 0-3*). Each
  alert gets a **system-calculated High/Medium/Low severity** (uncustomizable risk score; can
  rise if untriaged). UEBA-style: IRM analyses each user's activity over a **rolling 90–120-day
  baseline** and looks for anomalies vs that norm.
- **Data sources & the question each answers:**
  - **DLP policy hits** → *what data / how sensitive / how much* (high-severity DLP alerts feed
    the "Data leaks" template — note: the DLP-side *Incident-report level* gates whether an IRM
    alert is generated; the IRM-side severity then drives triage priority — keep the two distinct).
  - **Endpoint + cloud-app activity** → *was there an exfiltration sequence?* IRM detects device
    indicators (creating/copying files to USB; browser upload to the web), office indicators
    (external SharePoint/Teams sharing), and multi-step **sequences** ("Download from M365 then
    exfiltrate", "…exfiltrate then delete", "…obfuscate then exfiltrate").
  - **HR context** → *is this a departing / recently-notified employee?* (HR-connector last
    working date; Entra last-working-date / account-deletion in the user profile).
  - **Role / entitlement context** → *is this data IN SCOPE for the user's job?*
  - **The insider-risk score itself** → *how does this correlate with employment status and prior history?*
- **Aha (malicious / TRUE POSITIVE):** a **departing / recently-resigned** employee whose
  activity spikes near their end date — bulk-downloading from SharePoint, copying to USB or a
  **personal** cloud account, a detected **download-then-exfiltrate** sequence — **outside their
  normal pattern** and their role.
- **Aha (benign / FP):** the *same actions* can be legitimate. Two distinct not-a-threat reads:
  - **False Positive** — a **data-heavy role's baseline** (a data scientist / analyst whose job
    NORMALLY touches large datasets, so the UEBA "anomaly" *is* their norm; stays in the corporate
    environment). The detection misfired → tune the baseline.
  - **Benign True Positive** — a **real, above-baseline bulk export that is AUTHORIZED**: a
    ticketed data **migration**, a sanctioned export, to a **corporate** destination (not personal).
    The detection was right; the activity was sanctioned.
- **The teaching point (medium-confidence synthesis, present as the analyst's reasoning, not a
  Microsoft quote):** *the discriminator is **intent / authorization / role**, not the action
  itself* — the identical download is malicious or benign depending on whether it was authorized
  and in-scope for the job. Grounded in IRM detecting **both malicious AND inadvertent** risk and
  Microsoft's requirement that customers **"conduct their own full investigation… not just rely
  on"** the IRM signal.
- **Decision (the important nuance):** **ESCALATE and hand up** to a **multi-stakeholder
  insider-risk / HR / legal program** — a Tier-1 analyst does **NOT** unilaterally isolate or
  confront the user. Grounded in **IRM** (alert → case → *share* → **escalate to eDiscovery
  Premium / legal-hold** workflow) and **CISA** (a four-phase Define→Detect→Assess→Manage
  framework, handled by a **multi-disciplinary Threat Management Team**: Insider Threat
  Analyst, **HR, General Counsel, CISO**, Ops, + external investigator/counsel). Isolating/
  confronting at Tier-1 tips off the subject and destroys the HR/legal case. → In-game this maps
  to **escalate (hand up), NOT escalate-with-isolate** — the case that inverts the usual
  "high-confidence → isolate" instinct.
- **MITRE (use only round-2-verified ids):** **T1567** *Exfiltration Over Web Service* (the
  upload-to-personal-cloud exfil) and **T1078** *Valid Accounts* (insider abuse of legitimate
  access). **Do NOT use unverified ids:** `T1530` (Data from Cloud Storage), `T1074` (Data
  Staged), `T1052` (Exfiltration Over Physical Medium / USB), `T1114` (Email Collection) — this
  pass produced **no surviving MITRE claim**; they'd map to IRM's USB/staging/email indicators
  but need a dedicated attack.mitre.org verification first.
- **Learn-for-real:** Microsoft Purview Insider Risk Management docs; CISA *Insider Threat
  Mitigation Guide*; the "context beats action" habit.

## Caveats (must respect)
- **MITRE gap:** `T1530`/`T1074`/`T1052`/`T1114` NOT verified this pass — don't present them.
  `T1078`/`T1567` are carried from round 2 (verified there).
- **The crisp "discriminator = intent/authorization/role" line is a SYNTHESIS**, not a verbatim
  source quote — present it as the analyst's reasoning (medium confidence), not a Microsoft quote.
- **Terminology is ours:** "Tier-1 analyst" is the game's SOC mapping; Microsoft uses
  "Reviewers/Analysts/Investigators", CISA uses "Threat Management Team". The escalate-don't-act
  point holds; the label is ours. Microsoft's docs inconsistently name the template "Data theft
  by departing users" vs "Departing user data theft".
- **Severity nuance:** the DLP *Incident-report level* (Low/Med/High) gates IRM alert generation;
  the IRM *severity + risk score* then drives triage — two different things.
- **Source-fetch note:** CISA .gov PDFs return HTTP 403 to automated fetch; several CISA quotes
  were verified via search-rendering + independent legal analyses, not direct PDF fetch. The
  Triage Agent / expanded-user-profile are **preview** Copilot features — frame as current-but-preview.
- **Refuted (0-3, don't use):** "the departing-users template *requires* the HR connector"
  (it's HR connector **or** Entra account-deletion), and a template-naming/trigger claim.

## Open (round 5)
- Verify `T1530` / `T1074` / `T1052` / `T1114` id+name at attack.mitre.org (this pass's MITRE gap).
- Human-confirm the CISA Jan-2026 "Assembling a Multidisciplinary Insider Threat Management Team"
  verbatim quotes against the PDF.
- Cross-vendor benign-TP for Splunk ES / Netskope / Zscaler (still unknown from round 3).

## Key sources (primary unless noted)
Microsoft Learn: Insider Risk Management (overview, -activities, -policy-templates, -configure,
copilot-triage-irm-agent) · CISA *Insider Threat Mitigation Guide* + *Assembling a
Multidisciplinary Insider Threat Management Team* · MITRE ATT&CK T1078 / T1567 (verified round 2).
