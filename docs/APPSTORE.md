# SENTRY — SOC · App Store package

`docs/ios/SPEC.md` §8, carried here verbatim and amended where the addendum, the P1 pass or a
measurement moved it. This is the sheet to type into App Store Connect.

Build runbook: [`docs/IOS-BUILD.md`](IOS-BUILD.md). Founder sign-off:
[`docs/PLAYTEST-ios.md`](PLAYTEST-ios.md).

There is **no WKWebView anywhere**, so the 4.2 "repackaged website" concern is gone — which
concentrates the remaining review risk on 2.1 / 4.3 "lasting value" (§7 below).

---

## 1 · Metadata

| field | value |
|---|---|
| App Store name | **SENTRY — SOC** |
| Subtitle | Tier-1 SOC analyst shifts |
| Home-screen name | SENTRY SOC |
| Bundle id | `pl.oumm.sentry.soc` |
| Category | **Games › Puzzle**, secondary Education |
| Devices | iPhone only (`TARGETED_DEVICE_FAMILY = 1`, target-level per D20), portrait, **iOS 18.0+** (was 16.0 — D14) |
| Version / build | 1.0 / CI run number |
| Price | **Paid up-front** (Tier 5, $4.99) — zero StoreKit, zero restore flow, and it keeps "Data Not Collected" trivially true. No ads, no timers, no consumables, no loot, stated in-app under "Our promise". |

Paid up-front is a design decision, not a pricing experiment: with no StoreKit there is no
purchase to restore, no receipt to validate, no consumable to disclose on the privacy label
and no account to hold one. The App Store page should read as a small finished game, not a
licence.

---

## 2 · Age rating — **4+**

Text-only fictional security alerts trigger no Violence / Mature / Medical / Gambling /
Unrestricted-Web-Access descriptor. The privacy link opens `SFSafariViewController`, which
does **not** force 16+; an embedded browser (`WKWebView` with free navigation) would.

Questionnaire answers, and the evidence behind them:

| question | answer |
|---|---|
| Cartoon or Fantasy Violence | None |
| Realistic Violence · Prolonged Graphic Violence | None |
| Profanity or Crude Humor | **None** — see the grep below |
| Mature/Suggestive Themes · Horror · Alcohol/Drugs · Sexual Content · Nudity | None |
| Simulated Gambling · Contests | None |
| Medical/Treatment Information | None |
| Unrestricted Web Access | **No** — one `SFSafariViewController` to a fixed privacy URL |
| User-Generated Content · Messaging | None |
| Advertising | None |
| Data collection | None |

### The grep evidence

`ios/scripts/verify.sh` runs check 7 over the shipped copy before these answers are filed:

```
grep -inE '\b(damn|shit|fuck|hostage|weapon)\b|\bkill(s|ed|ing)?\b' \
     copy.json content.json ios/SentrySOC/Sources/**/*.swift
```

Result on the shipped bundle: **one hit, allowlisted with its reason** in
`ios/scripts/profanity-allow.txt`:

> `content.json` (and its source `app/lib/soc/cases.ts`), the red-team-tool case's
> `learn.concept`: *"suppress for the window — **don't kill the rule** that catches the real
> thing."* "Kill the rule" is SOC idiom for disabling a detection rule. No person, no
> violence, no weapon — the sentence argues for suppressing a rule for a window instead of
> deleting it.

Zero hits in Swift sources. The guard fails on any unlisted hit, so the questionnaire answer
cannot silently go stale as content is added.

**Negative control, re-run at C11 review.** Append `// he grabbed a weapon and killed the
process` to any Swift source and `bash ios/scripts/verify.sh profanity` goes RED, naming the
file and line. It did not, until the review: the hits were piped into a heredoc-fed
`python3 -`, the heredoc owned fd 0, `sys.stdin` was already at EOF, and the check could
never fail. The evidence above is only worth filing because the guard is now proven to fail
on a violation — re-run that probe if you ever touch check 7.

The app also states its own framing on the first-run gate, before anything else is shown:
*"Fiction simulator. Every organisation, host, user and log line in this game is fabricated.
Cases show how a Tier-1 analyst reads evidence — the concepts and the workflow, never a
working technique. Not a training platform, not a certification, and it makes no claims about
hiring or pay. MITRE ATT&CK® ids are lookup labels only."*

---

## 3 · Privacy — **Data Not Collected**

True, and cheap to prove: v1 ships **no analytics SDK, no crash reporter, no account, no
login, no network call**. The only outbound traffic the binary can produce is the
`SFSafariViewController` the player opens deliberately from Settings → About → Privacy policy,
which is Safari's own session and not the app's.

- Every label answer: **Data Not Collected**. No linked data, no tracking, no third-party SDK.
- The save is a single file in the app container, written by an `actor SaveStore`. It never
  leaves the device and is removed with the app.
- The first-run gate says it in the player's own words: *"No account. No network. No
  analytics. Your career is stored only on this device."*

**Guideline 5.1.1(i)** still requires a privacy-policy link at zero collection, in **ASC
metadata and inside the app**. Both are handled:

- In the app: Settings → About prints the policy **summary inline** and the URL as selectable
  text under the link, so the requirement is met by the app itself even offline (P1-4).
- The page: `app/privacy/page.tsx`, a static server component in this repo, prerendered by
  `npm run build` as `○ /privacy`.
- The URL: `https://link26.arvind.workers.dev/privacy` — `MetaID.privacyPolicy`.

> **SUBMISSION BLOCKER (open).** The page is written and builds, but the Worker has no
> workers.dev route enabled and the URL answers **404 · error code 1042** today. Founder step
> 3 in `docs/IOS-BUILD.md`: `npm run deploy` with workers.dev routing on, open the URL,
> confirm the About link, then paste the same URL into the ASC privacy-policy field. A live
> link is required before submission, not before TestFlight.

---

## 4 · Export compliance

`ITSAppUsesNonExemptEncryption = NO`, set in `ios/project.yml` and therefore in the generated
Info.plist, so the export questionnaire is skipped on every upload. Correct as stated: the app
makes no network call of its own and uses no cryptography beyond whatever the OS applies to
its own file storage — no TLS pinning, no bundled crypto library, no custom algorithm.

Other declared Info.plist keys: `UIUserInterfaceStyle = Dark`, `UIRequiresFullScreen = YES`,
`UIViewControllerBasedStatusBarAppearance = YES`, portrait-only,
`LSApplicationCategoryType = public.app-category.puzzle-games`. `UIStatusBarStyle` is dropped
(S11 — dead under view-controller-based appearance). Built with Xcode 26.2 / iOS 26 SDK,
mandatory for uploads since 2026-04-28.

---

## 5 · Notes for Review (2.3.1 — specificity is the requirement)

`DESIGN.md` §6's paragraph, verbatim, with the two amendments SPEC §8 requires: *"haptic
feedback (UIKit feedback generators)"* → **"Core Haptics patterns"**, and the SwiftUI
sentence added.

> SENTRY — SOC is a fictional, offline single-player deduction game about a Tier-1
> security-operations analyst. The player reads fabricated alerts, chooses which fabricated log
> excerpts to consult, and classifies each alert as a true positive, a false positive, or
> authorized (benign) activity; a debrief then explains the reasoning. The content is defensive
> and educational: it teaches how an analyst reads evidence, and never depicts a working attack
> or evasion technique. No real organisations, systems, credentials, or data appear — every
> host, user, domain and log line is invented. Public MITRE ATT&CK® technique identifiers are
> cited as glossary references only. All content is bundled: there is no account, no login, no
> network request, no advertising, no user-generated content, no third-party AI, and no in-app
> purchase. **The app is written in SwiftUI; it contains no web view.** Native features:
> **Core Haptics patterns** for the alert heartbeat and for filing a call, a native splash
> screen, and full offline play with local save. Precedent: Uplink and Hacknet. To reach every
> screen quickly: Desk → Clock in → tap any data source → Make the call → Next alert; the shift
> summary appears after 7 alerts (~12 minutes). Haptics can be turned off in Settings, which
> also contains the fiction disclaimer and the privacy policy link.

**Demo account:** none required — there is no login.
**Attachment:** none required, but a 20-second screen recording of Desk → case → call →
debrief answers the 4.3 question before it is asked.

---

## 6 · Screenshots — 6.9″ (iPhone 17 Pro Max, 1320 × 2868)

Six, in this order. Every one is gameplay; none is a title card. Captured from the simulator
with `make shots`, which pins the status bar to 09:41 with full bars and a charged battery.

| # | screen | why it earns the slot | gate file |
|---|---|---|---|
| 1 | **Debrief** — the stamp, the verdict, `WHY` | the hero: it shows the game is about *reasoning*, not clicking | `debrief-medium.png` |
| 2 | **Case** — alert header, SOURCES tab, coach | the loop in one frame: read, choose a log, decide | `case-medium.png` |
| 3 | **Call sheet** — the four dispositions | the decision the whole game is built around | `call-medium.png` |
| 4 | **Evidence board** — findings, not the tool's guess | the mechanic a reviewer will not have seen elsewhere | `evidence-medium.png` |
| 5 | **Hub** — rank, inbox, five queues | scope: a campaign and a career, not a demo | `hub-medium.png` |
| 6 | **Rank-up** — badge, ladder, Vale's message | progression, and the ceremony that pays it off | `rankup-medium.png` |

Shoot the store set at the **medium** content size from `docs/screenshots/ios/gate/`; the
extra-small, accessibility-medium and 375-pt captures in that directory are the review gate,
not marketing.

App preview video: optional for 1.0. If one is made, record the same six beats in order.

---

## 7 · The 2.1 / 4.3 "lasting value" defence

The only substantial remaining review risk, and the one the 4.2 answer concentrates.

- **Content:** 24 cases across 5 shifts, plus a **precomputed 730-day Daily calendar**, so the
  Hub reads complete with no "coming soon" card on any date a reviewer opens it.
- **Progression:** a four-rank career ladder with standing and cash, a kit purchase, an inbox
  that reacts to how the shift went, and a recorded per-board cleared ledger.
- **Craft:** native SwiftUI, custom type and colour systems, Core Haptics patterns authored
  per event, an ECG that responds to shift state, and screenshots that show gameplay.
- **Framing:** the Notes name **Uplink** and **Hacknet** — the precedent for a text-driven,
  fictional security game on the store.
- **Price:** a small finished game, not a licence or a subscription.
- **Sequencing:** ship a TestFlight build before the polish is finished, so a verdict arrives
  while the codebase is small enough to change. The nine archetype × verdict grid gaps are a
  queued v1.1 content drop in one file.

---

## 8 · Pre-submission checklist

- [ ] `bash ios/scripts/verify.sh` green — all nine checks (this is the gate on the QA jump)
- [ ] `make` green end to end
- [ ] `/privacy` live and opening from Settings → About (§3 blocker)
- [ ] Privacy-policy URL in the ASC metadata field
- [ ] Age-rating questionnaire filed per §2, with the grep result as the evidence
- [ ] Export compliance: `ITSAppUsesNonExemptEncryption = NO` confirmed in the archived plist
- [ ] Six screenshots uploaded per §5
- [ ] Notes for Review pasted per §5
- [ ] **Device haptics pass signed off** in `docs/PLAYTEST-ios.md` (X7 — blocking)
- [ ] Kill-and-relaunch check passed on device (`docs/IOS-BUILD.md` §5)
- [ ] TestFlight internal build installed and played end to end
