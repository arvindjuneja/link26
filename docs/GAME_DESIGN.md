# GHOST26 — Definitive Design & Technical Proposal

*An arcade simulator of the modern signals operator. UPLINK's heart, reborn for 2026.*

> **One line:** You never leave the chair, but you reach across the whole physical-digital world — footprint a person, task a sensor, listen to a band, fly a counter-UAS, crack a network — to answer one human question, and get out before anyone realizes you were there.

This document is the canonical build spec. It is grounded in the **actual current codebase** (verified file-by-file, not assumed), folds in every credible must-fix from three adversarial critiques (red-team/OSINT practitioner, senior game designer, pragmatic technical founder), and resolves the conflicts between them with stated reasoning. Where a critique corrected a factual claim in the original vision, this document uses the corrected fact.

---

## Decisions locked (2026-06-18)

Owner-made calls. These override any conflicting text below.

| Decision | Choice | Implication |
|---|---|---|
| **LLM access model** | **Baked pack free, live generation paid.** Ship a 50–100 mission starter pack (pre-generated) + assembly-based, non-LLM grading for free. Live procedural generation is behind the paid License. | Worst-case Anthropic bill is bounded by a number we set; free play costs ~$0/play. Drives the §8 cost model and §12 MVP. |
| **ATTRIBUTION forgiveness** | **Hybrid.** Barely decays naturally (preserves cross-session dread); an "identity churn" action fully resets it for a steep cash + reputation cost, affordable by mid-game. | §5 ATTRIBUTION + §6 meta. Out of paid v1.0 — design before Phase 2, with a clean save-migration story. |
| **Advisor / credibility** | **Both** — a named, paid security advisor for the codex + sensitive (camera/EW) pillars, **and** a closed cybersec beta. | §11. Line up the advisor before Phase 3; camera pillar copy ships only with sign-off. |
| **Game name** | **OPEN.** GHOST26 vs NULLROUTE vs keep Link26. Engine/Phase 0 work is name-agnostic, so this does not block development. Clearance must test "does a security person find it derivative," not just trademark/domain. | Decide before Phase 1 art spend. Doc uses "GHOST26" as a placeholder only. |

---

## Career-sim pivot (2026-06-23) — supersedes the single-seat framing

> **This note supersedes the single-operator framing of everything below. The GHOST26 spec is NOT discarded — it is now the RED seat of a larger whole.**

The single-seat operator fantasy is **reframed into a three-seat cybersecurity career sim** — **Blue (SOC analyst — deduction/triage)**, **Red (authorized red team / pentest)**, **Blackhat (the criminal path)** — three chairs sharing **one world, one engine**. The entire GHOST26 design below remains valid **verbatim as the RED seat**: the kill chain, the four-channel Exposure Board, the six surfaces, the seeded reducer, the evidence-assembly grading, and the codex are all reused — now one seat of three.

- **Why.** An *arcade* career sim (not a training platform) with an **education-affiliate on-ramp**; the Blue seat is the entry chair real newcomers actually start in.
- **Status.** Decided in the team's working memory; this doc was locked 2026-06-18 and never updated, so it was **stale** relative to the direction. This note + **§1b** reconcile it without gutting the locked content.
- **Grounding.** The Blue Tier-1 SOC role is researched in `docs/research/soc-tier1-research.md` (verified, adversarial). A first Blue-seat prototype is **already built and playable**: the engine in `app/lib/soc/` (`types.ts` / `engine.ts` / `cases.ts` + `*.test.ts`) plus a console UI at the **`/soc` route** (`app/soc/page.tsx` → `app/components/soc/SocConsole.tsx` + `SocOnboarding.tsx`, a first-shift coach). See **§1b** for what it is and how it shares the engine.

---

## 0. Verified ground truth (what actually exists today)

I read the code. These facts are load-bearing for everything below.

| Claim | Reality (verified) | Consequence for the plan |
|---|---|---|
| `trace.ts` is pure & reusable | **True.** 51 lines: `getTraceStatus`, `clampLevel`, `addTraceNoise`, `decayTrace`. Thresholds CALM/ALERT/HUNT/LOCKDOWN at 0/25/50/80. Noise formula: `base*(1-anon*0.7)*max(monitoring,0.15)*routePenalty`. | Reuse verbatim, instantiate per channel. Lowest-risk part of the plan. |
| `buildRouteState` is pure | **True.** `store.ts:62`. Anonymity composes `1-(1-a)(1-b)`, latency `30+costPerUse`/hop. | Lift to shared engine as-is. |
| `evaluateMission` is a clean switch | **True.** `store.ts:178`. But it's brittle: `modify` = `content.includes("tampered")`, `plant` = `includes("tracer")`. | Extend by cases; harden the predicate, do not LLM-grade pass/fail. |
| `rng.ts` is "an empty stub to fill with mulberry32" | **FALSE (critique correct).** It's a 3-line `randomBetween` using `Math.random()`. Must *replace internals* AND audit call sites. | The doc must not call it a stub. Determinism work is an audit, not a fill-in. |
| "Lift the already-pure cash math from runCommand" | **MATERIALLY OVERSTATED (critique correct).** `runCommand` is a **967-line async store method** (not ~600). Cash/reputation mutations (`store.ts:459-466`) are interleaved with `set()`, `emit()`, 9 `setTimeout` drama calls, and `Date.now()`. There is **no pure cash function to lift.** | Phase 0 is a *re-expression of runCommand as a pure reducer*, budgeted at 4-6 weeks, not 2-3. |
| The cheat hole | **CONFIRMED, worse than framed.** `saveCloudSupabase.ts` upserts the entire `GameState` blob (incl. `cash`, `reputation`); RLS (`supabase-schema.sql`) only checks `auth.uid() = user_id` and grants the client `update`. A devtools edit of `cash` persists. | **Hard gate: no public build, beta, screenshot, or leaderboard until this is closed.** Existential to the positioning. |
| The cringe noun layer | **CONFIRMED.** `worldgen.ts` ships "Nova Satellite HQ", "Orbital Data Exchange", "Charon Defense Grid"; files `/secrets.txt` ("TOP SECRET: Prototype diagnostics") and `/payload.bin` ("[binary blob]"). | **Retiring this is an explicit MVP deliverable**, not flavor polish. Credibility is won/lost in the first 30 seconds of nouns. |
| Trace has no connection-time clock | **CONFIRMED.** Noise is appended *per-action* (`appendTrace`), decays only on a 3s idle tick. A patient player sits connected at zero cost. | Add a dwell-time clock to the action phase. Without it, the heartbeat reacts to typing speed, not a closing window. |

Everything below is an **evolution of this engine, not a rewrite.**

---

## 1. Vision & Positioning

**GHOST26** — keeping the "26" (the 2026 setting and the UPLINK-to-now bridge) and naming the win-state and player fantasy: *ghosting* a target = leaving no trace.

> **Naming caveat (red-teamer must-fix, folded in):** "ghost" is heavily overloaded in security culture (Ghost framework, GhostNet, Ghost in the Shell, countless tools/handles). To the exact audience we court, it risks reading as derivative. The clearance check (Open Decision 1) must explicitly test "does this read as generic to a security person," not only legal availability. **NULLROUTE** is the vetted fallback and is arguably stronger — a nullroute *is* the operator dropping traffic into the void; it's authentic, ownable, and uncrowded. Run both in parallel.

The game is an **arcade simulator** of red teaming / OSINT / wardriving / cyber warfare / ELINT. Credibility comes from **authentic tradecraft vocabulary, accurate mental models, and respect for the craft** — never from transferable attack instructions.

### The HARD GUARDRAIL (load-bearing in two directions)
The same line that clears App Store review *also* earns cybersec respect:

| WE DEPICT | WE NEVER DEPICT |
|---|---|
| Phase/workflow names (recon → access → action-on-objective → exfil) | Working exploit code, payloads, real commands |
| Tool *categories* and what they're for | Anything that transfers to a live system |
| Abstracted minigames (pivot graph, spectrogram, scene analysis) | Real IPs, creds, target data, real CVEs-as-instructions |
| Trace/heat tradeoffs as game stats | Actual evasion/jamming techniques that work |
| Codex concepts + links to *legal* sandboxes | Step-by-step "how to attack X" |

---

## 1b. The three seats (career-sim pivot)

One world, three chairs. The same target, telemetry, and codex are seen from three vantage points; the engine **primitives are shared, not reimplemented per seat**.

| Seat | Role | Core loop | Outcome shape |
|---|---|---|---|
| **Blue** | Tier-1 SOC analyst — the **entry chair** | triage a queue of alerts; per alert pull the right sources, assemble evidence, make ONE call | TP / FP / Benign-TP → escalate or close |
| **Red** | authorized red team / pentest (**= the entire GHOST26 spec above**) | recon → access → action-on-objective → exfil against one target; minimize your *own* exposure | Clean / Hot / Burned |
| **Blackhat** | the criminal path | the Red verbs **without** RoE/scope — the line the game must walk to stay credible | (future) |

**What the seats share (engine reuse, not a fork):**
- The **Exposure Board** (`trace.ts` thresholds CALM/ALERT/HUNT/LOCKDOWN, instantiated per meter). Red's *own-detection* meter becomes Blue's **breach-risk** meter, **inverted**: now the dread is the **adversary's dwell when you MISS** (which, paired with noise, drives the headline heartbeat).
- **Evidence assembly + deterministic predicate grading.** Blue's call is graded by a pure predicate over ground truth (`gradeCall`/`scoreShift`) — the same crisp, un-gameable shape as Red's `evaluateMission`. **No LLM referee on either seat.**
- The **seeded reducer**, the tagged entity/world graph, and the **~80-card codex** (concepts + ethics, never procedures).

### The Blue Tier-1 loop (as actually built — `app/lib/soc/` + `/soc` route)
A **shift** presents a **queue of alerts** (the first shift deliberately leans toward not-a-threat — 4 of 7 — to cover all three verdicts and all three archetypes early; later shifts tilt more FP-heavy to mirror real triage, where most alerts aren't a threat). Per alert the analyst:
1. reads the **trigger** (what fired); the tool's severity is deliberately often wrong;
2. **pulls the right data sources** — each source carries the *question it answers*, teaching "**which log answers which question**" (auth → 4624/4625/4672; C2 → DNS; lineage → EDR process tree). Pulling the decisive sources is the move; pulling irrelevant ones just burns shift-minutes;
3. **assembles evidence** (cards weighted decisive / supporting / neutral / **noise** — the FP-dominant red herring) toward a verdict;
4. makes **ONE call** — `close-false-positive` / `close-benign` / `escalate-tier2` / `escalate-ir-isolate` — folding the **three-way classification AND the escalate/contain disposition into a single move**.

**Canonical verdict definition (decided 2026-09-05):** one question decides every alert — did the attack behaviour the rule hunts for actually happen? Didn't happen → **False Positive** (fix the rule). Happened + sanctioned by an artifact (RoE, change ticket, known tool, approved drill) → **Benign True Positive** (scope an exception, leave the logic). Happened + unsanctioned → **True Positive**. Full memo: [`DECISION-soc-taxonomy.md`](DECISION-soc-taxonomy.md).

Two pressure meters reuse `trace.ts`: **breach-risk** (a missed or under-escalated TP is now dwelling) and **noise** (crying wolf — escalating FPs or *isolating authorized activity* erodes trust and buries the next analyst). The headline **heartbeat is driven by the worse of the two** (mirroring Red's max-status-vector), with breach-risk the dread that's *new* to the blue chair. Grading is deliberately **asymmetric**: missing a live threat is the cardinal sin; crying wolf is the chronic one.

**First content — three verified archetypes**, each shipping as a malicious AND an authorized (Benign-TP) or false-positive variant (same detection, opposite verdict — the thesis):

| Archetype | MITRE | The read |
|---|---|---|
| Encoded PowerShell | **T1059.001** | encoding ≠ threat — decode, then read the parent (Word→PS→outbound vs SCCM agent + change ticket) |
| Auth brute-force | **T1110** (4624/4625/4672) | burst→success is only a threat when source/time/account don't fit the user |
| DNS C2 / beaconing | **T1071.004** | fixed-interval + high-entropy + NXDOMAIN — but confirm it's a temp-path binary, not a browser/CDN |

**Round 2 (2026-06-28, [`soc-tier1-cases-round2.md`](research/soc-tier1-cases-round2.md)) added a second shift** over four more archetypes — again each malicious **and** authorized (Benign-TP) or false-positive: **Phishing** (SPF/DKIM/DMARC + sanctioned-simulation B-TP; `T1566`), **Impossible-travel / MFA-fatigue** (Entra ID Protection risk detections; **`T1621`**, **`T1078.004`** — verified), **EDR malware** (Defender for Endpoint *True positive / Informational-expected / False positive*; `T1204`), **Data exfil to cloud storage** (personal-cloud TP vs sanctioned-backup B-TP; **`T1567.002`** — verified). The three-way verdict is now anchored in **Microsoft's own taxonomy**: Defender for Cloud Apps ships a literal *True positive / **Benign true positive** / False positive* scheme whose B-TP example is "an authorized penetration test" — exactly the game's bridge. The console (`/soc`) rotates through the shifts on "New shift". **Round 3 (2026-07-04,
[`soc-tier1-cases-round3.md`](research/soc-tier1-cases-round3.md))** verified the last
open MITRE ids (`T1566`/`T1204`/`T1547.001` — so phishing + EDR are cleared) and added an
**account-lockout** shift (the archetype where *most* alerts are benign: the #1 real cause
is a device caching an OLD password — Event 4740's Caller Computer Name is often blank, so
the read is to correlate Kerberos 4771 / NTLM 4776). Cross-vendor check: **Microsoft
Sentinel** ships a literal *Benign Positive - suspicious but expected* close-class — another
primary-source validation of the mechanic (the "benign positive" *disposition* is a
Sentinel/Splunk-style concept, not universal; named *signals* are cross-vendor). **Round 4
(2026-07-04, [`soc-tier1-cases-round4.md`](research/soc-tier1-cases-round4.md))** grounded the
**insider-threat** archetype (Microsoft Purview Insider Risk Management + CISA): the *same*
action is malicious or benign by **intent / authorization / role** — a departing employee's
exfil to a personal cloud (TP) vs a data-scientist's in-role baseline (FP, the UEBA anomaly
misfired) vs a ticketed corporate migration (Benign-TP). And the lesson that *inverts the usual
instinct*: the insider TP **escalates — hands up to a multi-stakeholder insider-risk / HR / legal
program — and must NOT isolate/confront** (that burns the case). This needed one engine tweak
(the "wrong containment" grade message is now direction-agnostic, since here *isolating* is the
over-action). **Now 21 hand-authored + 3 generated cases across 10 archetypes, 5 shifts.**

**The Red↔Blue handoff (2026-07-02, `app/lib/soc/handoff.ts`) makes the bridge a MECHANIC.** A red-seat run is turned into a blue case: the operator's tradecraft becomes the analyst's evidence — `cred-spray → password-spray→4624`, `proxy-chain → anonymized source`, `exfil-copy → scoped read+egress`, `log-wipe → audit log cleared (1102)`. `caseFromRedRun()` is pure/deterministic; a single impact-centred resolver drives archetype + title + detection rule + MITRE together (so they never diverge). The pivot is authorization: an **authorized** run (RoE on file) → **Benign-TP / close-benign**; the **identical tradecraft off-book** (your handle, no engagement) → **TP / escalate-IR**. **Authorization, not authorship**, decides the verdict — the same-board-two-seats thesis as a playable "Shift 4 · the other chair," with a fuchsia "↔ from your red seat" badge. This is the strongest demo of the pivot: your own red run, adjudicated from the blue chair.

**The same-board-two-seats bridge, made concrete:** a sanctioned pentest is a **Benign True Positive** — *a red-team run seen from the blue chair.* The shipped `soc-auth-pentest` case is exactly this: textbook credential-spray behaviour (the detection is **correct**) plus a signed RoE/deconfliction record → **close benign**, never escalate. The player's *own* Red-seat run is precisely what the Blue seat must recognize and not isolate.

### Career ladder & the education on-ramp
- The ladder is the meta: **T1 → T2 → T3** (monitoring/triage → investigation/containment → threat-hunting/detection-engineering), branching off to IR / threat-intel / **Red** / detection engineering. **BTL1 (Blue Team Level 1)** is the verified real-world **entry cert** the Blue seat models toward.
- The **education-affiliate on-ramp** lives on this seat: each case carries "learn this for real" pointers (MITRE pages, legal sandboxes such as LetsDefend) — the codex's affiliate surface, kept educational about concepts, silent on procedures.

> **Accuracy/credibility matters MORE on the Blue side** because it ties to **real recruitment**, so the research brief's caveats are load-bearing: **no unverified salary/pay data is ever presented as fact** (every concrete band was refuted — label any money illustrative/in-game); the SOC role, tiers, Windows event IDs, and ATT&CK mappings are kept accurate; and the "tierless-SOC / AI-automation" trend means manual-triage T1 is the *conventional baseline*, not a permanent truth. On this seat, **credibility is the product.**

---

## 2. The Player & The Fantasy

You are a freelance operator in one dim room. Not a hoodie cliché — a quiet professional with a workstation who reaches a substation in Stockholm, a courier's phone in Dubai, a parking-lot camera in Vienna. The fantasy is **omniscience earned one careful step at a time, paid for in constant low-grade dread.**

The career arc is the answer to UPLINK's known monotony — the *moment-to-moment* stays similar but the **source of tension migrates**:

- **Act I — The Scared Freelancer.** Cheap proxy chain, junk SDR. Every job is almost-getting-caught. Tension = *no margin*. (Maps to today's start: 4200c, rep 36.)
- **Act II — The Operator.** Hardened rig, global proxy mesh, tuned ELINT. You *choose* how to get in — the UPLINK "superhuman" peak. But you're now known.
- **Act III — The Hunted.** Your own footprint is the threat. The better you got, the more the world's eye turned toward you. Tension = *a target on my back.*

---

## 3. The Core Loop — one target, six surfaces, one rising heartbeat

**The one decision everything hangs on:** the six domains are **NOT six minigames**. They are **six recon/access surfaces of ONE target**, mapped onto the practitioner's **recon → access → action-on-objective** kill chain. A mission names a *person, place, or org* and an unanswered human question; the domains are the *ways in*. This is what makes GHOST26 cohere instead of being a feature checklist.

Every job flows through a 5-phase **Job arc** (8-20 min, mobile-sized), reusing the existing staged-`setTimeout` drama:

| Phase | Tradecraft term | Player does | Exposure pressure |
|---|---|---|---|
| 1. **Tasking** | Scoping / RoE | Read Mercer's brief: target + human question + **explicit scope (these assets, this window)** + a clock | none |
| 2. **Recon** | Footprinting / collection | Pick a surface. **Passive-first is the skill.** Choose *how hard to look*: passive = slow, near-zero footprint, incomplete; active = rich but writes to FOOTPRINT/NETWORK | slow, your *own* choice |
| 3. **Approach** | Staging / access-acquisition | Build route + posture (proxy chain, sensor placement, burner identity) **and acquire access** (see §6 — the missing kill-chain phase, now modeled) | small |
| 4. **Action-on-objective** | The op | `connect`/`cp`/`edit`/`deny-link`/`flag`. **Dwell-time clock runs — the heartbeat hammers.** | the spike + the clock |
| 5. **Exfil & cleanup** | Egress | `disconnect`, ride the decay down, decide whether to scrub | decays while disconnected |

**Emotional contour:** a rising sawtooth — long calm recon → breath-held action → release on clean exfil.

### Recon must have DECISIONS, not be a loading bar (designer must-fix)
The single biggest design risk is "spreadsheet not a game." The original loop is already a 4-step deterministic checklist with a guidance panel that literally prints the next command. Adding verbs on the same staged delays makes it *longer*, not deeper. We fix this structurally:

1. **Every recon action spends a scarce, legible resource against a payoff.** Looking is never free: `osint` → FOOTPRINT, `survey`(RF) → RF. Each action raises a vector.
2. **You choose how hard to look** (passive/cautious vs aggressive) — the foundational OSINT discipline (passive-first to minimize active surface) becomes the core tradeoff.
3. **Partial intel makes the action phase more dangerous** (unknown defenses = bigger spike). The live decision is *"do I have heat budget to dig one more thread, or act now on partial intel?"*
4. **The world pushes back unprompted.** A wardrive that trips RF mid-recon summons a "someone's looking back" event — a vector twitches without your input, forcing an abort decision. Tension requires the world to act, not just accumulate your noise.

### The Risk-Dial on submit (cheap, high-leverage)
Optionally hold a connection longer to grab BONUS intel/cash at rising exposure — a press-your-luck beat that turns the dwell clock into a greed decision and creates the "I should've left" regret story players retell.

### Three endings, never pass/fail
- **Clean (ghost):** all channels CALM at exfil. Reward = *silence returning* + Mercer's respect. The screenshot people share.
- **Hot:** objective met but a channel hit HUNT/LOCKDOWN. Full payout, but **Attribution permanently ticks up.**
- **Burned:** LOCKDOWN closes the window. NOT game-over — you lose the kit you used (it goes "known"), take rep + Attribution hits, log off shaken. Survival, not score.

### Streak discipline
A multiplier for consecutive Clean exits, reset by Hot/Burned. Reinforces the exact behavior the game is about. Tiny system, classic skill-game retention.

---

## 4. The Six Surfaces — modeled correctly (red-teamer must-fixes folded in)

The original vision name-dropped these; the practitioner critique caught real category errors. Corrected models:

### NETWORK (red team) — and the missing ACCESS-ACQUISITION phase
The terminal spine. But the original jumped recon → `connect/cp/edit`, skipping the *most characteristic* kill-chain phase. We add an **abstracted access-acquisition step** between recon and action:
- **Harvested-but-uncertain credentials** (from the OSINT breach-correlation surface) that *may* work — a probabilistic gate, not a guaranteed key.
- **A "spray" posture** that raises NETWORK trace in exchange for an access attempt.
- **No working technique ever** — it's a roll against gear/skill vs the target's posture. This is what makes "red teaming" not hollow.

### OSINT — grounded in specific, recognizable pivots (not generic "correlate")
The authenticity lives in the *specific pivots*, abstracted into a **pivot graph** (the Maltego/SpiderFoot mental model). Verbs and evidence reference real OSINT primitives:
- username pivoting across platforms, certificate-transparency-style subdomain discovery, WHOIS-history correlation, EXIF/geo inference, **breach-data correlation** (feeds access-acquisition), tech-stack leakage from job posts, timezone/commit-time analysis.
- **The interface is a pivot graph, not a text box.** Recon actions drop **evidence cards** (a handle, a MAC, an emitter ID, a face); the player connects a username → email → breach record → device → building. The **"Dossier Snap"** is literally two subgraphs merging into one. Practitioners recognize this instantly and respect it.
- **Passive vs active** is the FOOTPRINT tradeoff: public records/breach/cert logs/cached pages = near-zero footprint; scanning/probing/social engineering = richer but writes to FOOTPRINT.

### RF collection — NOT "wardriving" by a chair-bound operator (category-error fix)
A chair-bound operator who "never leaves the room" **cannot wardrive** (wardriving is mobile by definition). RF intel comes from **deployed/rented/co-opted assets**: a dropped sensor, a positioned SDR, a co-opted device radio. The verb is **`deploy sensor` / `tap` / `collect rf`** — the player *tasks remote collection*, they do not personally drive. This reconciles the fantasy with the tradecraft.

### ELINT — disambiguated from COMINT (lane chosen: ELINT)
We ship **ELINT**, not COMINT. The verb is **characterize/fingerprint an emitter by signal parameters** — band, PRF, modulation, scan pattern, on/off duty cycle — to **classify and geolocate** it. **Content is never decoded.** The "aha" is realizing the unlabeled emitter at the target site matches the signature of a security-camera backhaul. Real ELINT thinking, fully abstract, zero operational value. The codex card is written for ELINT specifically and advisor-checked. (No single "sweep/intercept/classify" verb that smears ELINT and COMINT together.)

### Drone / EW — abstract counter-UAS
`classify-emitter` → `deny-link` drives a target C2 link's quality below threshold for a window. The EW trace analog is **DF heat** (transmit power × duration → a counter-team triangulates *you*). Spoof/jam are timer + heat tradeoffs, never signal recipes. Drones are abstract sprites with stats.

### Camera — reframed away from person-spotting (reputationally radioactive fix)
**Cut the "watch open cameras to spot a person" framing entirely** — the stalking adjacency is the risk, not the photorealism. Replace with **scene analysis over stylized, non-photoreal generated dioramas**: detect a misconfiguration, classify a scene, count assets, read a shift-change time, identify a badge color. **No person identification or tracking, ever.** Stylized diorama, never a real feed, never a Shodan-style index. Ships last, gated behind named-advisor sign-off on the exact scenario copy.

---

## 5. The Emotional Core — the Exposure Board (the modern Trace Tracker)

UPLINK's genius: *one rising number that beeped like a heart-rate monitor as the window closed.* We keep `trace.ts` **verbatim** and **instantiate it four times.** `gameState.trace` → `gameState.exposure: Record<Vector, TraceInfo>`.

| Channel | The fear | Driven by | Decay |
|---|---|---|---|
| **NETWORK** | "Are they tracing the packet back?" | unscanned connect, log-wiping (today's behavior) | disconnect & idle |
| **RF / PHYSICAL** | "Is someone in that building noticing me?" | deployed-sensor dwell, transmitting, jamming | go RF-silent |
| **FOOTPRINT** | "Did I just tip them off by looking?" | aggressive/active OSINT vs a watched entity | time + switching sources |
| **ATTRIBUTION** | the slow one — "they're building a profile of *me*" | **infrastructure & TTP reuse** (see below) | barely decays; persists across sessions |

The skill is **triage across four bars, not zeroing one.** The global heartbeat (persistent Web Audio oscillator: CALM=silence as reward → LOCKDOWN=150bpm sawtooth + edge strobe; page tint via the existing `traceStyle.bg`; iOS Core Haptics lub-dub) is driven by the **max-status vector.**

### Two-Vector Squeeze — corrected coupling (red-teamer caught the original was backwards)
The original example (wipe network logs → spike RF) was physically wrong: wiping logs on a remote host is a NETWORK action and wouldn't touch RF. The **honest couplings**:
- **Dwell coupling:** to lower NETWORK you go quieter on the wire but must **hold the session longer** = more dwell = higher ATTRIBUTION/correlation risk. Quiet-but-slow vs fast-but-loud. This is also the connection-time clock the loop needs.
- **Jam coupling:** denying a link to lower one pressure spikes **RF/DF heat** hugely.

### ATTRIBUTION = infrastructure & TTP reuse (the spine, folded in)
The meta-trace rises specifically when you **REUSE kit** — proxies, sensors, identities, even mission patterns — because real attribution is built on infrastructure overlap and TTP repetition. This makes "identity churn" (burn it all, start fresh) feel *earned* and teaches the actual lesson that reuse is how operators get caught. Perfect marriage of mechanic and tradecraft.

### OPSEC-slip events (the authentic "oh no")
Occasionally an action carries a hidden tell surfaced *after the fact*: *"that view came from your real session — Mercer flags it"*; *"you reused a sensor that's already known"*; *"your collection happened in the target's working hours — it correlates to a human at a keyboard."* The sickening, recognizable moment real operators know.

> **Conflict resolved — 4 vs 3 vs 6 channels.** Ship **four** (NETWORK/RF/FOOTPRINT/ATTRIBUTION). Three can't carry the distinct OSINT-footprint and persistent-attribution fears; six is UI clutter that kills UPLINK's one-legible-signal. The six *domains* each write into one of the four *channels* — "one heartbeat, four channels, six input verbs." **MVP ships only NETWORK + RF.** FOOTPRINT + ATTRIBUTION gate behind Act II so newcomers learn one thing at a time. (The founder's caution — that ATTRIBUTION's cross-session persistence is the highest save-migration risk for the least MVP value — is exactly why it is *not* in the first paid release.)

---

## 6. World, Systems & Progression

### Seeded skeleton + LLM skin (never LLM-as-referee)
- **Layer A — deterministic seeded PRNG (authoritative).** Replace the *internals* of `rng.ts`'s `randomBetween` with mulberry32 and **audit every call site** in `worldgen.ts`/`store.ts` to route through the seeded instance (the critique's correction: this is an audit, not a one-line fill). Thread a seed through `generateWorld`. Same seed → byte-identical skeleton: graph shape, monitoring, mission-relevant entities, the truth tags.
- **Layer B — LLM skin (cosmetic, async, server-side, schema-bounded, cached by `(seed, entityId, contentVersion)`).** Hostnames, file contents, personas, Mercer's voice. **The iron rule: the LLM proposes; a deterministic predicate over game state decides pass/fail.** This single decision resolves anti-cheat, anti-hallucination, AND the guardrail at once — free-form technical prose physically cannot leak through a schema-bounded, predicate-graded pipeline.

### Replacing the cringe layer (explicit MVP deliverable)
Retire `/secrets.txt`, `/payload.bin`, "Nova Satellite HQ", "Charon Defense Grid". Targets read like real intel: a person with a handle and a timezone, an org with a public footprint, a building with an emitter. Artifacts are plausible-but-fictional — a config fragment, a leaked org chart, a firmware version string, a calendar invite — **never a file literally named "secrets."** Costs almost nothing; highest-leverage credibility fix.

### Rules of Engagement / scope discipline (most authentic missing concept)
Every contract carries explicit scope (this org, these assets, this window). Going out-of-scope carries an ATTRIBUTION/reputation penalty. A **"minimize collection / leave no trace" scoring bonus** rewards taking *only* the data the objective needs. This models the legal/ethical boundary real red teams operate under and is the line between a professional and a criminal — exactly the line the game must walk to earn respect. RoE turns the ethics framing into a *mechanic*, not a disclaimer.

### The World type
`World = {hosts, proxies}` promotes to a tagged entity graph adding `person`/`network`/`rfEmitter`/`cameraFeed`/`drone`/`org`, each reusing `id`/`label`/`geo` so the existing Canvas2D map plots them unchanged. `MissionObjective.type` extends from `exfil`/`modify`/`plant` with `identify`/`geolocate`/`classify`/`deny_link`/`spot_event`/`own_node`/`map_coverage`; `evaluateMission` grows by cases (and the brittle `includes("tampered")` predicate is hardened to a real state check).

### Acquisition loop in the MVP — NOT a punishment-only meta (designer must-fix)
The original MVP shipped only *vulnerability* (Attribution) and deferred all *power* (gear) to Phase 2-4. UPLINK's magic was the **balance** of power-fantasy and vulnerability. So **one capability-acquisition track moves into Phase 1**: completing jobs visibly buys a **gear/rank tier that flattens a vector's noise coefficient** — the player *feels* a fear get quieter ("Owning the Rig"). This is the difference between day-1 (tension lands) and week-1 (a reason to play job #7) retention. Full gear catalog (Rig/Field-kit loadout aliasing the old `ToolId`s, fixing the proxy-heat-never-cools bug with a decay tick) and the faction matrix arrive in Phase 2.

### ATTRIBUTION as opt-in pressure with a payoff (designer must-fix)
When it ships (Phase 2), accumulating Attribution **unlocks higher-paying tiers/factions** (heat = access to the good contracts) so the meta *pulls forward* as well as threatens. Paired with **identity churn** as an affordable-by-mid-game reset valve, it's a managed resource, never a dead-end.

### The Callback — pulled forward to retention-grade (designer must-fix)
Between jobs, a poorly-ghosted target "calls back": a vector twitches, Mercer pings *"they ran your handle."* The asynchronous pull that brings players back. Cheap (one persisted timer + one push) — bring a lightweight version into Phase 1/2, not Phase 4.

> **Conflict resolved — gating dead-ends.** Faction zero-sum edges + capped gear could strand a player (too low-tier, too hated). Guarantee a low-tier income floor and a faction-reset path (identity churn) so no save becomes unwinnable.

---

## 7. The Handler: "Mercer"

The existing `MissionGuidance` panel becomes a handler with personality — terse, ex-trade, never theatrical. Mercer authors contracts, role-plays NPCs you socially engineer, grades open-ended calls against a fixed rubric, and **coaches newcomers in character** (accessibility via two reading levels of the *same* depth, never a dumbed-down mode: *"I'd footprint him before you go near the building"* teaches the verb AND the tradecraft).

**Mercer has OPSEC judgment** (folded in): he occasionally refuses or warns on tradecraft grounds — *"That building has people in it at this hour — wait for the off-shift window"*; *"You're about to touch their prod infra directly; footprint says don't."* A handler with judgment teaches the craft AND signals to the community that the game knows what responsible operation looks like.

**Mercer's tone is soft progression:** terse approval after clean jobs, clipped warnings after hot ones. A felt week-1 thread that isn't a number. Cache the tone state; don't regenerate personality each call.

---

## 8. LLM Grading — crisp and fair, never mushy (designer must-fix, decisive)

The original "Sonnet grades free-text `identify` against a rubric" is the single mushiest point. Three problems: (a) the cybersec crowd *will* discover and copy-paste optimal answers; (b) typing paragraphs mid-session kills pace and is brutal on mobile; (c) non-deterministic scores feel *unfair* even when correct, and unfairness is retention poison.

**Resolution: the core answer is ASSEMBLED, not typed.** The player builds the answer from collected **evidence cards** — select the person, the building, the emitter, the link — and a **deterministic predicate** checks the assembly. This kills the typing-on-mobile problem, the rubric-gaming problem, and the unfairness problem in one move.

- **LLM free-text grading is reserved for optional, high-tier "analyst calls"** that pay a bonus, never for core pass/fail.
- If free-text is used at all, the LLM returns a **deterministic structured verdict the player can see the reason for**, and identical answers score identically (cache by normalized answer).

### Model tiering (verified current pricing)
| Tier | Use | Model | Price (in/out per MTok) |
|---|---|---|---|
| Cheap | NPC chatter, ambient flavor, host banners | `claude-haiku-4-5` | $1 / $5 |
| **Workhorse** | mission generation, analyst-call grading | `claude-sonnet-4-6` | $3 / $15 |
| Marquee | campaign set-piece beats only | `claude-opus-4-8` | $5 / $25 |

> **Conflict resolved — two-tier vs three-tier.** Ship **three.** Sonnet at $3/$15 is the right home for high-frequency generation/grading; Opus at $5/$25 would 1.7× the dominant cost line for work Sonnet handles well, and Haiku can't reliably rubric-grade. Opus is reserved for the handful of writing-is-the-product moments. Structured outputs via `output_config.format`; prompt caching on the frozen world-bible prefix — **the system prompt must never interpolate `Date.now()`** (the code stamps timestamps everywhere; that habit would silently bust the cache).

### A real cost model with a circuit breaker (founder must-fix)
- **Batch-pregenerate ALL mission content offline** (cheap, cacheable — can be Opus once and reused). Reserve *live* LLM for analyst-call grading + NPC chatter only.
- **A "starter content pack"** (50-100 missions, persona snippets, host filesystems) generated once with Opus, **baked into the build, served offline/free at zero per-play LLM cost.** Live generation becomes a *paid delighter*, not the load-bearing free path. This makes the free tier genuinely free-to-run and turns "infinite world" into clean monetization.
- **Kill switch + cost circuit breaker from day one:** per-account AND global daily token budget in a Cloudflare KV counter; when exceeded, **degrade gracefully to cached/pregenerated content** instead of erroring. The difference between a surprise $4,000 bill and a $200 ceiling during a launch spike.
- **Open-text grading does NOT cache** (every answer is unique → only the rubric prefix caches). This is *why* core grading is assembly-based, not free-text. If live grading can't be bounded, the free tier falls back to a **deterministic scorer**, reserving any LLM grading for the paid License.

| Line item | 1k MAU | 50k MAU |
|---|---|---|
| Cloudflare Workers | ~$5 | $50-150 |
| KV / Durable Objects | <$5 | $20-60 |
| Supabase | $25 | $25-100 |
| **Anthropic LLM** (dominant, capped) | $60-150 | $3k-9k |
| **Total** | ~$100-200/mo | ~$3.5k-9.5k/mo |

The LLM line is bounded by the per-player caps — worst case = `(paid seats × cap) + (free MAU × small cap)`, both set by the owner.

---

## 9. Technical Architecture

### Hosting — Cloudflare Workers via OpenNext (decided)
| Option | Verdict | Why |
|---|---|---|
| **Cloudflare Workers + `@opennextjs/cloudflare`** | **CHOSEN** | Full App Router SSR + Route Handlers (the LLM proxy + authoritative engine) on Node-compatible Workers; unlimited bandwidth; 300+ edge POPs. |
| Cloudflare Pages static export | Rejected | No server for the LLM proxy/engine. |
| Firebase | Rejected | Weak App Router SSR/RSC; unpredictable Functions billing. |

Supabase stays **exactly as-is** for auth (JWT issuer) + Postgres. The Worker validates Supabase JWTs and holds the Anthropic key in a Cloudflare secret behind `POST /api/llm/:usecase`. (Note: the repo's `output:"standalone"` Docker target is demoted to a fallback escape hatch, not the primary.)

### Closing the cheat hole — Phase 1, hard gate
Split state:
- **Client-authoritative (cosmetic):** terminal scrollback, UI, command history. Stays in IndexedDB; offline-capable.
- **Server-authoritative (Worker-written only):** `cash`, `reputation`, mission completion, Attribution. New `player_progress`/`player_session`/`mission_state` tables; RLS gives clients **read-but-not-write**. A one-time migration grandfathers existing players from their `saves` blob **with a sanity-clamp** so tampered blobs can't seed inflated balances.

**Ship reconciliation in shadow-mode first (founder must-fix):** make the first server-authoritative action low-stakes (mission-complete payout) behind a feature flag — client computes optimistically, Worker is the silent logged source of truth — watch divergence logs for a week, *then* flip enforcement on. De-risks the prediction/reconciliation bug class.

### The Phase 0 refactor — honestly scoped (founder must-fix)
The cash/reputation logic is **not** a pure function to lift; it lives inside the 967-line async `runCommand`. Phase 0 re-expresses it as a **pure reducer**:

```
reduce(intent, state, seededRng) -> { nextState, effects[] }
```
where `effects` (terminal lines, sounds, setTimeout drama) are re-driven by the store on the client and **discarded** on the Worker. **Budget: 4-6 weeks, not 2-3.** The explicit acceptance test: *the same engine call produces identical `{cash, reputation, mission.completed}` in the browser and in a Worker unit test.* A **determinism test harness in CI** (headless run-from-seed+command-log, reproduces identical economy state twice) is a Phase 0 deliverable — if it can't, replay-anti-cheat is impossible and we learn it in week 2, not month 9.

### Anti-cheat — split into two problems (founder must-fix)
- **Server-authoritative economy** (Phase 1, achievable): Worker validates deltas via the shared reducer; RLS forbids client writes.
- **Deterministic replay verification** (a *research spike*, NOT a committed deliverable): byte-identical determinism across browser and Worker JS runtimes is not guaranteed. Spike it with a fallback — **server-side statistical anomaly detection + heuristic flagging** (shadow-flag suspicious accounts off leaderboards) — so the leaderboard isn't blocked on solving cross-runtime determinism.

### iOS via Capacitor — submit EARLY (founder must-fix)
Wrap the same client build; API base URL points at the Worker. One backend, two frontends. **Before Phase 1 even completes, submit a minimal-but-native Capacitor build (real Core Haptics, real push, offline play) to TestFlight** to flush out the two stacked landmines while the codebase is small:
1. **Guideline 4.2/4.3 (webview wrapper):** a text-terminal-in-a-webview is exactly the silhouette reviewers reject. **Lead the build with the glowing animated netmap/spectrum canvas apps + the haptic heartbeat as the hero experience**; keep the raw terminal secondary. This reads as a real app, not a wrapped website.
2. **Content + AI (4.x/5.x):** hacking theme + third-party AI + (later) UGC is a moderation magnet. Hacknet precedent exists but ships *no* live AI and *no* UGC. Add the mandatory third-party-AI disclosure in onboarding + privacy policy; complete the age questionnaire (~12+/13+); build on iOS 26 SDK; reviewer note citing UPLINK/Hacknet precedent. **Budget 2-4 weeks of review-iteration buffer.**

### Offline tiering
Deterministic core loop (scan/route/connect/fs/trace) runs fully offline and reconciles on reconnect. LLM content is online-only with pre-fetch of upcoming chapters. Honest framing: an arcade sim with an online narrative layer.

---

## 10. UI/UX, Art & Sound — the Gateway OS

One fictional OS, **Gateway**, where each pillar is a runnable *app* (`term`, `netmap`, `recon`, `spectrum`, `optics`, `recce`, `inbox`, `gear`, `comms`), unified by one melancholy-blue **"cold glass at 3am"** palette where **color is spent as tension rises** (CALM = low-saturation cyan, *not* bright green; LOCKDOWN desaturates toward the threat hue and dims non-essential panels to ~40% to force tunnel vision).

- **Terminal + apps are two views of one command stream** (generalizing the existing `onProxyAdd → runCommand` bridge — clicking a host == typing `scan <host>`).
- **`TraceMeter` → persistent System Bar ECG**; BPM = max-vector level. The pulse line *is* the gauge (long-press reveals the number).
- **Sound (`sounds.ts`):** add an always-on ambient bed (~55Hz pad + sparse data ticks that detune as trace rises) + a synthesized `lub-dub` heartbeat fired at `60000/BPM`. Wire up the already-present-but-unused `playTraceRise`/`playTraceWarning`. Budget the glitch/scanline/CRT effects to HUNT/LOCKDOWN only; no idle decorative glitching; no emoji in UI.
- **Two-voice type:** IBM Plex Mono = machine; Space Grotesk = human. Drop the barely-used Geist font.

```
+==========================================================================================+
|  GATEWAY v26   id: ghost_0x2A   13:42 UTC   [♥ ~~/\~~/\~~ HUNT ]   CASH 4,210c   ⊘       |  <- System Bar ECG
+====+=====================================================================================+
| D  |  ┌─ netmap ─────────────────────[ _ ⊡ ✕ ]──────────────────────────────────────┐  |
| O  |  |   · · · ·  ▢───▢════▢ ───→ ◇ TARGET (Reykjavik)   route 3 · anon 71% · 240ms |  |
| C  |  └────────────────────────────────────────────────────────────────────────────┘  |
| K  |  ┌─ term ─────────────[ _ ⊡ ✕ ]┐  ┌─ recon (pivot graph) ───────[ _ ⊡ ✕ ]┐     |
| >_ |  | op@target:~ [HUNT]>          |  |  (handle)──reused──(email)             |     |
| ◈  |  | > collect rf --passive       |  |     |                  |                |     |
| ∿  |  | _                            |  |  (domain)──hosts──(asn)──(org)         |     |
| ✉  |  └──────────────────────────────┘  └────────────────────────────────────────┘     |
| ⌘K |     ^ DOCK rail + Cmd-K palette (connective tissue, also the mobile super-power)    |
+====+=====================================================================================+
```

> **Conflict resolved — full window manager risk.** v1 ships existing components reskinned into the OS frame + System Bar heartbeat + Cmd-K palette. The tiling/floating compositor, workspaces, and new canvas apps arrive **progressively, gated behind gear unlocks** (which doubles as diegetic onboarding). On mobile, the desktop **dissolves into a one-app-at-a-time App Deck** with a swipe-up tap-to-build command palette (never a shrunk desktop) and a one-tap **PANIC** (disconnect-all) at HUNT/LOCKDOWN.

---

## 11. Credibility, Ethics, Monetization, Community

- **Tradecraft as structure:** the kill chain is the named phase bar; MITRE ATT&CK tactics are objective verbs (carrying `attackTechniqueId` used ONLY for a codex lookup, never a procedure); the OSINT lifecycle is the recon minigame.
- **The ~80-card "How it really works" codex** (static, advisor-reviewed, educational about concepts + ethics, silent on procedures) — the artifact infosec people screenshot. Open-source the codex content as goodwill; keep the game proprietary.
- **Monetization (un-scummy):** one-time **$14.99 Operator License** (web via Cloudflare; iOS as non-consumable IAP, entitlement mirrored to Supabase so one purchase unlocks both platforms) + cosmetic Terminal Themes + an optional cosmetic/curation Season Pass. **Publicly reject** P2W, purchasable stats, energy timers, loot boxes, gacha, ads, data-selling — and make the "monetization promise" page a marketing asset.
- **Community:** daily seeded contract (the week-1 ritual + leaderboard wedge, scored on **trace discipline** — lowest exposure peak / cleanest exit), **ghost-run replay** (top runs animate over the map — aspirational AND a better tutorial than any tutorial), additive Supabase tables, named security advisor whose credit is itself a credibility asset + a closed cybersec beta.

> **Conflict resolved — premium price vs LLM-cost recovery.** Both. The $14.99 License is the headline (UPLINK/Hacknet precedent). The free tier is bounded by baked-in starter content + Haiku flavor + assembly-based (non-LLM) grading on a daily pool + heavy caching — genuinely playable, top-of-funnel, not P2W (you buy content + campaign, never power), and it caps the worst-case bill.

---

## 12. MVP Scope (v1.0 = the actual launch)

> **Founder must-fix folded in:** v1.0 = **Phases 0-1 only** — web-first, no iOS, two channels, OSINT + RF, premium License. Everything else is post-launch. This is the runway-safe launch; the grand vision is the post-launch roadmap.

1. **Rename + reskin** to GHOST26 (pending clearance) / NULLROUTE. Cold-glass palette tokenized; drop Geist.
2. **Retire the cringe noun layer** (explicit deliverable): kill `/secrets.txt`, `/payload.bin`, "Nova/Charon" names → real-intel-shaped targets and plausible-fictional artifacts.
3. **Exposure Board, TWO channels** (NETWORK + RF). FOOTPRINT + ATTRIBUTION explicitly OUT.
4. **The heartbeat:** persistent Web Audio oscillator on max-status channel; wire up unused `playTraceRise`/`playTraceWarning`. Page-tint + edge-glow. (Haptics deferred to Capacitor phase.)
5. **Connection-time dwell clock** in the action phase (the missing UPLINK mechanic) + intermediate "looking back" failure events in recon.
6. **TWO recon surfaces:** OSINT (pivot graph + evidence cards + passive/active tradeoff) and RF (deployed-sensor `collect rf`, *not* "wardrive"). ELINT/drone/camera OUT of v1.
7. **Abstracted access-acquisition** step (harvested-uncertain creds) so red teaming isn't hollow.
8. **Seeded world:** replace `rng.ts` internals with mulberry32 + audit call sites; seed through `generateWorld`. `person` + `network` kinds.
9. **Server-authoritative slice (HARD GATE):** OpenNext deploy; Phase 0 pure-reducer refactor (4-6 wks) + CI determinism harness; `player_progress` + `POST /api/action` with shadow-mode reconciliation; sanity-clamp migration; RLS read-only on balance.
10. **Mercer handler,** one LLM use case: Haiku flavor/coaching; **assembly-based** `identify` grading (deterministic predicate over evidence cards) — LLM free-text reserved for optional bonus analyst calls. KV cache + circuit breaker + per-account daily cap. **Baked-in starter content pack** so free play is zero-per-play-cost.
11. **One acquisition track** (gear/rank tier that flattens a vector) so week-1 has a carrot, not just the Attribution stick.
12. **Lightweight Callback** + streak bonus + Risk-Dial on submit.
13. **Three endings** (Clean/Hot/Burned). **RoE/scope** on every contract + minimize-collection bonus.
14. **Gateway OS frame (light):** reskinned components + System Bar ECG + Cmd-K palette. No window manager.
15. **First-run fiction-simulator disclaimer + versioned EULA + mandatory third-party-AI disclosure.** README states the WE-DEPICT / WE-NEVER-DEPICT line.

---

## 13. Phased Roadmap (re-baselined to ~14-20 months solo)

> The original ~7.5-11.5 months was engineering-hours presented as calendar-time. Real solo calendar — accounting for the true Phase 0 cost, Apple review loops (1-3 wks each), LLM prompt-engineering iteration, and live-ops once players exist — is **~14-20 months**. Scope v1.0 as Phases 0-1 so there is a shippable game before runway risk.

**Phase 0 — Foundation refactor (the unblocker) · ~4-6 wks**
- Replace `rng.ts` internals with mulberry32 + audit all call sites; seed through `generateWorld`.
- Re-express `runCommand` as a pure reducer `(intent, state, rng) -> {nextState, effects[]}`; lift the already-pure `trace.ts`/`buildRouteState`/`evaluateMission` into `engine/`.
- **CI determinism harness** (acceptance: identical economy state browser vs Worker).
- Deploy the *current unchanged* app to Cloudflare Workers via OpenNext; validate before building on it (Docker as fallback).
- One cosmetic LLM use case (Haiku handler flavor) through `POST /api/llm/handler` — proves key boundary, KV cache, rate limit, circuit breaker at zero gameplay risk.

**Phase 1 — GHOST26 v1.0 (the emotional MVP + the launch) · ~1.5-2 mo**
- Everything in §12. The first genuinely shippable, emotionally-complete, cheat-proof slice. **Web-first launch with the Operator License.**
- *Submit a minimal native Capacitor build to TestFlight during this phase* to flush Apple's verdict early.

**Phase 2 — Depth & the four-channel meta · ~1.5-2 mo**
- FOOTPRINT + ATTRIBUTION (ATTRIBUTION = infrastructure/TTP reuse, persists server-side, gates Act II, drives the Callback). ELINT (sweep/characterize on a Three.js spectrum waterfall; SDR-relay-as-proxy). Full gear catalog + Rig/Field-kit (fix proxy-heat-never-cools). Faction matrix + identity churn. Opus marquee campaign beat #1.

**Phase 3 — iOS + the sensitive pillars · ~1.5-2 mo + review buffer**
- Full Capacitor App Deck + Core Haptics + PANIC + push. Drone/EW (classify-emitter/deny-link). Camera as scene-analysis dioramas (advisor sign-off). Full Gateway window manager + new canvas apps. App Store submission with IAP entitlement mirrored to Supabase.

**Phase 4 — Community, seasons & longevity · ~2-3 mo**
- Seasons + leaderboard on trace discipline; **replay-verification spike with anomaly-detection fallback**. Skill tree (auditable formula coefficients). ~80-card codex + PhaseTracker. UGC Mission Forge (validated data specs + safety classifier + real-world-identifier deny-list) + ghost-replay spectating. District-lazy infinite world. Launch CTF + creator early-access + public monetization-promise page.

---

## 14. Conflicts Resolved (summary)

| Conflict | Resolution | Why |
|---|---|---|
| 4 vs 3 vs 6 exposure channels | **4** (MVP ships 2) | 3 can't carry FOOTPRINT+ATTRIBUTION as distinct fears; 6 kills the one-legible-signal. |
| 2-tier vs 3-tier LLM | **3 tiers** | Sonnet is the right $3/$15 workhorse; Opus would 1.7× the dominant cost; Haiku can't rubric-grade. |
| LLM author vs referee | **Always author; never referee** | Deterministic predicate decides pass/fail → resolves anti-cheat + anti-hallucination + guardrail at once. |
| Free-text vs crisp grading | **Assembly of evidence cards** (deterministic); free-text only for optional bonus calls | Kills mobile-typing, rubric-gaming, and unfairness simultaneously. |
| Firebase vs Cloudflare vs Pages | **Cloudflare Workers + OpenNext** | Needs a server for LLM proxy + authority; Firebase SSR weak + billing unpredictable. |
| Client blob vs server-authoritative | **Split; economy Worker-written** | The verified 90-second cheat hole is existential to the positioning. Hard gate before any public build. |
| Premium vs LLM-cost tiers | **Both:** $14.99 License headline + bounded free tier (baked content + Haiku + non-LLM grading) | Honest, not P2W; caps the worst-case bill. |
| Grand UI vs shippable MVP | **Stage it; gate apps behind gear** | Window manager dwarfs the game if built first; gating doubles as onboarding. |
| All six surfaces vs phased | **Phase by reputational risk:** OSINT+RF → ELINT → drone/EW → camera last | Camera is reputationally radioactive; reframed to scene-analysis, advisor-gated. |
| "Wardrive" from a chair | **Deployed/tasked RF sensors**, not personal wardriving | Category error practitioners catch instantly. |
| ELINT vs COMINT | **ELINT** — characterize emitters by parameters, never decode content | Distinct disciplines; pick the lane and model it right. |
| Determinism "instant in Phase 0" | **It's an audit + a 4-6 wk reducer refactor + a CI harness; replay-anti-cheat is a spike** | The hard 90% can't be both "instant" and "the foundation of Phase 4." |
| Single-seat operator vs career sim | **Three seats, one world (Blue SOC / Red / Blackhat)** — GHOST26 below is the Red seat | Blue is the entry chair tied to real recruitment; shared engine + codex; first Blue prototype built (`app/lib/soc/`). See the pivot note + §1b. |
