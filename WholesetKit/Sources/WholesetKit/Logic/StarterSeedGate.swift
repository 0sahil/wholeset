// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Decides when a device may create the starter routines on its own.
///
/// The Watch seeds them automatically so a new user has something to start; the iPhone
/// never does (its Plan screen offers them instead). A device must not seed on top of
/// routines that exist in iCloud but have not arrived yet, so the Watch waits until it has
/// seen what iCloud holds:
/// - without CloudKit (local or in-memory store, no iCloud account, iCloud restricted)
///   nothing can arrive, so it seeds at once;
/// - with CloudKit it waits for its first import of this launch to finish, or gives up
///   waiting after ``patience`` (for example offline at the gym) and seeds anyway.
///
/// Seeding after giving up can still race another device; ``StoreMaintenance`` repairs
/// that after sync (merging duplicate starters, removing untouched late ones).
public enum StarterSeedGate {
    /// How long a device waits for its first iCloud import before seeding anyway.
    public static let patience: Duration = .seconds(30)

    /// What the device knows about iCloud data that may still arrive.
    public enum Readiness: Sendable, Equatable {
        /// Nothing can arrive: no CloudKit store, or no usable iCloud account.
        case noCloudSync
        /// CloudKit is on and the first import of this launch has not finished yet.
        case waitingForFirstImport
        /// The first import of this launch finished (successfully or not).
        case firstImportFinished
        /// Waited ``patience`` without an import finishing.
        case gaveUpWaiting
    }

    /// The device's readiness from what it can observe.
    ///
    /// - Parameters:
    ///   - storeMode: How the store was opened; only `.cloudKit` can receive data.
    ///   - account: The iCloud account status, `nil` while still being checked.
    ///   - firstImportFinished: Whether an import event has ended since launch.
    ///   - waitedLongEnough: Whether ``patience`` has passed since launch.
    public static func readiness(
        storeMode: WholesetStore.Mode,
        account: CloudAccountStatus?,
        firstImportFinished: Bool,
        waitedLongEnough: Bool
    ) -> Readiness {
        guard storeMode == .cloudKit else { return .noCloudSync }
        switch account {
        case .noAccount, .restricted:
            return .noCloudSync
        case .available, .couldNotDetermine, .temporarilyUnavailable, nil:
            if firstImportFinished { return .firstImportFinished }
            return waitedLongEnough ? .gaveUpWaiting : .waitingForFirstImport
        }
    }

    /// Whether to seed the starter routines now.
    ///
    /// - Parameters:
    ///   - decidedAt: `AppSettings.starterRoutinesDecidedAt` after sync duplicates are merged.
    ///   - routineCount: Routines in the store.
    ///   - readiness: See ``readiness(storeMode:account:firstImportFinished:waitedLongEnough:)``.
    public static func shouldSeed(decidedAt: Date?, routineCount: Int, readiness: Readiness) -> Bool {
        guard decidedAt == nil, routineCount == 0 else { return false }
        return readiness != .waitingForFirstImport
    }

    /// Whether the device still has to wait before it can decide (Home says "looking in iCloud").
    public static func isWaiting(decidedAt: Date?, routineCount: Int, readiness: Readiness) -> Bool {
        decidedAt == nil && routineCount == 0 && readiness == .waitingForFirstImport
    }
}

/// The iCloud account status, mirrored from CloudKit so logic can be tested without it.
public enum CloudAccountStatus: String, Sendable, Equatable {
    case available
    case noAccount
    case restricted
    case couldNotDetermine
    case temporarilyUnavailable
}
