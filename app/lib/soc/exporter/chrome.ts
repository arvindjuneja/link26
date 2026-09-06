// Screen chrome — every letter the app draws that is not case content (S1).
//
// Lifted VERBATIM from `SocConsole.tsx` / `SocOnboarding.tsx` wherever the string
// already exists there (the pinned regions name which); the rest is new iOS copy
// written to `docs/ios/DESIGN.md` §2.3–§2.13 and the §11 voice rule — terse senior
// analyst, second person, no emoji, glyphs only (⬢ ⬡ ¢ ✓ ✗ ▸ ‹ ◉ ◔ ↗ ↔ ·).
//
// Placeholders are named and braced: {n} {m} {pct} {gap} {rank} {cash} {cost}
// {queue} {shift} {date} {source} {severity} {disposition} {standing} {clean}
// {version} {from} {to} {shifts} {cases}. NOT SHA-pinned — this is iOS copy that
// the web has no counterpart for. Routed through the B3 (age rating) and B4
// (pay-figure) guards like everything else.

/**
 * Counted chrome, in both English forms (P1-1).
 *
 * A screen that draws a count cannot mend `"1 findings"` on its own — S1 forbids a
 * Swift literal — so every counted string is authored here as a pair and Swift picks
 * an arm with `CopyPack.plural(_:_:)`. `other` also covers zero, which is the English
 * rule ("0 findings") and is why the arms are named `one`/`other` and not
 * `singular`/`plural`.
 *
 * `{n}` is present in BOTH arms on purpose, even where the singular could hardcode
 * the 1: the caller then interpolates one way for both arms, and a future locale that
 * spells one differently has somewhere to put it.
 */
export const CHROME_PLURALS: Record<string, { one: string; other: string }> = {
  /** Hub queue rows and the daily row. */
  hubAlertCount: { one: "{n} alert", other: "{n} alerts" },
  /** The EVIDENCE tab's eyebrow count and the board's own header. */
  caseFindingsCount: { one: "{n} finding", other: "{n} findings" },
  /** The Dock hint on the case screen, once at least one finding is revealed. */
  dockArmed: { one: "{n} finding · {t}m", other: "{n} findings · {t}m" },
  /** The call sheet's meta line, under MAKE THE CALL. */
  callSheetMeta: { one: "{n} source pulled · {t}m", other: "{n} sources pulled · {t}m" },
  /** A source row read aloud (§4.5). One shift-minute is one, not "1 shift-minutes". */
  caseSourceSpoken: {
    one: "{label}. Answers: {question}. Costs {n} shift-minute.",
    other: "{label}. Answers: {question}. Costs {n} shift-minutes.",
  },
  /** The source sheet's banner when a pull lands. Was `sourceFindingOne`/`Many`. */
  sourceFindings: { one: "{n} FINDING SURFACED", other: "{n} FINDINGS SURFACED" },
  /** The summary's blind-call clause. Was `summaryBlindOne`/`Many`. */
  summaryBlind: { one: "{n} call made blind", other: "{n} calls made blind" },
  /**
   * The results header the pull sequence lands on (FEEL.md §4, end row). The
   * sheet grows to `.large` under it, so it is the first thing a player reads
   * after the log pane stops — and `"RESULTS · 1 findings"` would be the first
   * thing they notice.
   */
  queryResults: { one: "RESULTS · {n} finding", other: "RESULTS · {n} findings" },
};

export const CHROME: Record<string, string> = {
  // ── global chrome ─────────────────────────────────────────────────────────
  wordmark: "SENTRY · SOC",
  statusCalm: "QUIET",
  queueLabel: "QUEUE",
  queueCount: "{n}/{m}",
  standingUnit: "⬢",
  cashUnit: "¢",
  standingHint: "standing — earned by clean shifts; it opens harder queues",
  cashHint: "cash — earned by the work; spent on kit",
  back: "‹ Desk",
  close: "Close",
  minutes: "{n}m",
  // The three numeric formats the deck draws (P1-6). They carry glyphs — `+`, `±`,
  // `→` — and a glyph is copy: authored here, the deck reads the same delta the same
  // way on the debrief meters and on the summary's standing sweep, and S1 stays
  // honest instead of being true only for words.
  deltaFormat: "+{n}",
  deltaZero: "±0",
  rangeArrow: "{from} → {to}",

  // ── hub · "The Desk" (§2.3) ───────────────────────────────────────────────
  hubEyebrow: "The desk · your career",
  hubToNextRank: "{gap} to {rank}",
  hubResumeEyebrow: "Resume",
  hubResumeLine: "{shift} · alert {n} of {m} · {t}m",
  hubQueuesEyebrow: "Queues — earn ⬢ to open harder work",
  hubKitEyebrow: "Analyst kit — spend ¢",
  hubInboxEyebrow: "Inbox",
  hubInboxEmpty: "Quiet for now.",
  hubStart: "Start ▸",
  hubCleared: "cleared · replay",
  hubOpen: "open",
  hubLocked: "⬡ LOCKED · opens at ⬢ {n}",
  hubLockedSpoken: "Locked. Opens at {n} standing.",
  hubDailyLabel: "Daily shift · {date}",
  hubDailyNote: "a fresh board every day",
  hubDailyDone: "done today ✓",
  hubKitOwned: "owned",
  hubKitBuy: "Buy · ¢{cost}",
  hubAbout: "About · fiction simulator · privacy",
  dockResume: "Resume {shift} · alert {n}/{m}",
  dockClockIn: "Clock in · {shift}",
  dockDaily: "Daily shift · {date}",

  // ── shift intro (§2.4) ────────────────────────────────────────────────────
  introWelcome: "Welcome to the desk.",
  introShiftMeta: "{shift} · {n} alerts",

  // ── board sheet (§2.5) ────────────────────────────────────────────────────
  boardEyebrow: "Alert queue",
  boardPressureEyebrow: "Shift pressure",
  boardClock: "{n}m",
  boardTimeValue: "{n} / {m} shift-min",
  boardAbandon: "Abandon shift",
  boardOpenAlert: "Open alert {n} ▸",
  boardBackToAlert: "Back to the alert ▸",
  boardMeterValue: "{n}%",

  // ── case (§2.6) ───────────────────────────────────────────────────────────
  caseSeverityChip: "{severity} · as flagged",
  caseHandoffChip: "↔ red-team run",
  caseAsset: "asset:",
  caseSourcesTab: "SOURCES",
  caseEvidenceTab: "EVIDENCE",
  caseSourcesEyebrow: "Pull a data source — which log answers the question?",
  caseEvidenceEyebrow: "Evidence board",
  caseSourcePulled: "pulled",
  caseSourceHint: "Pulls this log",
  caseEmptyBoard: "Pull a source to surface findings.",
  caseEmptyBoardBlind: "You can't make the call blind.",
  caseEvidenceFrom: "FROM {source}",
  makeTheCall: "Make the call",
  investigateFirst: "investigate first",
  coachEyebrow: "Shift lead · in your ear",
  coachStepCount: "{n}/{m}",
  coachSkip: "skip coaching",

  // ── Vale's interjections (FEEL.md §6) ─────────────────────────────────────
  // Rule-based, no new content: each fires at most once per shift, from a
  // condition the session already knows. They are the difference between a coach
  // panel and a voice in your ear.
  valeFirstPull: "Good — now read what it says, not what the tool guessed.",
  valeThinCall: "You're calling on one card. Your call — but I'd pull one more.",
  /**
   * The leads-to nudge (FEEL.md §7): a mono caption under a key source that has
   * not been pulled yet, once, after a decisive or supporting finding lands. It
   * points without answering — the rule fires on any key source, including the
   * ones that would refute the player's hunch.
   */
  sourceWorthALook: "worth a look",

  // ── source sheet (§2.7) ───────────────────────────────────────────────────
  sourceSheetEyebrow: "Pull a data source",
  sourceCost: "COST  {n} shift-min",
  sourceUsed: "USED  {n} / {m}",
  sourcePull: "Pull the log ▸",
  sourceQuerying: "querying {source}…",
  sourceToBoard: "To the board ▸",
  sourcePullAnother: "Pull another",

  // ── the pull, as a moment (FEEL.md §4) ────────────────────────────────────
  // The 600 ms progress bar becomes a log pane that streams. `queryHeader` is the
  // sheet's eyebrow while it runs; `queryLine1…6` are the fake log lines, four to
  // six of them picked and timed by `Sequences.pullSequence` (seeded by the case,
  // so a replay of the same pull reads the same). Placeholders are the four
  // §4 names and no others — {asset} {source} {n} {window} — because the sheet
  // fills them from the case and the source it already has in hand.
  queryHeader: "QUERYING · {source}",
  queryLine1: "connecting {source}://{asset} …",
  queryLine2: "process tree · {window} window",
  queryLine3: "matching lineage for pid {n}",
  queryLine4: "reading index shard {n}",
  queryLine5: "correlating {asset} over {window}",
  queryLine6: "{n} events",
  /** The window every log line quotes. One value, so the pane stays coherent. */
  queryWindow: "3 h",

  // ── call sheet (§2.9) ─────────────────────────────────────────────────────
  callSheetTitle: "MAKE THE CALL",
  callKeepInvestigating: "Keep investigating",
  callHoldToFile: "Hold to file · {disposition}",
  callFile: "File ▸",
  callConfirm: "Confirm",
  callFileAction: "File this call",

  // ── debrief (§2.10) ───────────────────────────────────────────────────────
  debriefTruth: "truth:",
  debriefWhy: "Why",
  debriefDecisive: "The decisive findings",
  debriefCoverage: "you pulled {n}/{m} of the sources that answer this case",
  debriefBlind: "called on thin evidence — that's luck, not a read. Pull the logs that answer the alert.",
  debriefThorough: "thorough — you pulled the logs that answer this.",
  debriefLearn: "Learn it for real",
  debriefYourCall: "your call:",
  debriefFiled: "Filed: {disposition}",
  debriefNext: "Next alert ▸",
  debriefEnd: "End shift ▸",

  // ── shift summary (§2.11) ─────────────────────────────────────────────────
  statAccuracy: "Accuracy",
  statCalls: "Calls",
  statMissed: "Missed threats",
  statFalseEscalations: "False escalations",
  summaryPayout: "Payout",
  summaryCash: "+{n} ¢",
  summaryStanding: "+{n} ⬢ standing",
  summaryPromoted: "promoted → {rank}",
  summaryUnlocked: "UNLOCKED",
  summaryUnlockedLine: "New queue unlocked — {queue}",
  summaryBoard: "The board",
  summaryBack: "Back to the desk ▸",

  // ── rank-up / finale (§2.12) ──────────────────────────────────────────────
  rankUpEyebrow: "Promoted",
  rankUpFinaleEyebrow: "The desk is yours",
  rankUpTransition: "{from} → {to}",
  rankUpRecap: "{shifts} shifts · {clean} clean · {cases} cases read",
  rankUpContinue: "Continue ▸",

  // ── settings · about · licences (§2.13) ───────────────────────────────────
  settingsTitle: "Settings",
  settingsFeel: "Feel",
  settingsHaptics: "Haptics · heartbeat + feedback",
  // FEEL.md §9. Sound is on by default and mixes with whatever the player is
  // already listening to; the heartbeat is a haptic channel first, so its sound
  // is opt-in and says so.
  settingsSound: "Sound · cues and room tone",
  settingsHeartbeatSound: "Heartbeat sound · a low thump",
  // FEEL.md §6. The DEF-A taxonomy is the first card of shift 1 and is not repeated
  // on every board after it — so it needs a door, and this is the door. Phrased as a
  // re-read rather than as help: the player already met these rules at 08:00 on their
  // first shift, and this row is for the shift where they want them again.
  settingsRules: "Read the rules again",
  settingsHoldToFile: "Hold to file · off = tap twice",
  settingsCoaching: "Coaching on the first alert",
  settingsMotion: "Motion",
  settingsMotionValue: "follows system",
  settingsDesk: "Desk",
  settingsDeskLine: "{rank} · ⬢ {standing} · ¢ {cash} · {clean} clean",
  settingsReset: "Reset career…",
  settingsResetTitle: "Reset career",
  settingsResetBody: "This clears your rank, standing, cash and kit on this device. It can't be undone.",
  settingsResetConfirm: "Reset",
  settingsCancel: "Cancel",
  settingsSaveNotice: "Your last save couldn't be read, so the desk started fresh. The old file is kept on the device.",
  aboutEyebrow: "About · SENTRY — SOC {version}",
  aboutFictionTitle: "Fiction simulator",
  aboutPrivacyTitle: "Privacy",
  aboutPrivacyLink: "Privacy policy ↗",
  aboutPromiseTitle: "Our promise",
  aboutCreditsTitle: "Credits",
  licencesTitle: "Licences",

  // ── kit sheet ─────────────────────────────────────────────────────────────
  kitTitle: "Analyst kit",
  kitSpend: "Spend ¢ on kit that makes you faster.",

  // ── abandon (§2.5) ────────────────────────────────────────────────────────
  abandonTitle: "Abandon shift",
  abandonBody: "You lose this queue's progress. Your career is not touched.",
  abandonConfirm: "Abandon",
  abandonCancel: "Keep working",
};
