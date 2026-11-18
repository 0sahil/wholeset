// swift-tools-version: 6.2
// SPDX-License-Identifier: GPL-3.0-or-later

import PackageDescription

/// Matches the app targets' "approachable concurrency" behaviour. The package
/// deliberately keeps the default `nonisolated` actor isolation: models and logic
/// must be usable from any actor, not only the main one.
let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "WholesetKit",
    platforms: [
        .iOS(.v26),
        .watchOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "WholesetKit", targets: ["WholesetKit"]),
    ],
    targets: [
        .target(
            name: "WholesetKit",
            // Built-in exercise library, curated from free-exercise-db (public domain);
            // see Scripts/curate-exercise-library.py.
            resources: [.copy("Library/exercises.json")],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "WholesetKitTests",
            dependencies: ["WholesetKit"],
            // Synthetic import fixtures: invented workouts in each export's header layout.
            resources: [.copy("Fixtures")],
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
