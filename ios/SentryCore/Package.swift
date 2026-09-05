// swift-tools-version: 6.2
import PackageDescription

// SPEC.md §3.1 — every target is declared HERE, on day one, so no later ticket
// edits this file (§11 rule 6). The Engine/, Career/, Session/ and Feel/ sources
// of C3–C5 land inside the SAME `Sources/SentryCore` tree, which SwiftPM walks
// recursively; the EngineTests / CareerTests / SessionTests directories already
// exist (empty) for the same reason.
//
// Zero remote dependencies → no Package.resolved, no network on any build.
// SentryCore imports Foundation only (D15): no UIKit, SwiftUI or CoreHaptics.
let package = Package(
  name: "SentryCore",
  platforms: [.iOS(.v18), .macOS(.v14)],          // macOS so the parity gate needs no simulator
  products: [.library(name: "SentryCore", targets: ["SentryCore"])],
  targets: [
    .target(name: "SentryContent",  resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
    .target(name: "SentryFixtures", resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]),          // test-only (D23)
    .target(name: "SentryCore", dependencies: ["SentryContent"],
            swiftSettings: [.swiftLanguageMode(.v6)]),
    .testTarget(name: "ContentTests", dependencies: ["SentryCore", "SentryFixtures"],
                swiftSettings: [.swiftLanguageMode(.v6)]),
    .testTarget(name: "EngineTests",  dependencies: ["SentryCore", "SentryFixtures"],
                swiftSettings: [.swiftLanguageMode(.v6)]),
    .testTarget(name: "CareerTests",  dependencies: ["SentryCore", "SentryFixtures"],
                swiftSettings: [.swiftLanguageMode(.v6)]),
    .testTarget(name: "SessionTests", dependencies: ["SentryCore", "SentryFixtures"],
                swiftSettings: [.swiftLanguageMode(.v6)]),
  ]
)
