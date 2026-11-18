// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation
import os
import SwiftData

/// Keeps the store tidy while an app runs: runs ``StoreMaintenance`` at launch, again
/// (debounced) after each CloudKit import, and decides with ``StarterSeedGate`` when this
/// device may add the built-in library and (on the Watch) the starter routines: at once
/// without CloudKit, otherwise after its first import of the launch or after
/// ``StarterSeedGate/patience``.
@MainActor
@Observable
public final class StoreCoordinator {
    /// Whether this app creates the starter routines on its own.
    public enum StarterPolicy: Sendable {
        /// Seed when the gate allows it (the Watch).
        case automatic
        /// Never seed on its own; the user can add them (the iPhone).
        case manual
    }

    /// The store's container.
    public let container: ModelContainer
    /// iCloud sync observation for this store.
    public let sync: SyncMonitor
    /// Whether the device is still waiting for its first iCloud import before adding the
    /// library (and deciding about starter routines).
    public private(set) var isWaitingForFirstImport = false
    /// Whether the device is still waiting for iCloud before it can decide about starter
    /// routines (only with ``StarterPolicy/automatic``).
    public private(set) var isWaitingForStarterDecision = false
    /// What the last pass changed.
    public private(set) var lastReport: MaintenanceReport?

    /// Called on the main actor after every maintenance pass, and after an import whose pass
    /// was deferred, for example to reload settings.
    @ObservationIgnored public var onMaintenance: (@MainActor () -> Void)?
    /// Return `true` to hold the passes that follow imports (the Watch does during a workout);
    /// call ``resumeDeferredMaintenance()`` when it is safe again.
    @ObservationIgnored public var defersMaintenance: (@MainActor () -> Bool)?
    @ObservationIgnored private var hasDeferredPass = false

    @ObservationIgnored private let policy: StarterPolicy
    @ObservationIgnored private let library: ExerciseLibrary
    @ObservationIgnored private let debouncer: Debouncer
    @ObservationIgnored private let patience: Duration
    @ObservationIgnored private var patienceExpired = false
    /// The wait for a first import started at launch; tests await it instead of sleeping.
    @ObservationIgnored private(set) var patienceWait: Task<Void, Never>?
    @ObservationIgnored private var started = false
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.wholeset", category: "Maintenance")

    /// Creates a coordinator. Call ``start()`` once the app is ready.
    ///
    /// - Parameters:
    ///   - container: The opened store.
    ///   - sync: The store's sync monitor.
    ///   - policy: Whether this app seeds the starter routines on its own.
    ///   - library: The built-in library; `nil` loads the bundled one.
    ///   - debounce: Quiet time after an import before the pass runs.
    ///   - patience: How long to wait for a first import before seeding anyway.
    public init(
        container: ModelContainer,
        sync: SyncMonitor,
        policy: StarterPolicy,
        library: ExerciseLibrary? = nil,
        debounce: Duration = .seconds(2),
        patience: Duration = StarterSeedGate.patience
    ) {
        self.container = container
        self.sync = sync
        self.policy = policy
        self.debouncer = Debouncer(delay: debounce)
        self.patience = patience
        if let library {
            self.library = library
        } else {
            do {
                self.library = try ExerciseLibrary.bundled()
            } catch {
                self.library = ExerciseLibrary(entries: [])
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.wholeset", category: "Maintenance")
                    .error("Could not load the exercise library: \(error, privacy: .public)")
            }
        }
    }

    /// Starts sync observation and runs the launch pass.
    public func start() {
        guard !started else { return }
        started = true
        sync.onImportFinished = { [weak self] in self?.scheduleMaintenance() }
        sync.onAccountChanged = { [weak self] in
            guard let self, self.isWaitingForFirstImport else { return }
            self.runMaintenance()
        }
        sync.start()
        runMaintenance()
        guard isWaitingForFirstImport else { return }
        let patience = patience
        patienceWait = Task { [weak self] in
            try? await Task.sleep(for: patience)
            guard let self else { return }
            self.patienceExpired = true
            if self.isWaitingForFirstImport {
                self.runMaintenance()
            }
        }
    }

    /// Runs the pass after a short quiet period; repeated calls push it back.
    public func scheduleMaintenance() {
        debouncer.schedule { [weak self] in
            guard let self else { return }
            if self.defersMaintenance?() == true {
                self.hasDeferredPass = true
                self.onMaintenance?()
                return
            }
            self.runMaintenance()
        }
    }

    /// The debounced pass not yet run, if any; tests await it instead of sleeping.
    var pendingMaintenance: Task<Void, Never>? {
        debouncer.pending
    }

    /// Runs a pass that was held by ``defersMaintenance``, if any.
    public func resumeDeferredMaintenance() {
        guard hasDeferredPass else { return }
        hasDeferredPass = false
        scheduleMaintenance()
    }

    /// Runs the pass now on the main context.
    public func runMaintenance() {
        let context = container.mainContext
        let readiness = StarterSeedGate.readiness(
            storeMode: sync.mode,
            account: sync.account,
            firstImportFinished: sync.activity.importsFinished > 0,
            waitedLongEnough: patienceExpired
        )
        let isReady = readiness != .waitingForFirstImport
        do {
            let report = try StoreMaintenance.run(
                in: context,
                library: library,
                seedLibrary: isReady,
                seedStarterRoutines: policy == .automatic && isReady
            )
            lastReport = report
            if isWaitingForFirstImport == isReady {
                isWaitingForFirstImport = !isReady
            }
            if policy == .automatic {
                let settings = try AppSettings.current(in: context)
                let routineCount = try context.fetchCount(FetchDescriptor<Routine>())
                isWaitingForStarterDecision = StarterSeedGate.isWaiting(
                    decidedAt: settings.starterRoutinesDecidedAt,
                    routineCount: routineCount,
                    readiness: readiness
                )
            }
        } catch {
            logger.error("Store maintenance failed: \(error, privacy: .public)")
        }
        onMaintenance?()
    }
}

/// Runs the latest scheduled action after a quiet period.
@MainActor
final class Debouncer {
    private let delay: Duration
    /// The latest scheduled action's task (kept after it runs); tests await it.
    private(set) var pending: Task<Void, Never>?

    init(delay: Duration) {
        self.delay = delay
    }

    /// Schedules `action`, replacing any action not yet run.
    func schedule(_ action: @escaping @MainActor () -> Void) {
        pending?.cancel()
        let delay = delay
        pending = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    /// Drops the scheduled action.
    func cancel() {
        pending?.cancel()
        pending = nil
    }
}
