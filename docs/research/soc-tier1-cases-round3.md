# SOC Tier-1 cases — research round 3 (MITRE verification · account-lockout · cross-vendor)

> Third research pass (2026-07-04). Three goals: (A) **verify** the MITRE ids round 2 left
> unconfirmed, (B) ground the **account-lockout** archetype (and attempt **insider**),
> (C) check whether the TP/FP/**Benign-TP** scheme generalises **cross-vendor**. Same bar
> and guardrail as rounds 1–2 (analyst *read* / detection *patterns* only).
>
> **Method:** deep-research harness — 3 angles → 12 sources → 53 claims → 25 to 3-vote
> adversarial verification → **24 confirmed, 1 killed.** MITRE/Sentinel/Falcon/Okta rest on
> primary docs; account-lockout benign-causes and Proofpoint rest on consensus-grade blogs
> (flagged). No salary figures asserted.

## A. MITRE ATT&CK — the round-2 unverified ids, now CONFIRMED (3-0 vs attack.mitre.org)

| ID | Canonical name (verbatim) | Status |
|---|---|---|
| **T1566** | Phishing *(Initial Access)* | ✅ verified |
| **T1566.001** | Spearphishing Attachment | ✅ verified |
| **T1566.002** | Spearphishing Link | ✅ verified |
| **T1566.003** | Spearphishing via Service | ✅ verified |
| **T1204** | User Execution | ✅ verified |
| **T1204.001** | Malicious Link | ✅ verified |
| **T1204.002** | Malicious File | ✅ verified |
| **T1547** | Boot or Logon Autostart Execution *(Persistence, Priv-Esc)* | ✅ verified |
| **T1547.001** | Registry Run Keys / Startup Folder | ✅ verified |

- **So the shipped cases are cleared:** phishing (`soc-phish-*`) → **T1566** verified;
  EDR malware (`soc-edr-*`) → **T1204** verified. Round 2's "not independently verified" flag
  for these is resolved.
- **Still NOT verified: `T1530` (Data from Cloud Storage)** — no surviving claim this pass;
  don't present as verified. (We don't currently use it; the exfil cases use **T1567.002**,
  verified round 2.) `T1531` (Account Access Removal) and `T1110` sub-precision also weren't
  re-checked here — but **T1110 "Brute Force"** was verified in round 1, so it's safe to use.
- **Time-sensitivity:** the families have GROWN — T1566 now has **.004 Spearphishing Voice**;
  T1204 now has **.003–.005**. Never state that ".001–.003 are the *only* sub-techniques."

## B. Account lockout  *(VERIFIED — Microsoft primary + consensus)*

- **Trigger / read:** **Windows Security Event ID 4740** — generated **every time** an account
  is locked out (on DCs, member servers, workstations), under the *Audit User Account
  Management* subcategory. The **"Caller Computer Name"** field is *defined* as the source
  machine of the failing logon — **but it is frequently BLANK/unreliable** when the source is
  outside AD (a mobile device on ActiveSync, cached creds, a mapped drive, a scheduled task, a
  service account). So it's the *intended* source indicator, not a source of truth — analysts
  **correlate Kerberos 4771 / NTLM 4776** to find where the bad passwords actually come from.
- **Aha (malicious):** repeated lockouts driven by a **brute-force / password-spray** from an
  anomalous source; a **compromised or attacker-abused** account; lockouts targeting many
  accounts (denial-of-access pattern). Correlate 4771/4776 to an external / unexpected origin.
- **Aha (benign / FP — the #1 real cause):** **stale / cached credentials being
  auto-resubmitted after a password change** — a phone syncing Exchange/Wi-Fi with a saved
  password, a mapped drive, a service account or scheduled task with an outdated credential, an
  RDP/desktop session with a cached old password. The 4771/4776 source correlates to the user's
  **own** device/service, internal. *(Consensus-grade, not a single Microsoft primary — do NOT
  attach the oft-quoted "~80%" figure; present as "the common benign cause.")*
- **Aha (benign true positive):** an **authorized penetration test / red-team** spray that
  happens to trip lockout thresholds — the detection is correct (real spray), but a signed RoE
  covers it → Benign-TP, not an incident.
- **Decision:** attack from an anomalous source → escalate (T2/IR, reset + investigate the
  compromise); stale-cred misconfig on the user's own device → close FP + help update the
  stored credential (and tune); sanctioned pentest with RoE → close benign.
- **MITRE:** **T1110 Brute Force** (verified round 1) for the credential attack. *(T1531 "Account
  Access Removal" — lockout-as-objective — was NOT verified this pass; don't cite it yet.)*
- **Learn-for-real:** MITRE T1110; Microsoft *event-4740* doc; the 4771/4776 correlation habit.
- **REFUTED (0-3, do not use as framed):** a blog claim that **4625** "is logged on the
  client/source computer and gives the reason + Logon Type." Ground any 4625 detail on a
  Microsoft primary before use. (4625 = *An account failed to log on* is fine; the "logged on
  the client" framing failed.)

## B2. Insider threat — **GAP, not researched this pass**

No claim survived verification for the insider-threat archetype (DLP/UEBA triggers, the
intent/authorization/role discriminator, HR-legal escalation, MITRE mappings). **Do NOT author
insider cases yet** — it needs a dedicated pass against primary DLP/UEBA docs. Deferred to round 4.

## C. Cross-vendor — does TP / Benign-TP / FP generalise?

- **Microsoft Sentinel** — the ONE verified vendor with an explicit benign-true-positive
  disposition. Closing an incident **requires** one of exactly five: *True Positive - suspicious
  activity · **Benign Positive - suspicious but expected** · False Positive - incorrect alert
  logic · False Positive - incorrect data · Undetermined.* Incidents also inherit MITRE
  tactics/techniques, severity, status, entities from their alerts. **Another primary-source
  validation of the game's core mechanic** (alongside round 2's Defender for Cloud Apps TP/B-TP/FP).
- **CrowdStrike Falcon** — `true_positive` / `false_positive` / `ignored`. **No benign class.**
- **Okta ITP** — a **low/medium/high risk-level** scale, not a TP/BP/FP verdict — but exposes
  rich **named signals** usable vendor-neutrally: *Suspected brute force attack · Suspicious
  login using a valid sprayed password · Breached credential detected · Okta Threat Intelligence
  · Suspicious app access* (12 total). Its Entity Risk Policy drives automated actions, not verdicts.
- **Proofpoint** — *Safe / Suspicious / Malicious* threat-verdict (blog-grade), not an analyst disposition.
- **Splunk ES / Netskope / Zscaler** — no surviving claim; their benign-TP status is **unknown**, don't assert.

> **Design takeaway:** named triage **signals** are cross-vendor (keep them realistic and
> vendor-flexible), but the **"benign positive" disposition** is a **Microsoft-Sentinel/Splunk-style**
> concept — present it as that, not a universal industry standard. Our in-game 4-disposition call
> (close-FP / close-benign / escalate-T2 / escalate-IR) maps cleanly onto Sentinel's scheme.

## Caveats / open (round 4)
- Verify **T1530** id+name, and **T1531** / T1110 sub-precision for lockout, against attack.mitre.org.
- Research the **insider-threat** archetype fully (primary DLP/UEBA), incl. the escalate-to-HR/legal path.
- **Splunk ES / Netskope / Zscaler** benign-TP-equivalent — unknown.
- Ground **Event 4625** detail on a Microsoft primary (the blog framing was refuted).
- MITRE families expand over time — re-verify "complete sub-technique" lists before shipping them.

## Key sources (primary unless noted)
attack.mitre.org T1566 / T1204 / T1547 (+ subs) · Microsoft Learn *event-4740*, Sentinel
*investigate-cases* / *investigate-incidents* · CrowdStrike Falcon developer docs (detections,
alerts API) · Okta ITP *overview* / *detections* · activedirectorypro.com (lockout causes —
consensus blog) · Proofpoint blog (Safe/Suspicious/Malicious — consensus blog).
