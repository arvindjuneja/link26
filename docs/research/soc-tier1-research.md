# Entry-level (Tier 1) SOC Analyst — research for the career-sim direction

> Deep, multi-source, adversarially-verified research (2026-06-23) to ground the
> blue/SOC "career path" seat in the real role. Accuracy matters here more than on
> the arcade-hacker side, because the long-term plan ties this to real recruitment.
> Method: 5 search angles → 23 sources → 99 claims → 25 verified by 3-vote adversarial
> check (19 confirmed, 6 refuted). Vendor/recruiter blogs are consensus-grade, not
> primary labor studies — treated accordingly. **Verdict: the direction is credible
> and, crucially, the real job has a clean game loop at its core (see §3).**

## 1. The career ladder  *(verified, high confidence)*
- **Tier 1** — monitoring, alert triage, initial enrichment, follow playbooks, escalate.
- **Tier 2** — validate/deep investigation, multi-source correlation, malware analysis, containment/remediation.
- **Tier 3** — advanced investigations, proactive threat hunting, detection engineering, forensics, mentoring.
- **Progression** ~1 tier / ~2 years; T1→T3 ≈ 4–6 years, **not automatic** (many stall T1→T2; ~18-month avg tenure; ~64% reportedly consider quitting — burnout is real). High performers fast-track in 12–18 months.
- **Branches off the ladder**: Incident Response, Threat Intelligence (GCTI), Red Team (OSCP), Detection Engineering, Security Architecture, GRC/Compliance (CISM/CISSP). **Management track**: T1 → T2 → Team Lead → SOC Manager → Director → CISO.
- **Entry cert**: **BTL1 (Blue Team Level 1)** is verified as explicitly aimed at entry-level analysts / students / career-changers (0–2 yrs), maps to NICE "Cyber Defense Analyst." Security+ / CySA+ are commonly named but were **not** independently verified here.

## 2. The Tier 1 day-to-day  *(verified)*
- **Alert triage dominates the shift.** ~20–50 (up to 40–100) alerts/shift, **most of them false positives.**
- 24/7 shift/rotation. Canonical day: 08:00 handover/briefing → 08:30 alert analysis → 15:00 documentation/ticket updates. Continuous monitoring throughout.
- Per alert: first-pass *what / where / when* → classify → enrich with IOCs → ticket → escalate ambiguous/true threats to Tier 2. Basic containment (e.g., block an IP) is **org-dependent** — sometimes T1 (runbook/SOAR-driven), sometimes reserved for T2.

## 3. THE CORE GAME LOOP — verified and citable
Tier 1's decision on every alert is a **three-way classification** (confirmed against Microsoft Defender/Sentinel docs):
- **True Positive** — genuine threat.
- **False Positive** — alert fired, no threat (the bulk of the queue).
- **Benign True Positive** — detection is *correct* but the activity is *authorized* (e.g., a sanctioned pentest, an approved tool).

This is the game's central mechanic: each case = gather evidence → make the call (TP / FP / Benign-TP) → escalate or close. It is judgment/deduction, **not** adrenaline — exactly the "developmental, not emotional" loop we want.

**Design bridge to the other seat:** a *Benign True Positive* is literally "an attack the analyst correctly detected, but it was authorized." That's the same-board-two-seats idea made concrete — a player's own red-team run, seen from the blue chair, is a Benign-TP. The two seats can share one world.

**Core mental model** *(medium confidence, single teaching source)*: "**which log answers which question**" — a first-response checklist mapping a threat type to the data source that answers it (auth → 4624/4625/4672; SSH → auth.log; network anomaly → firewall; malware → AV/EDR; C2 → DNS; impossible travel → VPN). Frame as the analyst's *starting move / mental index*, then real triage is multi-source correlation.

## 4. Verified "cases" (game content: trigger → logs → aha → decision → learn-for-real)
Only three case types surfaced **verified** procedural detail. These are the strongest first content.

**A. Encoded / suspicious PowerShell**  *(high confidence — the richest, teaches the central lesson)*
- Trigger: alert on `-enc` / `-EncodedCommand` / anomalous PowerShell.
- Logs/signals: Windows Events 4104 (script-block), 4103 (module), 4688 (process create), 7045 (service install), 4698 (scheduled task) + EDR process tree/lineage, file/registry writes, network connections + DNS/proxy logs.
- **Aha (malicious):** parent process is an Office app / browser / script interpreter; decoded content has `IEX` + `DownloadString` or reflective PE load; an immediate outbound connection after execution.
- **Aha (benign):** parent is a known IT tool (SCCM, Intune, Ansible/WinRM, RMM) or there is a valid change ticket.
- Decision: encoding alone ≠ threat → decode + read parent/behaviour/correlated signal before escalating. **This is the game's thesis: surface indicators need context.**
- Learn-for-real: MITRE ATT&CK **T1059.001**, Sysmon/EDR process-tree analysis, LetsDefend "Detecting Malicious PowerShell."

**B. Authentication — brute-force / suspicious login / privilege escalation**  *(high confidence)*
- Trigger: failed/successful logon anomalies.
- Logs: Windows Events **4624** (success, incl. Source Network Address), **4625** (failure — brute-force/spray), **4672** (special privileges assigned).
- **Aha:** 4672 firing for an account that shouldn't be admin/service; or a burst of 4625 followed by a 4624 from an anomalous source/time.
- Decision: correlate source IP / time / account; escalate confirmed access.
- Learn-for-real: Windows Security event-log analysis; Splunk/Sentinel auth detections.

**C. Beaconing / C2 over DNS**  *(high confidence — academic sources)*
- Trigger: anomalous DNS query patterns.
- Logs: DNS logs.
- **Aha:** regular/high-frequency timed queries (beaconing); long high-entropy domains (DGA); rare TLDs (.xyz/.me/.biz); repetitive NXDOMAIN bursts.
- Learn-for-real: DNS log analysis, entropy/DGA detection, MITRE ATT&CK **T1071.004**.

> The other cases in the brief — phishing triage, impossible-travel / MFA-fatigue, malware/EDR endpoint, data-exfil, account lockout, insider — are real and standard but did **not** surface verified procedural detail in this pass. They need a focused second research round before becoming content.

## 5. Tools & vocabulary  *(for credibility/flavour)*
- SIEM (Splunk, Microsoft Sentinel, Elastic), EDR (CrowdStrike, Defender), SOAR, ticketing, MITRE ATT&CK, playbooks/runbooks, threat-intel feeds.
- **IOA vs IOC** *(verified, complementary — NOT a clean temporal binary)*: an **IOA** is a behavioural pattern of an attack in progress (tool-agnostic, intent/TTPs, good vs fileless/LOLBins). An **IOC** is a forensic artifact/indicator. Mature stacks match both concurrently against live telemetry. (The over-narrow "IOC = proof of past breach, used only reactively" was **refuted 0-3** — don't phrase it that way.)

## 6. Optional game scoring mechanic  *(inspiration only — NOT an industry standard)*
A single source uses numeric triage bands: 0–20 = likely benign (close/whitelist); 21–49 = suspicious, escalate to T2 **without** isolating; 50+ = high-confidence malicious, escalate to IR (possible host isolation). The *behaviour* is standard; the *numbers* are proprietary to one article. Use as the game's **own** confidence/scoring system, never cited as real-world fact.

## Caveats (must respect)
- **NO salary data is verified.** Every concrete pay band — EU, Poland (PLN), US — was **refuted** (0-3 / 1-2). The game must not present pay figures as fact; if money is shown, label it illustrative/in-game.
- **"Tierless SOC" / AI-automation trend (2025-26)** is reshaping T1 (automation absorbing some triage). It doesn't refute current tier definitions but means "pure manual triage Tier 1" is the *conventional baseline* with a shelf life.
- Basic containment (block-IP) is genuinely **org-dependent** T1 vs T2 → treat as configurable.
- Career-structure findings rest on vendor/recruiter blogs (consensus-grade, not primary labor studies).

## Open questions (worth a second pass)
1. **Verified PL/EU salary bands** from a primary labor-market source (No Fluff Jobs / Bulldogjob / Hays / Robert Half / Eurostat) — needed for the recruitment/job-offer tie-in.
2. **Verified cert coverage** (Security+, CySA+, BTL1 domains) so "learn this for real" pointers are accurate.
3. **Procedural detail** for the remaining cases (phishing, impossible-travel/MFA-fatigue, malware/EDR endpoint, exfil, account lockout, insider). → **partly resolved 2026-06-28 in [`soc-tier1-cases-round2.md`](./soc-tier1-cases-round2.md)** for phishing, impossible-travel/MFA-fatigue, malware/EDR, and exfil (account-lockout + insider still open).
4. **How gamified platforms structure their loops** (TryHackMe SOC paths, LetsDefend, Blue Team Labs Online, HTB) and what makes T1 feel engaging (deduction) vs tedious (alert fatigue) — section 5 of the brief produced no surviving claims.

## Key sources
Microsoft Learn (Defender/Sentinel alert taxonomy, Windows event IDs) · CrowdStrike / Splunk / Wiz / Huntress (IOA vs IOC) · CyberDefenders (encoded-PowerShell playbook, triage process) · USENIX / arXiv (DGA/NXDOMAIN, DNS C2) · Security Blue Team / centri.org (BTL1) · soclab.wust.edu (log-to-question checklist) · nFlo, Dropzone, Wiz, Optima Europe (tiers/timelines/day-in-the-life — consensus blogs).
