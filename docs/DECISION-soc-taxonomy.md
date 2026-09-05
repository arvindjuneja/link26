# DECISION — SOC verdict taxonomy (FP vs Benign-TP)

**Decided 2026-09-05.** Closes the `soc-taxonomy-decision` FLAG opened by the 2026-07-11 playtest ([`PLAYTEST-lookandfeel.md`](PLAYTEST-lookandfeel.md)). Condensed from the full decision memo; inputs were 3 primary-source research passes, a per-case audit of all 24 cases under both candidate definitions, and a 3-lens adversarial verification of every proposed edit.

---

## 1. Decision

**DEF-A is canonical: "did the attack behaviour the rule hunts for actually happen?"**

**No case truth changes. The bug was the copy, not the cases.** `soc-auth-reset` (rkhan) stays **False Positive**. The playtester was right that the game taught one definition in the intro and graded by another — the fix is to make the intro, the buttons, the engine strings and the case copy all state DEF-A.

The rival definition (DEF-B: "FP = the activity never occurred at all; anything that did occur and isn't malicious is a Benign-TP") loses on three counts:

- **Churn 0 vs 7.** Under DEF-A, 0 of 24 shipped truths and 0 tests change. Under DEF-B all 5 hand-authored FPs retag to B-TP, plus 2 FP-remedy pointers become wrong by construction.
- **It empties the FP class.** 0 of 24 FPs ⇒ `close-false-positive` becomes unreachable in all four playable shifts, and the four shift-mix invariants (`app/lib/soc/cases.test.ts:105 / 127 / 147 / 160`, each asserting a shift covers all three verdicts) fail.
- **It has no home for the commonest real FP.** Sentinel's `IncorrectAlertLogic` — real, non-malicious activity the rule's logic wrongly flagged — is exactly DEF-A's FP and has no case under DEF-B.

### The six load-bearing primary sources

1. **Entra ID Protection** — the operational split stated outright: *"Confirm sign-in safe – This action confirms the sign-in is a false positive. Similar sign-ins shouldn't be considered risky in the future."* vs *"Dismiss sign-in risk – This action is used for a benign true positive. This sign-in risk we detected is real, but not malicious, like those from a known penetration test… Similar sign-ins should continue being evaluated for risk going forward."* — FP ⇒ stop flagging; B-TP ⇒ keep the detection. <https://learn.microsoft.com/en-us/entra/id-protection/howto-identity-protection-risk-feedback>
2. **Sentinel REST API** — canonical sample body `"classification": "FalsePositive", "classificationComment": "Not a malicious activity", "classificationReason": "IncorrectAlertLogic"`. <https://learn.microsoft.com/en-us/rest/api/securityinsights/incidents/create-or-update>
3. **Splunk ES 8.5 dispositions** — *"False Positive - Incorrect Analytic Logic: Finding was initially suspicious but then classified as harmless due to incorrect analytic logic."* <https://help.splunk.com/en/splunk-enterprise-security-8/administer/8.5/investigations/configure-dispositions-for-findings-in-splunk-enterprise-security>
4. **Defender XDR alert-classification playbooks** — the defining pair: B-TP = *"suspicious but not malicious activity, such as a penetration test or other authorized suspicious action"*; FP = *"An alert on a nonmalicious activity"*. <https://learn.microsoft.com/en-us/defender-xdr/alert-classification-playbooks>
5. **Google SecOps** — *"Benign Positive: A correct detection of authorized activity (for example, a sanctioned pentest)… False Positive: An incorrect detection caused by logic errors."* <https://docs.cloud.google.com/chronicle/docs/soar/investigate/working-with-cases/add-new-case-close-root-cause-admin>
6. **MITRE T1110** — the technique is an adversary act: *"Without knowledge of the password… an adversary may systematically guess the password."* A user re-typing his own new password is not T1110, so a rule firing without a source or logon-type condition has incorrect logic. <https://attack.mitre.org/techniques/T1110/>

---

## 2. The player-facing definition

**Intro** (`app/components/soc/SocConsole.tsx`, ShiftIntro):

> You're the Tier-1 analyst. One question decides every alert on that queue: **did the attack behaviour the rule hunts for actually happen?** If it didn't, and ordinary activity only looked like it, that's a **False Positive**; if it did but a pentest, change ticket or known tool sanctioned it, that's a **Benign True Positive**; if it did and nothing sanctioned it, that's a **True Positive**.

**Mnemonic:** Didn't happen → False Positive. Happened + sanctioned → Benign-TP. Happened + unsanctioned → True Positive.

**Heuristic** (coaching bubble only, `app/components/soc/SocOnboarding.tsx`): FP means the rule's logic is wrong — change what it fires on. Benign-TP means the rule is right — scope an exception and leave the logic alone.

"Sanctioned" is anchored to an **artifact** (RoE, change ticket, known tool, approved drill) — never to "a legitimate user did it", which is the exact slippage that made a legitimate user's typos read as "authorized". The heuristic is deliberately *scoped exception vs change the logic*, not "never tune": Defender's own feature is named **alert tuning**, and a hard "never tune" would contradict `soc-exfil-backup`'s own text.

**Button subtitles** (`SocConsole.tsx` `DISPOSITION_META`):

| Button | OLD | NEW |
|---|---|---|
| `close-false-positive` | `a false alarm — no real threat` | `didn't happen — the rule misread it` |
| `close-benign` | `correct detection, sanctioned activity` | `it happened — and it was sanctioned` |

"No real threat" is equally true of every B-TP, so the FP button's stated criterion could not separate the two; "correct detection" is the DEF-B ambiguity in miniature ("the rule fired" vs "the behaviour occurred").

---

## 3. What changed (copy only — no truths, no dispositions, no types)

| File | Edits | Substance |
|---|---|---|
| `app/lib/soc/cases.ts` | 14 | rkhan `why` (credential-stuffing → password-guessing; "fired on a real pattern" → "what it hunts for never happened"); rkhan `b2-ticket` label/detail ("No relevant change" over a detail naming CHG-2270 → "Reset — not a grant" / "it explains the failures; it authorizes nothing"); `soc-ps-patch` concept (a change ticket separates B-TP from **TP**, not from FP); `soc-id-vpn` concept + the shared `namedLocations` question (drop "sanctioned" from FP surfaces); `soc-lockout-stale` concept + `al2-ticket` detail ("timing, not authorization"); `soc-lockout-attack` ×2 (stop calling the FP sibling "the benign case"); `soc-exfil-backup` concept + pointer (tune → scoped exclusion); `soc-insider-migration` concept |
| `app/lib/soc/engine.ts` | 4 | the two mis-call outcome strings a player actually reads, plus 2 comments |
| `app/lib/soc/types.ts` | 3 | the `SocVerdict` / disposition comments that **seeded** the DEF-B player copy |
| `app/components/soc/SocConsole.tsx` | 4 | intro paragraph, 2 button subs, "false alarms" → "noise" |
| `app/components/soc/SocOnboarding.tsx` | 2 | coaching bubble = call prompt + mnemonic + heuristic |
| `app/lib/soc/handoff.ts` | 2 | burn-notice cleanup clause (§6) |
| `README.md` · `docs/GAME_DESIGN.md` · `docs/PLAYTEST-lookandfeel.md` | — | DEF-A wording, canonical-definition paragraph, FLAG resolved |
| `app/lib/soc/taxonomy.test.ts` | new | corpus-vs-definition invariant (§7) |

`types.ts:36` was the origin of the drift — the code comment seeded the player copy. Fixing it is what stops this recurring. Line 81 of `engine.ts` is the exact string the playtester saw after calling rkhan Benign; it said "the detection itself was wrong" while the debrief three lines later said "the rule fired on a real pattern". Both halves are fixed.

---

## 4. Rejected proposals

| Proposal | Why not |
|---|---|
| `soc-insider-baseline` MITRE `T1078` → `T1213` | T1213 answers "did it occur?" *yes* exactly as T1078 does; every FP in the pack tags what the rule hunts |
| `soc-insider-baseline` why/concept rewrites | Already DEF-A-clean; the proposed FP test mis-grades two B-TP siblings |
| rkhan `b2-help` demote to `supporting` | It's a `keySourceId` — the key source would vanish from the debrief that credits it |
| rkhan/B1 rule-threshold unification | Round-2+ pairs deliberately carry different rule strings; cosmetic |
| `soc-ps-patch` "file the exception; leave the rule alone" | Orphans a five-case B-TP motif and contradicts Defender's own "alert tuning" |
| Pointer relabels / MITRE prefixes | Graph enum maps the display label; MITRE-prefixed pointers are a TP-only convention (12/12 non-TP pointers omit it) |
| `soc-dns-cdn` trigger / alertTitle / evidence rewrites | Verdict leak into a pre-call evidence card; blurs the case's own discriminator |
| `soc-id-vpn` why rewrite ("never left the building") | Unsupported by any evidence card; the VPN implies the opposite |
| `soc-auth-bruteforce` concept rewrite | Priming premise is backwards (rkhan is alert 2, bruteforce alert 5); deletes the T1110.001 depth-vs-breadth tell |
| `soc-insider-departing` / `soc-insider-migration` rewrites | Create fresh contradictions with untouched siblings |
| `soc-exfil-cloud` / `soc-phish-harvest` keySourceIds changes | Convention break / archetype asymmetry; buys nothing |
| `soc-lockout-attack` trigger rewrite | Asserts a fact that appears in no evidence card in that case |
| burn-notice retag / per-technique scope model | Deferred — see §6 |

---

## 5. Sibling-pair discriminators (all 24 consistent under DEF-A)

| Archetype | Cases | The ONE discriminator |
|---|---|---|
| encoded-powershell | ps-cradle TP / ps-patch B-TP | Occurred in both. **Sanction artifact**: WINWORD.EXE + no change record vs `ccmexec.exe` under CHG-2291 |
| auth burst→success | auth-reset FP / auth-bruteforce TP / auth-pentest B-TP | **Did guessing occur?** Type-2 failures at the owner's own keyboard = no → FP. If yes, **RoE**: none → TP; CHG-2310 → B-TP |
| dns-c2 | dns-beacon TP / dns-cdn FP | **Did DGA beaconing occur?** Browser + one CDN parent + clean resolution + activity-driven timing = no → FP |
| phishing | phish-harvest TP / phish-sim B-TP | Phish delivered in both. **Campaign register**: no send to this user vs an active authorized run |
| identity | id-vpn FP / id-mfa TP | **Did a second party use the account?** Same registered device, only egress IP differs = no → FP |
| edr-malware | edr-loader TP / edr-test B-TP | Tool executed in both. **RoE**: none, non-IT user vs CHG-3120 naming tool + host |
| data-exfil | exfil-cloud TP / exfil-backup B-TP | Bulk egress in both. **Destination + standing change**: personal account, no ticket vs corporate tenant under CHG-2980 |
| account-lockout | lockout-stale FP / lockout-attack TP / lockout-pentest B-TP | **Did guessing occur?** Own phone + mapped drive replaying one known password = no → FP. If yes, **RoE**: none → TP; CHG-4130 → B-TP |
| insider-threat | insider-baseline FP / insider-departing TP / insider-migration B-TP | **Did the anomaly occur?** Within the user's own 90-day baseline = no → FP. If yes, **ticket + destination** |
| handoff (generated) | the-key B-TP / burn-notice B-TP / unsanctioned TP | Occurred in all three. **RoE only** — the generator has no FP branch |

Pattern holds 24/24: every FP is "the hunted behaviour did not occur"; every B-TP is "it occurred **and** a *named* sanction artifact covers it"; every TP is "it occurred and no artifact exists".

---

## 6. Honest dissent, residual risks, and the burn-notice note

**Two vendor texts genuinely cut the other way.** (a) **Defender for Identity** words FP literally as DEF-B: *"False positive (FP): A false alarm, meaning the activity didn't happen."* (<https://learn.microsoft.com/en-us/defender-for-identity/understanding-security-alerts>). It reconciles with DEF-A only by reading "the activity" as the alert's *named attack* — the natural reading given MDI names alerts as attacks and prescribes exclusion as the FP remedy on the same page, but it is a reading, not the text. (b) **Defender for Cloud Apps'** playbook for *Multiple failed login attempts* offers **no FP branch at all** and labels the closest analogue B-TP: *"B-TP (Password changed)… Recommended action: Dismiss the alert."* (<https://learn.microsoft.com/en-us/defender-cloud-apps/investigate-anomaly-alerts>) — the single strongest text for grading rkhan B-TP. It is undercut by the same page labelling untagged-VPN impossible travel and legitimately-performed volume anomalies **FP**, so the page is internally inconsistent. One refuter lens voted to grade rkhan and `soc-lockout-stale` as B-TP on exactly this basis. That dissent is real; it loses because DEF-B leaves `IncorrectAlertLogic` homeless, empties the FP class, and breaks the one thing every scheme agrees on — three verdicts must map to three different actions.

**Residual risks.**
- A Splunk- or MDCA-literate player arguing rkhan is B-TP is citing a real Microsoft page, not a misreading. Consider a codex footnote acknowledging the vendor split.
- **No `InaccurateData` FP case.** All five FPs are "incorrect alert logic". A telemetry-error case (duplicated forwarder, clock skew) would be the one FP both definitions agree on.
- **No "Undetermined" verdict.** Splunk, Sentinel and Google all ship one; the game forces a call. Fine for an arcade loop; the one structural divergence from every vendor scheme.
- The fix-vs-exception heuristic is **coaching-bubble only, by design**. If it ever migrates into case copy, `soc-exfil-backup`, `soc-edr-test` and `soc-insider-migration` must be reconciled first.

**Burn-notice scope exceedance — what was done.** `app/lib/soc/handoff.ts` marks the `burn-notice` run `authorized: true` with tradecraft including `log-wipe`, while the red campaign scopes that engagement to *"In scope: charon single manifest edit"* (`app/lib/game/campaign.ts:144`). Clearing the Security audit log (1102 / T1070.001) is a distinct, more destructive technique the RoE never grants. Because `acceptableDispositions` is `undefined` for authorized runs, a sharp player escalating it as out-of-scope is graded wrong — so the case teaches "blanket authorization covers everything", weaker tradecraft than "verify each action is in scope". Modelling per-technique scope needs changes on both seats (the red seat's `wipe logs` verb enforces no scope either), and the cheap fixes backfire: dropping `log-wipe` leaves the alert citing a 1102 with no evidence; flipping to TP breaks the shift's "authorization, not authorship" spine. **Applied instead — the cheapest safe option:** the generated RoE evidence card now appends, when the run's tradecraft includes `log-wipe`, *"Noisy cleanup (audit-log clear) is noted in the engagement record as an accepted side-effect."* — mirroring `soc-lockout-pentest`'s existing convention. No truth, disposition, type or test changes. Per-technique scope stays open.

---

## 7. Tests

Zero existing test updates required — no suite asserts on `why`, `learn.concept`, `learn.pointer`, `evidence.label`, `evidence.detail`, `DataSource.question`, `CallGrade.outcome`, or `DISPOSITION_META.sub`. The only prose assertions are length floors (`cases.test.ts:73-74`, `> 20`), which every new string clears.

New: `app/lib/soc/taxonomy.test.ts` pins the corpus against the class of drift that caused the FLAG — a case's `why` must never tell the player to reach a *different* verdict than its truth (an FP that calls itself a Benign-TP; a B-TP that says "close FP" / "detection misfired" / "false alarm"; a TP that says "close it"), plus a guard that no FP's `learn.concept` affirms a sanction. It also asserts all three verdict classes are non-empty, so the guards can never pass vacuously by the FP class emptying — the exact failure DEF-B would have produced.

**Guardrail tests nobody should "fix" later:** `cases.test.ts:105 / 127 / 147 / 160`. Each asserts `new Set(cases.map(c => c.truth))` equals all three verdicts per shift. They pass under DEF-A and fail under DEF-B.
