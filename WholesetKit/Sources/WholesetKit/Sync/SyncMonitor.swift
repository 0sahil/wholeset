// SPDX-License-Identifier: GPL-3.0-or-later

import CloudKit
import CoreData
import Foundation
import Observation
import os

/// Watches iCloud sync for the app: the account status and the CloudKit mirroring events
/// of the store.
///
/// SwiftData mirrors through Core Data's `NSPersistentCloudKitContainer`, which posts
/// `eventChangedNotification` for setup, import and export work. The monitor listens to
/// every such notification (the container posting it is internal to SwiftData) and records
/// it in ``activity``. If the system stops posting them, the account status is still
/// accurate and ``status`` reports ``SyncStatus/waiting``.
///
/// Account status is only asked for when the store is mirrored to CloudKit: an app built
/// without the iCloud entitlement (unsigned simulator builds) must not touch CloudKit.
@MainActor
@Observable
public final class SyncMonitor {
    /// How the store was opened.
    public let mode: WholesetStore.Mode
    /// Whether the app was built with iCloud; see ``CloudConfiguration/isICloudEnabled``.
    public let iCloudEnabledInBuild: Bool
    /// The iCloud account status; `nil` until checked, and always `nil` without CloudKit.
    public private(set) var account: CloudAccountStatus?
    /// Mirroring events since launch.
    public private(set) var activity = SyncActivity()

    /// Called on the main actor each time an import finishes.
    @ObservationIgnored public var onImportFinished: (@MainActor () -> Void)?
    /// Called on the main actor each time the account status changes.
    @ObservationIgnored public var onAccountChanged: (@MainActor () -> Void)?

    @ObservationIgnored private let accountStatusProvider: (@Sendable () async -> CloudAccountStatus?)?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    /// The latest account status check; tests await it instead of sleeping.
    @ObservationIgnored private(set) var accountRefresh: Task<Void, Never>?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.wholeset", category: "Sync")

    /// Creates a monitor.
    ///
    /// - Parameters:
    ///   - mode: How the store was opened.
    ///   - iCloudEnabledInBuild: Whether the app was built with iCloud; defaults to the
    ///     running app's ``CloudConfiguration/isICloudEnabled``.
    ///   - accountStatusProvider: Reads the account status. `nil` uses CloudKit's for
    ///     ``WholesetStore/cloudKitContainerIdentifier`` when `mode` is `.cloudKit`.
    public init(
        mode: WholesetStore.Mode,
        iCloudEnabledInBuild: Bool = CloudConfiguration.main.isICloudEnabled,
        accountStatusProvider: (@Sendable () async -> CloudAccountStatus?)? = nil
    ) {
        self.mode = mode
        self.iCloudEnabledInBuild = iCloudEnabledInBuild
        if let accountStatusProvider {
            self.accountStatusProvider = accountStatusProvider
        } else if mode == .cloudKit {
            self.accountStatusProvider = Self.cloudKitAccountStatus
        } else {
            self.accountStatusProvider = nil
        }
    }

    /// The summary shown in Settings.
    public var status: SyncStatus {
        SyncStatus.summarize(mode: mode, account: account, activity: activity, iCloudEnabledInBuild: iCloudEnabledInBuild)
    }

    /// Starts listening and checks the account. Call once.
    public func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
            let snapshot = SyncEvent(event)
            MainActor.assumeIsolated {
                self?.record(snapshot)
            }
        })
        if accountStatusProvider != nil {
            observers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshAccountStatus()
                }
            })
        }
        refreshAccountStatus()
    }

    /// Records a mirroring event (also used by tests and previews).
    public func record(_ event: SyncEvent) {
        if let description = event.errorDescription, !event.succeeded, event.endDate != nil {
            logger.error("CloudKit \(event.kind.rawValue, privacy: .public) failed: \(description, privacy: .public)")
        }
        if activity.record(event) {
            onImportFinished?()
        }
    }

    /// Reads the account status again.
    public func refreshAccountStatus() {
        guard let accountStatusProvider else { return }
        accountRefresh = Task {
            let status = await accountStatusProvider()
            guard status != account else { return }
            account = status
            onAccountChanged?()
        }
    }

    private static let cloudKitAccountStatus: @Sendable () async -> CloudAccountStatus? = {
        do {
            let status = try await CKContainer(identifier: WholesetStore.cloudKitContainerIdentifier).accountStatus()
            return CloudAccountStatus(status)
        } catch {
            return .couldNotDetermine
        }
    }
}

extension CloudAccountStatus {
    /// Mirrors CloudKit's account status.
    init(_ status: CKAccountStatus) {
        switch status {
        case .available: self = .available
        case .noAccount: self = .noAccount
        case .restricted: self = .restricted
        case .temporarilyUnavailable: self = .temporarilyUnavailable
        case .couldNotDetermine: self = .couldNotDetermine
        @unknown default: self = .couldNotDetermine
        }
    }
}

extension SyncEvent {
    /// Copies a Core Data mirroring event.
    init(_ event: NSPersistentCloudKitContainer.Event) {
        let kind: Kind
        switch event.type {
        case .setup: kind = .setup
        case .import: kind = .import
        case .export: kind = .export
        @unknown default: kind = .setup
        }
        self.init(
            id: event.identifier,
            kind: kind,
            startDate: event.startDate,
            endDate: event.endDate,
            succeeded: event.succeeded,
            errorDescription: event.error?.localizedDescription
        )
    }
}
