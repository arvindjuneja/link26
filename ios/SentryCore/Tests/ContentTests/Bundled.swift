import Foundation
import SentryFixtures
import Testing

@testable import SentryCore

// A parameterised failure should name the row, not print the whole case. The
// library cannot conform to a Testing protocol — `SentryCore` imports Foundation
// only (D15) — so the conformance lives here, where the test targets share it.
extension SocCase: CustomTestStringConvertible {
  public var testDescription: String { id }
}

extension ShiftDef: CustomTestStringConvertible {
  public var testDescription: String { id }
}

/// Shared handles for the content suites. `ContentPack.bundled` traps on a decode
/// failure, so simply touching it is the first assertion this target makes.
enum Bundled {
  static let pack = ContentPack.bundled
  static let copy = ContentPack.bundled.copy
  static let daily = ContentPack.bundled.daily

  /// The seven generated fixture files (D23) — test-only, never in the app.
  static let fixtureNames = [
    "career", "grades-synthetic", "grades", "handler", "scoring", "shift-runs", "trace",
  ]

  struct MissingFixture: Error, CustomStringConvertible {
    let name: String
    var description: String { "SentryFixtures is missing \(name).json" }
  }

  /// Just the two fields every one of the ten generated files carries.
  struct StampProbe: Codable, Sendable, Hashable {
    let schemaVersion: Int
    let contentHash: String
  }

  static func fixtureData(_ name: String) throws -> Data {
    guard let url = SentryFixtures.bundle.url(forResource: name, withExtension: "json") else {
      throw MissingFixture(name: name)
    }
    return try Data(contentsOf: url)
  }

  static func decodeFixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
    try JSONDecoder().decode(type, from: try fixtureData(name))
  }

  /// A gregorian UTC calendar, so the daily-board arithmetic is asserted against a
  /// fixed frame rather than whatever zone the machine is in.
  static let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
  }()
}
