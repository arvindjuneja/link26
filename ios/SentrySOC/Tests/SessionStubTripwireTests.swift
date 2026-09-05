import Foundation
import Testing
import SentryCore

@testable import SentrySOC

/// The loud half of `Sources/State/SessionStubs.swift`.
///
/// That file declares `Phase`, `ViewID`, `SessionState`, `SocAction`, `SettingKey`,
/// `Effect`, `SocCue`, `HeartbeatPlan` and `reduce` inside the **app** module. C5
/// ships the real ones inside `SentryCore` (`SPEC.md` §3.2/§3.3). Swift resolves an
/// unqualified name to the current module first, so the day C5 lands there is **no
/// compile error**: the app would silently keep calling the stub reducer — no graded
/// `CallGrade` on the session, no coach cursor — and C7/C8 would keep binding to the
/// wrong `SessionState`. A silent divergence is the worst outcome available here.
///
/// So the tripwire asks the runtime a question the compiler cannot: does
/// `SentryCore` export these types yet? A named Swift type is reachable by its
/// mangled name (`10SentryCore12SessionStateV` — module length, module, name length,
/// name, `V` for struct), and `_typeByName` answers `nil` while it does not exist.
///
/// `nil` is also what a *broken* lookup returns, so the control comes first, exactly
/// as B7's release grep does it: a type that certainly exists in `SentryCore` today
/// must resolve, or this test fails as "the tripwire is broken", not as "all clear".
@Suite("Session stub tripwire")
struct SessionStubTripwireTests {

  private static func coreType(_ name: String) -> Any.Type? {
    _typeByName("10SentryCore\(name.count)\(name)V")
  }

  @Test("SentryCore does not yet declare the Session types — delete the stub when it does")
  func stubsAreStillTheOnlyDeclaration() {
    #expect(
      Self.coreType("ContentPack") != nil,
      """
      The mangled-name lookup no longer resolves a type SentryCore certainly exports. \
      This tripwire is broken and is proving nothing — fix it before trusting it.
      """)

    for name in ["SessionState", "HeartbeatPlan"] {
      #expect(
        Self.coreType(name) == nil,
        """
        SentryCore now exports \(name) (C5 has landed), but the app still declares its \
        own — and the app's wins, silently. DELETE ios/SentrySOC/Sources/State/\
        SessionStubs.swift, then delete this test.
        """)
    }
  }
}
