# SOC Tier-1 cases — research round 2 (the four deferred archetypes)

> Second research pass (2026-06-28) resolving **Open Question #3** of
> [`soc-tier1-research.md`](./soc-tier1-research.md): verified procedural detail for the
> four case types round 1 named but could not ground — **phishing, impossible-travel /
> MFA-fatigue, malware / EDR, data exfiltration**. Same bar as round 1 (this feeds a
> recruitment-credible game), same guardrail (analyst *read* + detection *patterns*
> only, never an operationally transferable technique).
>
> **Method:** deep-research harness — 5 search angles → 25 sources fetched → 118 claims
> → 25 taken to 3-vote adversarial verification → **24 confirmed (all 3-0), 1 killed.**
> Every surviving claim is anchored to a **primary** source (Microsoft Learn / Entra /
> Defender, CISA SCuBA, MITRE ATT&CK) — no blog/recruiter source is load-bearing. No
> salary/labor figures asserted (round 1 refuted them all).

## 0. The headline win — "same detection, opposite verdict" is now vendor-canon

The game's central mechanic (TP / FP / **Benign-TP**) is not our invention — it is the
real taxonomy three Microsoft products ship:

- **Defender for Endpoint** — analysts classify an alert as **True positive /
  Informational, expected activity / False positive**, where *"Informational, expected
  activity"* explicitly captures **simulated or authorized** activity (Determination
  sub-values include *Security test* and *Line-of-business application*).
- **Defender for Cloud Apps** — verbatim three-verdict scheme: **True positive (TP)** =
  confirmed malicious · **Benign true positive (B-TP)** = "suspicious but not malicious,
  such as a penetration test or other authorized suspicious action" · **False positive
  (FP)** = nonmalicious. Its per-detection docs give *both* verdicts for the identical
  trigger (e.g. "Multiple failed login attempts": TP = brute force vs B-TP = authorized
  security/pen test).
- **Entra ID Protection** — dispositions are **confirmed compromised / confirmed safe /
  dismiss risk** (dismiss ≈ B-TP, e.g. a known pen test).

> This is the strongest external validation we have: a Tier-1 analyst on the Microsoft
> stack literally makes the three-way call the game is built around, and the B-TP =
> "authorized attack" case (our `soc-auth-pentest` bridge) is Microsoft's own example.

## 1. Phishing triage  *(VERIFIED but THIN — expand before claiming "comprehensive")*

- **Trigger:** a user-reported email, or one flagged by the mail gateway / Defender for Office 365.
- **The "which header answers which question" model (CISA, primary):** SPF and DKIM let a
  sending domain *"watermark"* its mail so unauthorized (spam/phishing) mail is easy to
  detect — **SPF** authenticates the sending IP against the domain's authorized senders;
  **DKIM** authenticates the signing (`d=`) domain and message integrity; **DMARC**
  governs **disposition** (what the recipient should do when SPF/DKIM fail) and enforces
  **From-header alignment**.
- **Aha (malicious):** failed / misaligned SPF-DKIM-DMARC on a message impersonating a
  trusted domain; a look-alike sender domain; a credential-harvesting landing page behind
  the link (described as a *pattern*, never built).
- **Aha (benign/FP):** an authenticated, aligned message from a reputable sender
  (false-positive user report) — **or a sanctioned phishing-simulation** (Benign-TP:
  the email *is* phishing-shaped, but it's the org's own security-awareness campaign).
- **Decision:** real phish → escalate (block sender/URL, hunt for other recipients);
  authenticated newsletter the user over-reported → close FP; sanctioned simulation →
  close Benign-TP.
- **Pedagogical caveat to encode:** the visible *From-header* check is technically
  **DMARC alignment**, not raw SPF/DKIM. And **authentication proves a domain authenticated
  *itself*, not that a message is safe** — an attacker-owned look-alike can pass its own
  SPF/DKIM, and sanctioned simulations are often allow-listed while *failing* auth. So the
  decisive tells are **From-alignment + look-alike domain + the landing page (+ campaign
  register for benign)**, never raw pass/fail.
- **Learn-for-real:** MITRE **T1566 Phishing** *(real, but NOT independently verified in
  this pass — see caveats)*; LetsDefend "Phishing Email Analysis"; the Authentication-
  Results header.

## 2. Impossible travel / MFA fatigue  *(VERIFIED — richly, Microsoft primaries)*

- **Trigger / detection source:** **Microsoft Entra ID Protection** sign-in / user risk
  detections. Each named detection maps to a real `riskEventType` queryable in Microsoft
  Graph:
  - **Atypical travel** = `unlikelyTravel` (Entra-native, computed **offline**)
  - **Impossible travel** = `mcasImpossibleTravel` (sourced from Defender for Cloud Apps)
    — *Atypical and Impossible travel are DISTINCT detections from different engines; do not conflate.*
  - **Anonymous IP** = `anonymizedIPAddress` · **Password spray** = `passwordSpray`
  - **Malicious IP address** = `maliciousIPAddress` · **Leaked credentials** = `leakedCredentials`
  - **User reported suspicious activity** = `userReportedSuspiciousActivity` (the MFA-fatigue signal)
- **Data sources (the three reports):** **Risky sign-ins** (impossible/atypical travel,
  anonymous/malicious IPs), **Risky users** (leaked-credential accounts, suspicious
  behavior), **Risk detections** — in the Entra admin center or via Graph. Sign-in-log
  fields to validate normality: **Application, Device (registered/compliant?), Location,
  IP address, User-agent string.**
- **Aha (malicious):** confirmed-illegitimate sign-in — anonymized IP, unregistered
  device, location/agent outside the user's pattern, often paired with a `leakedCredentials`
  or `passwordSpray` signal.
- **Aha (benign/FP):** the IP/location is legitimate — the user **uses that IP in the scope
  of their duties**, **recently travelled** there, or the range is a **sanctioned VPN**
  (then add it to *Named locations*). The Atypical-travel algorithm is computed offline,
  **deliberately suppresses VPNs and locations regularly used by other org users**, and has
  an initial **learning period of the earliest of 14 days or 10 logins** (early FPs expected).
- **MFA fatigue / bombing:** `userReportedSuspiciousActivity` fires when a user **denies an
  MFA prompt and reports it suspicious** (requires the tenant's *Report suspicious activity*
  feature on). `passwordSpray` fires **only when the attacker successfully validates a
  password** — unsuccessful sprays generate **no** detection, and it signals **password
  compromise, not resource access**. Named mitigation (CISA): configure Microsoft
  Authenticator to show **login-context / number-matching** to cut MFA-fatigue compromises.
- **Decision (3-way, verbatim):** **confirmed compromised** (TP → block/disable account +
  force password reset, revoke sessions) / **confirmed safe** (FP → add VPN to named
  locations) / **dismiss risk** (Benign-TP, e.g. a known pen test). **Remediation is
  RBAC-gated → literal Tier-1 authority is org-dependent.**
- **MITRE (VERIFIED):** **T1621** Multi-Factor Authentication Request Generation;
  **T1078** Valid Accounts / **T1078.004** Cloud Accounts (CISA SCuBA MS.AAD.2.3 maps
  high-risk-sign-in blocking to these).
- **Learn-for-real:** MITRE T1621 / T1078 pages; Entra ID Protection investigate-risk docs;
  LetsDefend / Blue Team Labs Online identity-compromise exercises.

## 3. Malware / EDR endpoint  *(VERIFIED — Defender primaries)*

- **Trigger / detection source:** **Microsoft Defender for Endpoint** AV or behavioral alert.
- **Data source:** the **AlertEvidence** table in Advanced Hunting — filter
  `DetectionSource == "Antivirus"` and `ServiceSource == "Microsoft Defender for Endpoint"`
  to retrieve real columns **DeviceName, DeviceId, Title, AlertId, Timestamp** (process-tree
  / quarantine context lives in linked evidence tables).
- **Classification (the engine):** **True positive / Informational, expected activity /
  False positive.** "Informational, expected activity" = simulated/authorized (sub-values
  *Security test*, *Line-of-business application*). A **false positive** is "a benign
  entity wrongly detected as malicious"; a **false negative** is a missed real threat.
- **Aha (malicious):** known-bad file + suspicious lineage/behaviour + persistence (run
  key / scheduled task) + outbound C2.
- **Aha (benign/FP):** a flagged **security-test / red-team tool** run during an authorized
  engagement, or a **line-of-business app** misdetected (Benign-TP / "informational") — vs a
  **genuinely benign tool wrongly flagged** (FP).
- **Decision (disposition, verbatim):** accurate-malicious → **assign & investigate**
  (escalate to T2/IR); accurate-but-benign → **classify True positive, then suppress**;
  false positive → **classify FP, suppress, create an indicator, submit the file to
  Microsoft.** Containment actions (mostly **reversible** — restore a quarantined file from
  the Action Center; Live Response actions cannot be undone): quarantine a file, remove a
  registry key, kill a process, stop a service, disable a driver, remove a scheduled task.
- **MITRE:** **T1204** User Execution and persistence techniques apply *(real, but NOT
  independently verified in this pass)*.
- **Learn-for-real:** MITRE ATT&CK; LetsDefend EDR / malware-analysis exercises.
- **REFUTED (0-3, do NOT use):** the claim that a Tier-1 can take *Restart / Quick Scan /
  Full Scan / Sync / Update-signatures* actions on the Intune-integrated "Active malware" tab.

## 4. Data exfiltration  *(VERIFIED — MITRE + Defender for Cloud Apps primaries)*

- **Trigger / detection source:** a **DLP** policy hit, a **proxy/firewall egress** anomaly,
  or a **Defender for Cloud Apps** activity alert.
- **MITRE (VERIFIED):** **T1567.002** *Exfiltration to Cloud Storage*, a sub-technique of
  **T1567** *Exfiltration Over Web Service* (tactic **TA0010** Exfiltration). Adversaries
  exfiltrate to cloud-storage services (MITRE-named: Dropbox, Google Drive, OneDrive, MEGA,
  Amazon S3) **rather than over their primary C2**, using services the host already talks to
  as cover.
- **Aha (malicious — behaviour/IOA, not just an IOC):** an **unusual process** (e.g.
  `powershell.exe`, `excel.exe`) accessing **large local files** then initiating **HTTPS POST**
  to a cloud-storage domain; tools like `curl` / `wget` / `rclone` uploading to cloud-storage
  endpoints; off-hours; classified data.
- **Aha (benign/FP):** a legitimate **scheduled backup**, a **sanctioned cloud-sync client**
  (corporate OneDrive), or an **authorized red-team** exercise → **Benign-TP**; a DLP
  pattern-match on a file that doesn't actually contain sensitive data → **FP**.
- **Decision:** confirmed exfil → escalate (IR + isolate/disable as authority allows);
  sanctioned backup/sync with a change ticket → close Benign-TP; mis-matched DLP regex →
  close FP (and tune the policy).
- **Learn-for-real:** MITRE T1567.002 page; LetsDefend / TryHackMe exfiltration labs.

## 5. Caveats (must respect — these gate how content is presented)

- **MITRE verification is partial.** **VERIFIED 3-0 against MITRE/CISA primaries:**
  `T1621`, `T1078`/`T1078.004`, `T1567`/`T1567.002`. `T1566` (Phishing), `T1204` (User
  Execution) and `T1547.001` were **since VERIFIED 3-0 in [round 3](./soc-tier1-cases-round3.md)**
  — so the phishing and EDR cases are cleared. **Still NOT verified:** `T1530` (Data from Cloud
  Storage) — not used in shipped content (exfil uses the verified `T1567.002`). Re-verify `T1530`
  before any use.
- **Phishing is under-covered** — it rests on a single confirmed claim (CISA SPF/DKIM/DMARC).
  Author phishing cases conservatively and anchored on the email-auth model; a dedicated
  third pass should verify `T1566.*` and the header-analysis read (Received chain,
  Return-Path vs From mismatch, Authentication-Results parsing).
- **Vendor-specificity.** The identity/EDR detail is Microsoft-stack (`riskEventType`
  values, the "Manage alert" set, the TP/B-TP/FP scheme are Microsoft taxonomy). Equivalents
  in Proofpoint / CrowdStrike / Okta / Splunk differ. In-game labels should read as
  "Microsoft-style" or be kept generic if cross-vendor neutrality matters.
- **Containment authority is org-dependent.** Entra remediation and EDR isolate/quarantine
  are RBAC-gated; keep the "org-dependent containment" hedge in content (the game already
  models this via the disposition choice).
- **Time-sensitivity.** Microsoft Learn pages update often; detection names drift
  ("Malicious IP address" vs colloquial "malware-linked IP"; CISA `MS.AAD.3.5` v1→v2).
  Re-verify `riskEventType` names and CISA policy IDs before each content release.

## 6. Open questions (round 3)

1. Phishing: verify `T1566`/`.001`/`.002`/`.003` IDs+names and the full header-analysis read
   from a primary/vendor playbook; source the sanctioned-simulation B-TP (KnowBe4 / Microsoft
   Attack Simulation Training).
2. Confirm `T1204`, `T1530`, `T1048`, `T1547` as the correct primary mappings for their archetypes.
3. Defender for Endpoint **device isolation** primitives + reversibility + RBAC role (distinct
   from the AV remediation actions already verified) — to set realistic T1 vs T2 containment.
4. Cross-vendor mapping (Proofpoint / CrowdStrike / Okta / Netskope) so the game can offer
   vendor-neutral framing.

## Key sources (all primary unless noted)
CISA *Enhance Email & Web Security* (SPF/DKIM/DMARC) · CISA SCuBA M365/Entra baseline
(MS.AAD.* → MITRE) · Microsoft Learn: Entra ID Protection (risks, investigate-risk, guide),
MFA additional-context · Defender for Endpoint (false-positives-negatives, review-detected-
threats), AlertEvidence table · Defender for Cloud Apps (investigate-anomaly-alerts,
anomaly-detection-policy) · MITRE ATT&CK T1621 / T1078 / T1078.004 / T1567 / T1567.002.
