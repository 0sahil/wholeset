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
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "WholesetKitTests",
            dependencies: ["WholesetKit"],
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
