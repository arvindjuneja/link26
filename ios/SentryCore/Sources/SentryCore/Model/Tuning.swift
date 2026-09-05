import Foundation

/// Every number the engine branches on (D7). `Sources/SentryCore/Engine/` contains
/// no numeric literal: a designer retune in the exporter's `tuning.ts` is a
/// zero-Swift-change operation, and `TuningExpectationTests` holds the hardcoded
/// table that makes a silent retune loud in review.
///
/// 29 numbers (S8): trace 5 · bpm 4 · timeBudgetDefault 1 · grade 8 · shift 2 ·
/// career 6 · heartbeat 3. Property names are the JSON keys 1:1 — including the
/// upper-case bpm bands, which are the `TraceStatus` raw values.
public struct Tuning: Codable, Sendable, Hashable {
  /// The two meters' bands. Shared with `game/trace.ts`.
  public struct TraceTuning: Codable, Sendable, Hashable {
    public let min: Int
    public let max: Int
    public let alert: Int
    public let hunt: Int
    public let lockdown: Int

    public init(min: Int, max: Int, alert: Int, hunt: Int, lockdown: Int) {
      self.min = min
      self.max = max
      self.alert = alert
      self.hunt = hunt
      self.lockdown = lockdown
    }
  }

  /// Heartbeat rate per band. Keyed by the `TraceStatus` raw values.
  public struct BPMTuning: Codable, Sendable, Hashable {
    public let CALM: Int
    public let ALERT: Int
    public let HUNT: Int
    public let LOCKDOWN: Int

    public init(CALM: Int, ALERT: Int, HUNT: Int, LOCKDOWN: Int) {
      self.CALM = CALM
      self.ALERT = ALERT
      self.HUNT = HUNT
      self.LOCKDOWN = LOCKDOWN
    }

    /// Band → beats per minute, so callers never spell a band twice.
    public subscript(status: TraceStatus) -> Int {
      switch status {
      case .calm: CALM
      case .alert: ALERT
      case .hunt: HUNT
      case .lockdown: LOCKDOWN
      }
    }
  }

  /// The asymmetric consequence model: missing a real threat costs breach, crying
  /// wolf costs noise, and the two are never traded against each other.
  public struct GradeTuning: Codable, Sendable, Hashable {
    public let tpMissedBreach: Int
    public let tpUnderContainBreach: Int
    public let tpOverContainNoise: Int
    public let fpEscalateT2Noise: Int
    public let fpEscalateIsolateNoise: Int
    public let btpClosedAsFpNoise: Int
    public let btpEscalateT2Noise: Int
    public let btpIsolateNoise: Int

    public init(
      tpMissedBreach: Int, tpUnderContainBreach: Int, tpOverContainNoise: Int,
      fpEscalateT2Noise: Int, fpEscalateIsolateNoise: Int, btpClosedAsFpNoise: Int,
      btpEscalateT2Noise: Int, btpIsolateNoise: Int
    ) {
      self.tpMissedBreach = tpMissedBreach
      self.tpUnderContainBreach = tpUnderContainBreach
      self.tpOverContainNoise = tpOverContainNoise
      self.fpEscalateT2Noise = fpEscalateT2Noise
      self.fpEscalateIsolateNoise = fpEscalateIsolateNoise
      self.btpClosedAsFpNoise = btpClosedAsFpNoise
      self.btpEscalateT2Noise = btpEscalateT2Noise
      self.btpIsolateNoise = btpIsolateNoise
    }
  }

  /// The grade rule's two thresholds.
  public struct ShiftTuning: Codable, Sendable, Hashable {
    public let cleanAccuracy: Double
    public let breachedMissedDetections: Int

    public init(cleanAccuracy: Double, breachedMissedDetections: Int) {
      self.cleanAccuracy = cleanAccuracy
      self.breachedMissedDetections = breachedMissedDetections
    }
  }

  /// The economy.
  public struct CareerTuning: Codable, Sendable, Hashable {
    public let cashPerCorrect: Int
    public let cleanBonus: Int
    public let standingClean: Int
    public let standingRough: Int
    public let standingBreached: Int
    public let redRunCut: Int

    public init(
      cashPerCorrect: Int, cleanBonus: Int, standingClean: Int,
      standingRough: Int, standingBreached: Int, redRunCut: Int
    ) {
      self.cashPerCorrect = cashPerCorrect
      self.cleanBonus = cleanBonus
      self.standingClean = standingClean
      self.standingRough = standingRough
      self.standingBreached = standingBreached
      self.redRunCut = redRunCut
    }
  }

  /// The looping haptic (D17): a floor on the period, the idle suspend, and the
  /// offset of the dub from the lub.
  public struct HeartbeatTuning: Codable, Sendable, Hashable {
    public let minPeriodMs: Int
    public let autoSuspendMs: Int
    public let dubOffsetMs: Int

    public init(minPeriodMs: Int, autoSuspendMs: Int, dubOffsetMs: Int) {
      self.minPeriodMs = minPeriodMs
      self.autoSuspendMs = autoSuspendMs
      self.dubOffsetMs = dubOffsetMs
    }
  }

  public let trace: TraceTuning
  public let bpm: BPMTuning
  /// Shift-minutes on the clock when a board is assembled.
  public let timeBudgetDefault: Int
  public let grade: GradeTuning
  public let shift: ShiftTuning
  public let career: CareerTuning
  public let heartbeat: HeartbeatTuning

  public init(
    trace: TraceTuning, bpm: BPMTuning, timeBudgetDefault: Int, grade: GradeTuning,
    shift: ShiftTuning, career: CareerTuning, heartbeat: HeartbeatTuning
  ) {
    self.trace = trace
    self.bpm = bpm
    self.timeBudgetDefault = timeBudgetDefault
    self.grade = grade
    self.shift = shift
    self.career = career
    self.heartbeat = heartbeat
  }
}
