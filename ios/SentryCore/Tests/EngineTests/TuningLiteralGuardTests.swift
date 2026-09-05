import Foundation
import Testing

@testable import SentryCore

/// D7 / S7, enforced on the sources rather than trusted: **no tuning value appears
/// as a numeric literal in `Sources/SentryCore/Engine/`**, so a designer retune in
/// the exporter is a re-export and zero Swift.
///
/// The check reads the engine sources next to this test, strips comments and string
/// literals — a decision id in a doc comment is prose, not a number the compiler
/// sees — and asserts every remaining numeric token is `0` or `1`. Those two are
/// allowed by S7 and are documented at the head of each engine file: an empty
/// accumulator, an empty count, a single-step increment, and the two division
/// guards the TypeScript itself writes.
@Suite("Tuning literal guard")
struct TuningLiteralGuardTests {

  /// `…/Sources/SentryCore/Engine`, located from this file rather than from the
  /// working directory, so it survives being run from anywhere.
  static var engineDirectory: URL {
    URL(fileURLWithPath: #filePath)                     // …/Tests/EngineTests/<this file>
      .deletingLastPathComponent()                      // …/Tests/EngineTests
      .deletingLastPathComponent()                      // …/Tests
      .deletingLastPathComponent()                      // …/SentryCore (package root)
      .appendingPathComponent("Sources")
      .appendingPathComponent("SentryCore")
      .appendingPathComponent("Engine")
  }

  static func engineSources() throws -> [URL] {
    try FileManager.default
      .contentsOfDirectory(at: engineDirectory, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "swift" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
  }

  @Test("the engine sources are where the spec puts them")
  func sourcesExist() throws {
    let files = try Self.engineSources().map(\.lastPathComponent)
    #expect(files.contains("Grading.swift"))
    #expect(files.contains("ShiftOps.swift"))
    #expect(files.contains("Scoring.swift"))
    // `Trace.swift` in SPEC §1; renamed because SwiftPM derives object-file names
    // from the basename and `Model/Trace.swift` already claims it.
    #expect(files.contains("TraceOps.swift"))
  }

  @Test("no engine source spells a number the tuning owns")
  func noTuningLiterals() throws {
    let allowed: Set<String> = ["0", "1"]
    for url in try Self.engineSources() {
      let code = Self.stripCommentsAndStrings(try String(contentsOf: url, encoding: .utf8))
      let found = Self.numericTokens(in: code)
      let offenders = found.filter { !allowed.contains($0) }
      #expect(
        offenders.isEmpty,
        "\(url.lastPathComponent) spells \(offenders.joined(separator: ", ")) — read it from content.tuning")
    }
  }

  /// The other half of the same promise: the engine actually reaches for the
  /// tuning, rather than having no numbers at all because it does no arithmetic.
  @Test("the engine reads its numbers from the tuning")
  func theEngineReadsTuning() throws {
    let bodies = try Self.engineSources()
      .map { try String(contentsOf: $0, encoding: .utf8) }
      .joined()
    for property in [
      "trace.lockdown", "trace.hunt", "trace.alert", "trace.min", "trace.max",
      "timeBudgetDefault", "grade.tpMissedBreach", "grade.tpUnderContainBreach",
      "grade.tpOverContainNoise", "grade.fpEscalateT2Noise", "grade.fpEscalateIsolateNoise",
      "grade.btpClosedAsFpNoise", "grade.btpEscalateT2Noise", "grade.btpIsolateNoise",
      "shift.cleanAccuracy", "shift.breachedMissedDetections",
    ] {
      #expect(bodies.contains(property), "the engine never reads tuning.\(property)")
    }
  }

  // ── the crude scanner ──────────────────────────────────────────────────────

  /// Enough of a lexer for files this suite also owns the shape of: line comments,
  /// block comments and double-quoted strings become spaces. Escapes inside a
  /// string only matter for `\"`, which is the one that could end it early.
  static func stripCommentsAndStrings(_ source: String) -> String {
    enum Mode { case code, line, block, string }
    var mode = Mode.code
    var out = ""
    let chars = Array(source)
    var i = 0
    while i < chars.count {
      let c = chars[i]
      let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
      switch mode {
      case .code:
        if c == "/", next == "/" { mode = .line; i += 2; continue }
        if c == "/", next == "*" { mode = .block; i += 2; continue }
        if c == "\"" { mode = .string; i += 1; continue }
        out.append(c)
      case .line:
        if c == "\n" { mode = .code; out.append(c) }
      case .block:
        if c == "*", next == "/" { mode = .code; i += 2; continue }
      case .string:
        if c == "\\" { i += 2; continue }
        if c == "\"" { mode = .code }
      }
      i += 1
    }
    return out
  }

  /// Every numeric literal in already-stripped code: a run of digits, optionally
  /// with a fractional part, not glued to an identifier (so `escalateTier2` and
  /// `fpEscalateT2Noise` are names, not numbers).
  static func numericTokens(in code: String) -> [String] {
    var tokens: [String] = []
    let chars = Array(code)
    var i = 0
    while i < chars.count {
      guard chars[i].isNumber else { i += 1; continue }
      let start = i
      while i < chars.count, chars[i].isNumber || chars[i] == "_" { i += 1 }
      if i < chars.count, chars[i] == ".", i + 1 < chars.count, chars[i + 1].isNumber {
        i += 1
        while i < chars.count, chars[i].isNumber { i += 1 }
      }
      let precededByIdentifier =
        start > 0 && (chars[start - 1].isLetter || chars[start - 1] == "_")
      let followedByIdentifier = i < chars.count && (chars[i].isLetter || chars[i] == "_")
      if !precededByIdentifier && !followedByIdentifier {
        tokens.append(String(chars[start..<i]))
      }
    }
    return tokens
  }
}
