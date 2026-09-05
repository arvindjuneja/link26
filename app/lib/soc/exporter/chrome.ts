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

  // ── hub · "The Desk" (§2.3) ───────────────────────────────────────────────
  hubEyebrow: "The desk · your career",
  hubToNextRank: "{gap} to {rank}",
  hubResumeEyebrow: "Resume",
  hubResumeLine: "{shift} · alert {n} of {m} · {t}m",
  hubQueuesEyebrow: "Queues — earn ⬢ to open harder work",
  hubKitEyebrow: "Analyst kit — spend ¢",
  hubInboxEyebrow: "Inbox",
  hubInboxEmpty: "Quiet for now.",
  hubAlertCount: "{n} alerts",
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
  caseFindingsCount: "{n} findings",
  caseSourcePulled: "pulled",
  caseSourceSpoken: "{label}. Answers: {question}. Costs {n} shift-minutes.",
  caseSourceHint: "Pulls this log",
  caseEmptyBoard: "Pull a source to surface findings.",
  caseEmptyBoardBlind: "You can't make the call blind.",
  caseEvidenceFrom: "FROM {source}",
  makeTheCall: "Make the call",
  investigateFirst: "investigate first",
  dockArmed: "{n} findings · {t}m",
  coachEyebrow: "Shift lead · in your ear",
  coachStepCount: "{n}/{m}",
  coachSkip: "skip coaching",

  // ── source sheet (§2.7) ───────────────────────────────────────────────────
  sourceSheetEyebrow: "Pull a data source",
  sourceCost: "COST  {n} shift-min",
  sourceUsed: "USED  {n} / {m}",
  sourcePull: "Pull the log ▸",
  sourceQuerying: "querying {source}…",
  sourceFindingOne: "1 FINDING SURFACED",
  sourceFindingMany: "{n} FINDINGS SURFACED",
  sourceToBoard: "To the board ▸",
  sourcePullAnother: "Pull another",

  // ── call sheet (§2.9) ─────────────────────────────────────────────────────
  callSheetTitle: "MAKE THE CALL",
  callSheetMeta: "{n} sources pulled · {t}m",
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
  summaryBlindOne: "1 call made blind",
  summaryBlindMany: "{n} calls made blind",
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
