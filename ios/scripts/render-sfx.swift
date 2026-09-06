#!/usr/bin/env swift
//
// SENTRY — SOC · the sound bank, synthesised (F2a, `docs/ios/FEEL.md` §9).
//
//     swift ios/scripts/render-sfx.swift [--out <dir>] [--check]
//
// Writes every asset of the §9 table into `ios/SentrySOC/Resources/Sounds/` as
// **44.1 kHz mono 16-bit PCM WAV**. `--check` renders into a temporary directory and
// diffs, so CI can prove the committed bytes are what this file produces.
//
// **Why synthesis and not samples.** §9: "generated procedurally … so there is no
// licensing surface — no downloaded samples". Every waveform below is arithmetic on
// a seeded generator; there is nothing here to attribute, nothing to licence, and
// nothing a store review can ask about. It also means the sound bank is a *diffable
// text file* — a designer retunes `stamp` by moving a number, re-runs this, and the
// review sees which number moved.
//
// **Determinism.** No `Date`, no `SystemRandomNumberGenerator`, no floating-point
// reduction whose order depends on a scheduler. The noise comes from a SplitMix64
// seeded per asset by its own name, so the same asset is the same bytes on any
// machine, and adding an asset cannot change an existing one.
//
// **Level.** Each asset is normalised to a common loudness rather than a common
// peak: RMS to −16 dBFS (the "−16 LUFS-ish" of §9 — this is a peak/RMS
// approximation, not a gated ITU-R BS.1770 measurement, and it is deliberately the
// cheaper one because these are 20–600 ms one-shots that a loudness gate would
// mostly discard), then a ceiling at −1 dBFS so a click cannot clip. The result is
// that a `tick` and a `verdict-good` chord sit at the same apparent level in the
// player's ear, which is the only reason a common target is worth having.
//
// **Foundation only**, no AVFoundation: a WAV header is 44 bytes, and writing them
// by hand is what keeps this script runnable as `swift <file>` with no project, no
// simulator and no audio device.

import Foundation

// MARK: - Constants

let sampleRate = 44_100.0
/// §9: "All assets short (≤ 600 ms)". Asserted per asset — the room tone is the one
/// documented exception, because it is a *loop* and not a cue.
let cueDurationCapSeconds = 0.600
/// RMS target — 10^(−16/20).
let targetRMS = 0.158_489_319
/// Peak ceiling — 10^(−1/20).
let peakCeiling = 0.891_250_938

// MARK: - Seeded noise (SplitMix64, same generator as `SentryCore.SeededRandom`)

struct Noise {
  private var state: UInt64

  init(seed: String) {
    // FNV-1a over the asset's own name: adding an asset cannot move another one.
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in seed.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x100_0000_01b3
    }
    state = hash
  }

  private mutating func next() -> UInt64 {
    state = state &+ 0x9e37_79b9_7f4a_7c15
    var z = state
    z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
    z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
    return z ^ (z >> 31)
  }

  /// Uniform white noise in −1…1.
  mutating func white() -> Double {
    Double(next() >> 11) / Double(1 << 53) * 2 - 1
  }
}

// MARK: - Building blocks

/// A buffer of `seconds` of silence, ready to be written into.
func buffer(_ seconds: Double) -> [Double] {
  [Double](repeating: 0, count: Int(seconds * sampleRate))
}

func time(_ index: Int) -> Double { Double(index) / sampleRate }

/// Exponential decay — the envelope almost every percussive asset wears.
func decay(_ t: Double, _ tau: Double) -> Double { exp(-t / tau) }

/// A short attack so nothing starts with a DC step (which reads as a click of its
/// own, on top of the click you meant).
func attack(_ t: Double, _ seconds: Double) -> Double {
  seconds <= 0 ? 1 : min(1, t / seconds)
}

func sine(_ frequency: Double, _ t: Double, phase: Double = 0) -> Double {
  sin(2 * .pi * frequency * t + phase)
}

/// A one-pole low-pass, applied in place. `cutoff` in Hz.
func lowPass(_ samples: inout [Double], cutoff: Double) {
  let dt = 1 / sampleRate
  let rc = 1 / (2 * .pi * cutoff)
  let alpha = dt / (rc + dt)
  var previous = 0.0
  for index in samples.indices {
    previous += alpha * (samples[index] - previous)
    samples[index] = previous
  }
}

/// A one-pole high-pass, applied in place. Keeps a thud out of the sub-sonic range
/// where a phone speaker can only turn it into distortion.
func highPass(_ samples: inout [Double], cutoff: Double) {
  let dt = 1 / sampleRate
  let rc = 1 / (2 * .pi * cutoff)
  let alpha = rc / (rc + dt)
  var previousIn = 0.0
  var previousOut = 0.0
  for index in samples.indices {
    let input = samples[index]
    previousOut = alpha * (previousOut + input - previousIn)
    previousIn = input
    samples[index] = previousOut
  }
}

/// Mix `source` into `destination` starting at `atSeconds`.
func mix(_ destination: inout [Double], _ source: [Double], at atSeconds: Double, gain: Double = 1) {
  let offset = Int(atSeconds * sampleRate)
  for (index, value) in source.enumerated() {
    let target = offset + index
    guard target >= 0, target < destination.count else { continue }
    destination[target] += value * gain
  }
}

/// RMS to −16 dBFS, then a −1 dBFS ceiling. Silence is left alone rather than
/// divided by zero.
func normalise(_ samples: inout [Double]) {
  guard !samples.isEmpty else { return }
  let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
  let rms = (sumOfSquares / Double(samples.count)).squareRoot()
  guard rms > 1e-9 else { return }
  var gain = targetRMS / rms
  let peak = samples.reduce(0) { max($0, abs($1)) }
  if peak * gain > peakCeiling { gain = peakCeiling / peak }
  for index in samples.indices { samples[index] *= gain }
}

/// A short fade at both ends, so no asset begins or ends on a non-zero sample. Two
/// milliseconds is inaudible and is the difference between a clean one-shot and a
/// click every time the buffer is scheduled.
func deClick(_ samples: inout [Double], seconds: Double = 0.002) {
  let count = min(Int(seconds * sampleRate), samples.count / 2)
  guard count > 0 else { return }
  for index in 0..<count {
    let ramp = Double(index) / Double(count)
    samples[index] *= ramp
    samples[samples.count - 1 - index] *= ramp
  }
}

// MARK: - The assets

/// A dry click: a filtered noise transient with a very fast decay. The `select` of
/// §9 and the body of every other tick in the bank.
func click(seed: String, seconds: Double, tau: Double, cutoff: Double, tone: Double) -> [Double] {
  var out = buffer(seconds)
  var noise = Noise(seed: seed)
  for index in out.indices {
    let t = time(index)
    out[index] = (noise.white() * 0.8 + sine(tone, t) * 0.2) * decay(t, tau)
  }
  lowPass(&out, cutoff: cutoff)
  highPass(&out, cutoff: 180)
  return out
}

/// A soft mallet: a sine with a touch of its second partial and a wooden click on
/// the attack. Three of these, a fifth apart, are §9's `finding-land`.
func mallet(seed: String, frequency: Double, seconds: Double) -> [Double] {
  var out = buffer(seconds)
  var noise = Noise(seed: seed)
  for index in out.indices {
    let t = time(index)
    let body =
      sine(frequency, t) * decay(t, seconds * 0.30)
      + sine(frequency * 2.01, t) * 0.28 * decay(t, seconds * 0.12)
    let strike = noise.white() * decay(t, 0.004) * 0.35
    out[index] = (body + strike) * attack(t, 0.001)
  }
  lowPass(&out, cutoff: 5_000)
  return out
}

/// Two notes struck together — §9's verdict chords. `ratio` is the second note
/// against the first: 1.25 major third, 1.335 suspended fourth, 1.06 minor second.
func chord(seed: String, root: Double, ratio: Double, seconds: Double) -> [Double] {
  var out = buffer(seconds)
  for index in out.indices {
    let t = time(index)
    let a = sine(root, t) * decay(t, seconds * 0.40)
    let b = sine(root * ratio, t) * decay(t, seconds * 0.34)
    let air = sine(root * 2, t) * 0.15 * decay(t, seconds * 0.16)
    out[index] = (a + b + air) * attack(t, 0.006)
  }
  lowPass(&out, cutoff: 7_000)
  _ = seed
  return out
}

/// A sub thud: a pitch envelope falling from `from` to `to` over the first tenth of
/// the asset, which is what makes a sine read as a drum instead of a beep.
func thud(seed: String, from: Double, to: Double, seconds: Double) -> [Double] {
  var out = buffer(seconds)
  var noise = Noise(seed: seed)
  var phase = 0.0
  for index in out.indices {
    let t = time(index)
    let sweep = to + (from - to) * decay(t, seconds * 0.10)
    phase += 2 * .pi * sweep / sampleRate
    let body = sin(phase) * decay(t, seconds * 0.28)
    let knock = noise.white() * decay(t, 0.006) * 0.25
    out[index] = (body + knock) * attack(t, 0.0015)
  }
  lowPass(&out, cutoff: 900)
  highPass(&out, cutoff: 35)
  return out
}

/// A filtered noise burst — §9's `query-start`, and the paper in `file` and `stamp`.
func air(seed: String, seconds: Double, tau: Double, cutoff: Double, highCut: Double) -> [Double] {
  var out = buffer(seconds)
  var noise = Noise(seed: seed)
  for index in out.indices {
    let t = time(index)
    out[index] = noise.white() * decay(t, tau) * attack(t, 0.004)
  }
  lowPass(&out, cutoff: cutoff)
  highPass(&out, cutoff: highCut)
  return out
}

/// A sonar ping: a sine with a long tail and a metallic partial, pitched by `step`.
func ping(step: Int) -> [Double] {
  let seconds = 0.300
  // A semitone per alert: seven alerts walk up a fifth, which is far enough to hear
  // the queue filling and near enough that the seventh is not a different sound.
  let frequency = 880.0 * pow(2.0, Double(step) / 12.0)
  var out = buffer(seconds)
  for index in out.indices {
    let t = time(index)
    let body = sine(frequency, t) * decay(t, 0.075)
    let partial = sine(frequency * 2.76, t) * 0.18 * decay(t, 0.030)
    out[index] = (body + partial) * attack(t, 0.002)
  }
  lowPass(&out, cutoff: 9_000)
  return out
}

/// §9's room tone: filtered noise, and the one asset that is a **loop** rather than
/// a cue — so it is longer than the 600 ms cap, which applies to one-shots. It ends
/// where it begins: the last 200 ms cross-fades into the first, so the seam is
/// inaudible however long a shift runs.
func roomTone() -> [Double] {
  let seconds = 4.0
  let count = Int(seconds * sampleRate)
  let crossfade = Int(0.200 * sampleRate)
  var raw = [Double](repeating: 0, count: count + crossfade)
  var noise = Noise(seed: "room-tone")
  // Two bands: a low hum for the room and a hiss for the air in it.
  var lowBand = raw
  var hiss = raw
  for index in raw.indices {
    let value = noise.white()
    lowBand[index] = value
    hiss[index] = value
  }
  lowPass(&lowBand, cutoff: 160)
  lowPass(&hiss, cutoff: 2_400)
  highPass(&hiss, cutoff: 700)
  for index in raw.indices {
    raw[index] = lowBand[index] * 1.0 + hiss[index] * 0.22
  }

  var out = Array(raw[0..<count])
  for index in 0..<crossfade {
    let ramp = Double(index) / Double(crossfade)
    // Equal-power, so the seam does not dip in level the way a linear fade would.
    let head = out[index]
    let tail = raw[count + index]
    out[index] = head * sin(ramp * .pi / 2) + tail * cos(ramp * .pi / 2)
  }
  return out
}

// MARK: - The bank

struct Asset {
  let name: String
  /// `true` for the room tone, which loops and is therefore not a cue at all.
  let isLoop: Bool
  /// The cap this asset is held to. §9's headline is "≤ 600 ms", and the same §9
  /// table then gives `rankup` a **700 ms** rising figure — the document's own
  /// exception, written into the row rather than inferred here. Every other cue is
  /// held to 600.
  let capSeconds: Double
  let render: () -> [Double]

  init(
    _ name: String, isLoop: Bool = false, cap: Double = cueDurationCapSeconds,
    _ render: @escaping () -> [Double]
  ) {
    self.name = name
    self.isLoop = isLoop
    self.capSeconds = cap
    self.render = render
  }
}

let assets: [Asset] = [
  // arrive · low pad + click, 400 ms.
  Asset("arrive") {
    var out = buffer(0.400)
    for index in out.indices {
      let t = time(index)
      let pad =
        (sine(110, t) + sine(164.81, t) * 0.6 + sine(220, t) * 0.3)
        * decay(t, 0.16) * attack(t, 0.030)
      out[index] = pad * 0.55
    }
    lowPass(&out, cutoff: 1_400)
    mix(&out, click(seed: "arrive-click", seconds: 0.040, tau: 0.006, cutoff: 6_500, tone: 2_100),
        at: 0.018, gain: 0.5)
    return out
  },

  // select · dry click, 30 ms.
  Asset("select") {
    click(seed: "select", seconds: 0.030, tau: 0.004, cutoff: 5_200, tone: 1_800)
  },

  // hold-tick · the rising tone under the hold-to-file ring (§8, t=0). Three of
  // these play 180 ms apart, so each one is a step, not a repeat.
  Asset("hold-tick") {
    var out = buffer(0.060)
    for index in out.indices {
      let t = time(index)
      out[index] = sine(660, t) * decay(t, 0.014) * attack(t, 0.002)
    }
    mix(&out, click(seed: "hold-tick", seconds: 0.020, tau: 0.003, cutoff: 6_000, tone: 2_400),
        at: 0, gain: 0.45)
    return out
  },

  // query-start · filtered noise burst, 200 ms.
  Asset("query-start") {
    var out = air(seed: "query-start", seconds: 0.200, tau: 0.070, cutoff: 3_200, highCut: 420)
    for index in out.indices {
      // A slow sweep under the noise: the log pane is opening, not just hissing.
      let t = time(index)
      out[index] += sine(180 + 420 * t / 0.2, t) * 0.25 * decay(t, 0.060) * attack(t, 0.008)
    }
    return out
  },

  // tick · tiny click, 20 ms. One per log line, and the severity chip's stamp.
  Asset("tick") {
    click(seed: "tick", seconds: 0.020, tau: 0.0025, cutoff: 7_000, tone: 3_000)
  },

  // finding-land · soft mallet, 120 ms, three pitches cycling.
  Asset("finding-land-1") { mallet(seed: "land-1", frequency: 523.25, seconds: 0.120) },
  Asset("finding-land-2") { mallet(seed: "land-2", frequency: 659.25, seconds: 0.120) },
  Asset("finding-land-3") { mallet(seed: "land-3", frequency: 783.99, seconds: 0.120) },

  // commit-soft · short double click.
  Asset("commit-soft") {
    var out = buffer(0.110)
    mix(&out, click(seed: "commit-a", seconds: 0.030, tau: 0.004, cutoff: 4_800, tone: 1_500), at: 0)
    mix(&out, click(seed: "commit-b", seconds: 0.040, tau: 0.006, cutoff: 4_200, tone: 1_180),
        at: 0.042, gain: 0.85)
    return out
  },

  // file · paper slide + thud, 350 ms. The heaviest sound in the game, because it
  // is the one you cannot take back.
  Asset("file") {
    var out = buffer(0.350)
    var slide = air(seed: "file-paper", seconds: 0.180, tau: 0.055, cutoff: 5_500, highCut: 900)
    for index in slide.indices { slide[index] *= attack(time(index), 0.020) }
    mix(&out, slide, at: 0, gain: 0.55)
    mix(&out, thud(seed: "file-thud", from: 150, to: 58, seconds: 0.260), at: 0.090, gain: 1.0)
    return out
  },

  // stamp · ink stamp on paper, 300 ms.
  Asset("stamp") {
    var out = buffer(0.300)
    mix(&out, air(seed: "stamp-paper", seconds: 0.060, tau: 0.010, cutoff: 7_500, highCut: 1_400),
        at: 0, gain: 0.7)
    mix(&out, thud(seed: "stamp-body", from: 260, to: 96, seconds: 0.220), at: 0.006, gain: 0.9)
    // The wooden knock of the handle bottoming out.
    mix(&out, mallet(seed: "stamp-knock", frequency: 196, seconds: 0.140), at: 0.012, gain: 0.45)
    return out
  },

  // verdict-* · a 2-note chord, 500 ms: major / suspended / minor 2nd.
  Asset("verdict-good") { chord(seed: "vg", root: 392.00, ratio: 1.2599, seconds: 0.500) },
  Asset("verdict-off") { chord(seed: "vo", root: 349.23, ratio: 1.3348, seconds: 0.500) },
  Asset("verdict-wrong") { chord(seed: "vw", root: 293.66, ratio: 1.0595, seconds: 0.500) },

  // breach-thud · sub thud, 400 ms.
  Asset("breach-thud") {
    var out = thud(seed: "breach", from: 120, to: 42, seconds: 0.400)
    // A second blow inside the first, matching `CHPatternSpec.breachThud`'s
    // transient at 90 ms — so the ear and the hand agree it is one event, doubled.
    mix(&out, thud(seed: "breach-2", from: 96, to: 40, seconds: 0.240), at: 0.090, gain: 0.6)
    return out
  },

  // beat-lub / beat-dub · the optional heartbeat sound, off by default (§9).
  Asset("beat-lub") { thud(seed: "lub", from: 88, to: 44, seconds: 0.130) },
  Asset("beat-dub") { thud(seed: "dub", from: 72, to: 40, seconds: 0.100) },

  // rankup · rising 3-note figure, 700 ms — §9's own row, past the 600 ms headline.
  Asset("rankup", cap: 0.700) {
    var out = buffer(0.700)
    let notes = [(392.00, 0.0), (493.88, 0.180), (587.33, 0.400)]
    for (frequency, at) in notes {
      mix(&out, mallet(seed: "rank-\(Int(frequency))", frequency: frequency, seconds: 0.300),
          at: at, gain: 0.9)
    }
    // The last note keeps ringing past the third strike — this is the one cue in the
    // game that crescendos, and it should not stop dead at 700 ms.
    mix(&out, mallet(seed: "rank-top", frequency: 783.99, seconds: 0.280), at: 0.400, gain: 0.5)
    return out
  },

  // denied · dull knock, 120 ms.
  Asset("denied") {
    var out = thud(seed: "denied", from: 190, to: 110, seconds: 0.120)
    lowPass(&out, cutoff: 520)
    return out
  },

  // ping · sonar ping, pitch up per alert, 300 ms. Seven, one per queue slot.
  Asset("ping-1") { ping(step: 0) },
  Asset("ping-2") { ping(step: 1) },
  Asset("ping-3") { ping(step: 2) },
  Asset("ping-4") { ping(step: 3) },
  Asset("ping-5") { ping(step: 4) },
  Asset("ping-6") { ping(step: 5) },
  Asset("ping-7") { ping(step: 7) },

  // room tone · the loop under an open shift, played at −30 dB by the service.
  Asset("room-tone", isLoop: true) { roomTone() },
]

// MARK: - WAV

func wav(_ samples: [Double]) -> Data {
  var pcm = Data(capacity: samples.count * 2)
  for value in samples {
    let clamped = max(-1.0, min(1.0, value))
    // 32767, not 32768: the negative rail has one more code than the positive one,
    // and scaling by 32768 turns a full-scale sample into a wrapped +1 click.
    let sample = Int16((clamped * 32_767).rounded())
    withUnsafeBytes(of: sample.littleEndian) { pcm.append(contentsOf: $0) }
  }

  var out = Data()
  func ascii(_ text: String) { out.append(contentsOf: Array(text.utf8)) }
  func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { out.append(contentsOf: $0) } }
  func u16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { out.append(contentsOf: $0) } }

  let rate = UInt32(sampleRate)
  ascii("RIFF")
  u32(UInt32(36 + pcm.count))
  ascii("WAVE")
  ascii("fmt ")
  u32(16)                       // PCM chunk size
  u16(1)                        // format: PCM
  u16(1)                        // channels: mono
  u32(rate)
  u32(rate * 2)                 // byte rate: mono 16-bit
  u16(2)                        // block align
  u16(16)                       // bits per sample
  ascii("data")
  u32(UInt32(pcm.count))
  out.append(pcm)
  return out
}

// MARK: - Main

var outputDirectory = "ios/SentrySOC/Resources/Sounds"
var isCheck = false
var arguments = Array(CommandLine.arguments.dropFirst())
while let argument = arguments.first {
  arguments.removeFirst()
  switch argument {
  case "--out":
    guard let value = arguments.first else {
      FileHandle.standardError.write(Data("--out needs a directory\n".utf8))
      exit(2)
    }
    outputDirectory = value
    arguments.removeFirst()
  case "--check":
    isCheck = true
  default:
    FileHandle.standardError.write(Data("unknown argument \(argument)\n".utf8))
    exit(2)
  }
}

let destination =
  isCheck
  ? FileManager.default.temporaryDirectory.appendingPathComponent("sentry-sfx-check")
  : URL(fileURLWithPath: outputDirectory)
try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

var failures = 0
var totalBytes = 0
for asset in assets {
  var samples = asset.render()
  normalise(&samples)
  deClick(&samples)

  let seconds = Double(samples.count) / sampleRate
  if !asset.isLoop && seconds > asset.capSeconds + 1e-9 {
    print("  FAIL \(asset.name): \(Int(seconds * 1000)) ms is past its \(Int(asset.capSeconds * 1000)) ms cap (§9)")
    failures += 1
  }
  let peak = samples.reduce(0) { max($0, abs($1)) }
  if peak > peakCeiling + 1e-6 {
    print("  FAIL \(asset.name): peak \(peak) is past the −1 dBFS ceiling")
    failures += 1
  }

  let data = wav(samples)
  let url = destination.appendingPathComponent("\(asset.name).wav")
  if isCheck {
    let committed = URL(fileURLWithPath: outputDirectory).appendingPathComponent("\(asset.name).wav")
    let onDisk = try? Data(contentsOf: committed)
    if onDisk != data {
      print("  DRIFT \(asset.name).wav — the committed bytes are not what this script renders")
      failures += 1
    }
  } else {
    try data.write(to: url)
  }
  totalBytes += data.count

  let rms = (samples.reduce(0) { $0 + $1 * $1 } / Double(max(samples.count, 1))).squareRoot()
  let dbfs = 20 * log10(max(rms, 1e-9))
  print(
    String(
      format: "  %-16s %6d ms  RMS %6.1f dBFS  peak %5.3f",
      (asset.name as NSString).utf8String!, Int(seconds * 1000), dbfs, peak))
}

print("")
print("\(assets.count) assets · \(totalBytes / 1024) KB · \(isCheck ? "checked" : destination.path)")
if failures > 0 {
  print("\(failures) problem(s)")
  exit(1)
}
