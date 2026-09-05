import Foundation
import OSLog
import SentryCore

/// All file I/O in the app (§4.3).
///
/// Two files in `Application Support/SentrySOC/`, both versioned JSON:
///
/// | file | written | policy |
/// |---|---|---|
/// | `career.json` | on settle, on buy, on reset | atomic · `career.bak.json` rotated before each overwrite · `.completeFileProtectionUnlessOpen` |
/// | `session.json` | after `PULL_SOURCE`/`MAKE_CALL`, coalesced by `EffectRunner` to ≤1 write per 250 ms, and on `scenePhase == .background` | same, deleted on settle or abandon |
///
/// **Reads are synchronous and `nonisolated`; every write hops to the actor.** That
/// split is the point: `SentrySOCApp.init()` hydrates a ~4 KB file before the first
/// frame, which deletes risk R6 ("hydration races the UI and overwrites a good
/// save") as a *class* — natively there is no race to lose — while writes still
/// leave the main thread. `CareerState` and the snapshot are `Sendable` value types,
/// so the hop is free.
///
/// **Corruption policy.** A decode failure renames the file to
/// `career.corrupt-<epoch>.json` and starts from `CareerState.initial` with a
/// one-shot Settings notice. The file is never overwritten, and `saveCareer` never
/// writes an initial career except behind the double-confirmed reset — a bad parse
/// must not silently become a wiped save.
actor SaveStore {

  // MARK: - Shape on disk

  /// The version of the envelope, not of the payload. A payload gains fields
  /// through `decodeIfPresent` defaults (below); this number moves only for a
  /// change no lenient decode can absorb.
  static let schemaVersion = 1

  /// `{ "schemaVersion": 1, "savedAt": …, "payload": { … } }`.
  nonisolated struct Envelope<Payload: Codable & Sendable>: Codable, Sendable {
    var schemaVersion: Int
    var savedAt: Date
    var payload: Payload
  }

  /// What a launch found on disk.
  nonisolated struct Hydration: Sendable {
    var career: CareerState
    var session: SessionSnapshot?
    /// The career file was unreadable and has been set aside — Settings shows the
    /// one-shot notice.
    var careerWasCorrupt: Bool
    /// The snapshot was unreadable and has been set aside. No notice: an
    /// interrupted shift is a smaller loss than a career, and the hub simply shows
    /// no Resume card.
    var sessionWasCorrupt: Bool

    static let empty = Hydration(
      career: .initial, session: nil, careerWasCorrupt: false, sessionWasCorrupt: false)
  }

  // MARK: - Location

  nonisolated let directory: URL

  private static let careerFile = "career.json"
  private static let careerBackupFile = "career.bak.json"
  private static let sessionFile = "session.json"

  private static let log = Logger(subsystem: "pl.oumm.sentry.soc", category: "SaveStore")

  init(directory: URL? = nil) {
    self.directory = directory ?? Self.defaultDirectory
  }

  /// `Application Support/SentrySOC/`. Not `Documents`: the save is app-managed
  /// state, not a user document, and it should not appear in Files.
  static var defaultDirectory: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first ?? URL.temporaryDirectory
    return base.appending(path: "SentrySOC", directoryHint: .isDirectory)
  }

  // MARK: - Hydration (synchronous, before the first frame)

  /// Reads both files. Never throws: a launch that cannot read its save still
  /// launches, into a fresh career, with the unreadable bytes preserved beside it.
  nonisolated func hydrate() -> Hydration {
    Self.ensureDirectory(directory)
    var result = Hydration.empty

    switch Self.read(CareerRecord.self, at: directory.appending(path: Self.careerFile)) {
    case .loaded(let record):
      result.career = record.state
    case .absent:
      break
    case .corrupt:
      Self.quarantine(directory.appending(path: Self.careerFile))
      // A rotated backup is the whole reason the backup exists.
      switch Self.read(CareerRecord.self, at: directory.appending(path: Self.careerBackupFile)) {
      case .loaded(let record):
        result.career = record.state
      case .absent, .corrupt:
        result.careerWasCorrupt = true
      }
      if result.careerWasCorrupt == false {
        Self.log.notice("career.json was unreadable; recovered from career.bak.json")
      }
    }

    switch Self.read(SessionSnapshot.self, at: directory.appending(path: Self.sessionFile)) {
    case .loaded(let snapshot):
      result.session = snapshot
    case .absent:
      break
    case .corrupt:
      Self.quarantine(directory.appending(path: Self.sessionFile))
      result.sessionWasCorrupt = true
    }

    return result
  }

  // MARK: - Writes

  func saveCareer(_ career: CareerState) {
    write(CareerRecord(career), to: Self.careerFile, rotatingBackup: true)
  }

  func saveSession(_ snapshot: SessionSnapshot) {
    write(snapshot, to: Self.sessionFile, rotatingBackup: false)
  }

  func clearSession() {
    try? FileManager.default.removeItem(at: directory.appending(path: Self.sessionFile))
  }

  /// The double-confirmed reset, and the only path that may write an initial career.
  func resetCareer() {
    clearSession()
    write(CareerRecord(.initial), to: Self.careerFile, rotatingBackup: true)
  }

  private func write(_ payload: some Codable & Sendable, to name: String, rotatingBackup: Bool) {
    Self.ensureDirectory(directory)
    let url = directory.appending(path: name)
    let envelope = Envelope(
      schemaVersion: Self.schemaVersion, savedAt: Date(), payload: payload)
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]     // byte-stable, so a diff is readable
      encoder.dateEncodingStrategy = .iso8601
      let data = try encoder.encode(envelope)
      if rotatingBackup { Self.rotateBackup(from: url, to: directory.appending(path: Self.careerBackupFile)) }
      // `.atomic` writes a temp file and renames — an interrupted write leaves the
      // old bytes, never a half file.
      try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    } catch {
      Self.log.error("failed to write \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: - Plumbing

  private nonisolated enum ReadResult<T> {
    case loaded(T)
    case absent
    case corrupt
  }

  private static func read<T: Codable & Sendable>(_ type: T.Type, at url: URL) -> ReadResult<T> {
    guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
      return .absent
    }
    do {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      let data = try Data(contentsOf: url)
      return .loaded(try decoder.decode(Envelope<T>.self, from: data).payload)
    } catch {
      log.error("\(url.lastPathComponent, privacy: .public) did not decode: \(error.localizedDescription, privacy: .public)")
      return .corrupt
    }
  }

  private static func quarantine(_ url: URL) {
    let stem = url.deletingPathExtension().lastPathComponent
    let target = url.deletingLastPathComponent()
      .appending(path: "\(stem).corrupt-\(Int(Date().timeIntervalSince1970)).json")
    try? FileManager.default.moveItem(at: url, to: target)
    log.notice("set aside \(url.lastPathComponent, privacy: .public) as \(target.lastPathComponent, privacy: .public)")
  }

  private static func rotateBackup(from url: URL, to backup: URL) {
    let fm = FileManager.default
    guard fm.fileExists(atPath: url.path(percentEncoded: false)) else { return }
    try? fm.removeItem(at: backup)
    try? fm.copyItem(at: url, to: backup)
  }

  private static func ensureDirectory(_ url: URL) {
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }
}

// MARK: - The mid-shift snapshot

/// Enough to put the player back exactly where the phone died (§4.3). Written after
/// every commit and on backgrounding; deleted the moment the shift settles.
nonisolated struct SessionSnapshot: Codable, Sendable, Hashable {
  var phase: Phase
  var shift: ShiftState
  var queried: [String]
  var status: TraceStatus

  init(phase: Phase, shift: ShiftState, queried: [String], status: TraceStatus) {
    self.phase = phase
    self.shift = shift
    self.queried = queried
    self.status = status
  }

  /// `nil` unless there is a board to come back to. An open sheet is not restored:
  /// coming back from a cold launch into a modal is disorienting, and every sheet is one
  /// tap away from the phase underneath it.
  init?(_ session: SessionState) {
    guard let shift = session.shift,
          session.phase == .investigating || session.phase.isDebrief
    else { return nil }
    self.init(
      phase: session.phase, shift: shift, queried: session.queried, status: session.status)
  }

  /// The hub's Resume card hands this back. The snapshot is never auto-entered
  /// (§2.1) — walking back into a half-finished shift unasked is how a player
  /// loses the thread.
  var session: SessionState {
    SessionState(
      phase: phase, view: nil, shift: shift, queried: queried,
      pendingDisposition: nil, status: status)
  }
}

// MARK: - The career record

/// The save format for `CareerState`, with the two properties Codable does not give
/// for free:
///
/// 1. **Missing fields default** from `CareerState.initial`, mirroring `loadCareer`'s
///    object spread in the web — so a save written before a field existed still loads.
/// 2. **Unknown fields survive.** Keys this build does not know are carried in
///    `extras` and written back out, so an older build cannot silently strip a newer
///    build's data from the file. Codable alone would drop them.
nonisolated struct CareerRecord: Codable, Sendable, Hashable {
  var cash: Int
  var standing: Int
  var shiftsCleaned: Int
  var redRunsDone: Int
  var gear: [String]
  var dailyDoneOn: String?
  /// Keys written by a build that knew more than this one.
  var extras: [String: JSONValue]

  init(_ state: CareerState, extras: [String: JSONValue] = [:]) {
    cash = state.cash
    standing = state.standing
    shiftsCleaned = state.shiftsCleaned
    redRunsDone = state.redRunsDone
    gear = state.gear
    dailyDoneOn = state.dailyDoneOn
    self.extras = extras
  }

  var state: CareerState {
    CareerState(
      cash: cash, standing: standing, shiftsCleaned: shiftsCleaned,
      redRunsDone: redRunsDone, gear: gear, dailyDoneOn: dailyDoneOn)
  }

  private static let knownKeys: Set<String> = [
    "cash", "standing", "shiftsCleaned", "redRunsDone", "gear", "dailyDoneOn",
  ]

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: DynamicKey.self)
    let initial = CareerState.initial
    cash = try container.decodeIfPresent(Int.self, forKey: "cash") ?? initial.cash
    standing = try container.decodeIfPresent(Int.self, forKey: "standing") ?? initial.standing
    shiftsCleaned =
      try container.decodeIfPresent(Int.self, forKey: "shiftsCleaned") ?? initial.shiftsCleaned
    redRunsDone =
      try container.decodeIfPresent(Int.self, forKey: "redRunsDone") ?? initial.redRunsDone
    gear = try container.decodeIfPresent([String].self, forKey: "gear") ?? initial.gear
    dailyDoneOn = try container.decodeIfPresent(String.self, forKey: "dailyDoneOn")

    var carried: [String: JSONValue] = [:]
    for key in container.allKeys where !Self.knownKeys.contains(key.stringValue) {
      carried[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
    }
    extras = carried
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: DynamicKey.self)
    try container.encode(cash, forKey: "cash")
    try container.encode(standing, forKey: "standing")
    try container.encode(shiftsCleaned, forKey: "shiftsCleaned")
    try container.encode(redRunsDone, forKey: "redRunsDone")
    try container.encode(gear, forKey: "gear")
    try container.encodeIfPresent(dailyDoneOn, forKey: "dailyDoneOn")
    for (key, value) in extras where !Self.knownKeys.contains(key) {
      try container.encode(value, forKey: DynamicKey(key))
    }
  }
}

/// A coding key built from a string — how `extras` reads keys it has never heard of.
nonisolated struct DynamicKey: CodingKey, ExpressibleByStringLiteral, Sendable {
  var stringValue: String
  var intValue: Int? { nil }

  init(_ value: String) { stringValue = value }
  init(stringLiteral value: String) { stringValue = value }
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { nil }
}

/// Any JSON value, so an unknown key round-trips byte-for-byte instead of being
/// dropped. Integers decode as integers so `5` never comes back as `5.0`.
nonisolated enum JSONValue: Codable, Sendable, Hashable {
  case null
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      self = .int(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "unrepresentable JSON value")
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .int(let value): try container.encode(value)
    case .double(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }
}
