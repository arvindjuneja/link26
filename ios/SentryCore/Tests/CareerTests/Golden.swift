import Foundation
import SentryFixtures
import Testing

@testable import SentryCore

// A parameterised failure should name its row, not print the whole struct. The
// library cannot conform to a Testing protocol — `SentryCore` imports Foundation
// only (D15) — so the conformances live here.

extension CareerAwardRow: CustomTestStringConvertible {
  public var testDescription: String { name }
}

extension CareerBuyRow: CustomTestStringConvertible {
  public var testDescription: String { name }
}

extension CareerRedRunRow: CustomTestStringConvertible {
  public var testDescription: String { name }
}

extension HandlerScenario: CustomTestStringConvertible {
  public var testDescription: String { name }
}

/// Shared handles for the career suites. `ContentPack.bundled` traps on a decode
/// failure, so touching it is the first assertion this target makes.
enum Golden {
  static let pack = ContentPack.bundled
  static let copy = ContentPack.bundled.copy
  static let rules = CareerRules(content: ContentPack.bundled)
  static let voice = HandlerVoice(content: ContentPack.bundled)

  struct MissingFixture: Error, CustomStringConvertible {
    let name: String
    var description: String { "SentryFixtures is missing \(name).json" }
  }

  static func decode<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
    guard let url = SentryFixtures.bundle.url(forResource: name, withExtension: "json") else {
      throw MissingFixture(name: name)
    }
    return try JSONDecoder().decode(type, from: try Data(contentsOf: url))
  }

  /// `career.json` — the 12-award ladder walk, `awardRedRun` and the three shop rows.
  static func career() throws -> CareerFile { try decode("career", as: CareerFile.self) }

  /// `handler.json` — 14 scenarios, each rendered under both feature sets (S3).
  static func handler() throws -> HandlerFile { try decode("handler", as: HandlerFile.self) }

  /// Every shift open at `c`, in bundle order — the exporter's `unlockedIds`.
  static func unlockedIds(_ c: CareerState) -> [String] {
    pack.shifts.filter { rules.isUnlocked(c, $0) }.map(\.id)
  }

  /// Every field of a message, so a failure prints the one that moved rather than
  /// two paragraphs that differ somewhere.
  static func expectEqual(
    _ actual: [HandlerMessage], _ expected: [HandlerMessage],
    _ scenario: String, sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(
      actual.map(\.id) == expected.map(\.id), "\(scenario): message ids",
      sourceLocation: sourceLocation)
    for (a, e) in zip(actual, expected) {
      #expect(a.from == e.from, "\(scenario)/\(e.id): from", sourceLocation: sourceLocation)
      #expect(a.role == e.role, "\(scenario)/\(e.id): role", sourceLocation: sourceLocation)
      #expect(a.tone == e.tone, "\(scenario)/\(e.id): tone", sourceLocation: sourceLocation)
      #expect(a.subject == e.subject, "\(scenario)/\(e.id): subject", sourceLocation: sourceLocation)
      #expect(a.body == e.body, "\(scenario)/\(e.id): body", sourceLocation: sourceLocation)
    }
  }
}
