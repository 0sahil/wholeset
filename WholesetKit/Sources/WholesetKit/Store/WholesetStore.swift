// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import os
import SwiftData

/// Builds the SwiftData container shared by the iPhone and Watch apps.
public enum WholesetStore {
    /// The iCloud container both apps sync through (private database).
    public static let cloudKitContainerIdentifier = "iCloud.app.wholeset"

    /// File name (without extension) of the on-disk store.
    public static let storeName = "Wholeset"

    /// Whether the apps should try CloudKit: on for device builds, off in the
    /// simulator, where builds are usually unsigned and lack the iCloud entitlement.
    public static var cloudKitEnabledByDefault: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    /// The schema of the current model version.
    public static var schema: Schema { Schema(versionedSchema: CurrentSchema.self) }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.wholeset",
        category: "Store"
    )

    /// Creates a container for the current schema.
    ///
    /// - Parameters:
    ///   - inMemory: Keep the store in memory only (previews, tests). CloudKit is
    ///     never used for in-memory stores.
    ///   - cloudKit: Mirror the store to the CloudKit private database
    ///     ``cloudKitContainerIdentifier``. Requires the iCloud entitlement.
    ///   - url: Store file location. `nil` uses `<Application Support>/Wholeset.store`.
    ///     Ignored when `inMemory` is `true`.
    public static func makeContainer(inMemory: Bool = false, cloudKit: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let database: ModelConfiguration.CloudKitDatabase =
            cloudKit && !inMemory ? .private(cloudKitContainerIdentifier) : .none
        let schema = schema

        let configuration: ModelConfiguration
        if let url, !inMemory {
            configuration = ModelConfiguration(storeName, schema: schema, url: url, cloudKitDatabase: database)
        } else {
            configuration = ModelConfiguration(
                storeName,
                schema: schema,
                isStoredInMemoryOnly: inMemory,
                groupContainer: .none,
                cloudKitDatabase: database
            )
        }
        return try ModelContainer(for: schema, migrationPlan: WholesetMigrationPlan.self, configurations: [configuration])
    }

    /// How the app's store ended up being opened.
    public enum Mode: String, Sendable {
        /// On disk, mirrored to CloudKit.
        case cloudKit
        /// On disk, not synced.
        case local
        /// In memory only: nothing persists past this launch.
        case inMemory
    }

    /// The outcome of ``loadAppContainer(cloudKit:)``.
    public struct LoadResult: Sendable {
        /// The opened container, or `nil` if every attempt failed.
        public let container: ModelContainer?
        /// The mode actually in use, or `nil` if every attempt failed.
        public let mode: Mode?
    }

    /// Opens the app's store without ever crashing.
    ///
    /// Tries, in order: CloudKit-mirrored on disk (when `cloudKit` is `true`), local on
    /// disk (the same file, so no data is hidden), then in memory. Every failure is
    /// logged. The caller should show an error state if ``LoadResult/container`` is `nil`.
    ///
    /// - Parameters:
    ///   - cloudKit: Try the CloudKit-mirrored store first.
    ///   - url: Store file location; `nil` uses the default location.
    public static func loadAppContainer(cloudKit: Bool, url: URL? = nil) -> LoadResult {
        var attempts: [Mode] = cloudKit ? [.cloudKit] : []
        attempts += [.local, .inMemory]

        for mode in attempts {
            do {
                let container = try makeContainer(inMemory: mode == .inMemory, cloudKit: mode == .cloudKit, url: url)
                if mode == attempts.first {
                    logger.info("Opened store (\(mode.rawValue, privacy: .public))")
                } else {
                    logger.error("Opened store in fallback mode \(mode.rawValue, privacy: .public)")
                }
                return LoadResult(container: container, mode: mode)
            } catch {
                logger.error("Could not open store (\(mode.rawValue, privacy: .public)): \(error, privacy: .public)")
            }
        }
        return LoadResult(container: nil, mode: nil)
    }
}
