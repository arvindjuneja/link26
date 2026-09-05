import SentryCore

// ─────────────────────────────────────────────────────────────────────────────
//  The session vocabulary, spelled once in the app module.
//
//  These are **aliases, not declarations**: `Phase` here IS `SentryCore.Phase`, the
//  same type with the same identity, so there is nothing for the app to diverge
//  from. (That is the difference between this file and the `SessionStubs.swift`
//  C5 deleted, which redeclared the types and would have shadowed the real ones
//  silently.)
//
//  **Why it exists at all.** `Sources/Services/ScreenRegistry.swift` names `Phase`,
//  `ViewID`, `SocCue` and `HeartbeatPlan` in its factory protocols and imports only
//  SwiftUI. It belongs to C6, whose ticket is closed, and §11 forbids C5 from
//  editing a foreign file — so the one-line `import SentryCore` it wants is a
//  request to the lead, not an edit this ticket may make. A top-level typealias is
//  module-scoped, so this file supplies the names without touching C6's.
//
//  **REQUEST TO THE LEAD:** add `import SentryCore` to
//  `ios/SentrySOC/Sources/Services/ScreenRegistry.swift` and delete this file. It is
//  three lines of indirection standing in for one line of import.
// ─────────────────────────────────────────────────────────────────────────────

typealias Phase = SentryCore.Phase
typealias ViewID = SentryCore.ViewID
typealias SocCue = SentryCore.SocCue
typealias HeartbeatPlan = SentryCore.HeartbeatPlan
