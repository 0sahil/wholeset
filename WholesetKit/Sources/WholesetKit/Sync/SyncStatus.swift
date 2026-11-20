// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One CloudKit mirroring event (setup, import or export), copied out of Core Data's
/// `NSPersistentCloudKitContainer.Event` so it can be tested and stored.
public struct SyncEvent: Sendable, Equatable {
    /// The kind of work the event reports.
    public enum Kind: String, Sendable, Equatable {
        case setup
        case `import`
        case export
    }

    /// The same for the start and the end of one piece of work.
    public let id: UUID
    public let kind: Kind
    public let startDate: Date
    /// `nil` while the work is still running.
    public let endDate: Date?
    public let succeeded: Bool
    /// The error's description when the work failed.
    public let errorDescription: String?

    /// Creates an event.
    public init(id: UUID, kind: Kind, startDate: Date, endDate: Date?, succeeded: Bool, errorDescription: String? = nil) {
        self.id = id
        self.kind = kind
        self.startDate = startDate
        self.endDate = endDate
        self.succeeded = succeeded
        self.errorDescription = errorDescription
    }
}

/// What has been observed of CloudKit mirroring since launch.
///
/// Core Data posts each piece of mirroring work twice: when it starts (no end date) and
/// when it ends. Only events of this launch are known; the system keeps no history the
/// app can read.
public struct SyncActivity: Sendable, Equatable {
    /// Work that has started but not ended.
    public private(set) var running: [UUID: SyncEvent.Kind] = [:]
    /// The most recent finished import.
    public private(set) var lastImport: SyncEvent?
    /// The most recent finished export.
    public private(set) var lastExport: SyncEvent?
    /// The most recent finished setup.
    public private(set) var lastSetup: SyncEvent?
    /// Imports finished since launch.
    public private(set) var importsFinished = 0

    /// Creates an empty activity record.
    public init() {}

    /// Records `event`.
    ///
    /// - Returns: Whether it was the end of an import (new data may have arrived).
    @discardableResult
    public mutating func record(_ event: SyncEvent) -> Bool {
        guard event.endDate != nil else {
            running[event.id] = event.kind
            return false
        }
        running[event.id] = nil
        switch event.kind {
        case .setup: lastSetup = event
        case .import:
            lastImport = event
            importsFinished += 1
            return true
        case .export: lastExport = event
        }
        return false
    }

    /// Whether any mirroring work is running.
    public var isRunning: Bool { !running.isEmpty }

    /// The most recently finished import or export.
    public var lastTransfer: SyncEvent? {
        [lastImport, lastExport].compactMap { $0 }.max { ($0.endDate ?? .distantPast) < ($1.endDate ?? .distantPast) }
    }
}

/// A one-line summary of iCloud sync for the Settings screen.
public enum SyncStatus: Sendable, Equatable {
    /// The store is not mirrored to CloudKit in this build or launch.
    case off(WholesetStore.Mode)
    /// The app was built without iCloud (``CloudConfiguration/isICloudEnabled`` is
    /// `false`), so data stays on the device by design.
    case offInThisBuild
    /// The iCloud account status is still being checked.
    case checkingAccount
    /// The account cannot sync (signed out, restricted, …).
    case accountUnavailable(CloudAccountStatus)
    /// Mirroring work is running.
    case syncing
    /// The latest finished setup, import or export failed.
    case failed(at: Date, message: String)
    /// The latest import or export succeeded.
    case upToDate(at: Date)
    /// The account is fine but no import or export has finished since launch.
    case waiting

    /// Summarises what is known.
    ///
    /// - Parameters:
    ///   - mode: How the store was opened.
    ///   - account: The account status, `nil` while checking.
    ///   - activity: Mirroring events since launch.
    ///   - iCloudEnabledInBuild: Whether the app was built with iCloud. A build without it
    ///     that opened its on-disk store reports ``offInThisBuild``.
    public static func summarize(
        mode: WholesetStore.Mode,
        account: CloudAccountStatus?,
        activity: SyncActivity,
        iCloudEnabledInBuild: Bool = true
    ) -> SyncStatus {
        guard mode == .cloudKit else {
            return mode == .local && !iCloudEnabledInBuild ? .offInThisBuild : .off(mode)
        }
        guard let account else { return .checkingAccount }
        guard account == .available else { return .accountUnavailable(account) }
        if activity.isRunning { return .syncing }
        let finished = [activity.lastSetup, activity.lastImport, activity.lastExport].compactMap { $0 }
        if let latest = finished.max(by: { ($0.endDate ?? .distantPast) < ($1.endDate ?? .distantPast) }),
           !latest.succeeded, let end = latest.endDate {
            return .failed(at: end, message: latest.errorDescription ?? "")
        }
        if let transfer = activity.lastTransfer, let end = transfer.endDate {
            return .upToDate(at: end)
        }
        return .waiting
    }
}
