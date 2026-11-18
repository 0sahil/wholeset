// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import HealthKit
import Observation
import os
import WholesetKit

/// Runs the `HKWorkoutSession` + `HKLiveWorkoutBuilder` pair for a strength workout.
///
/// Lifecycle: `prepare()` while the countdown runs, then `startActivity` +
/// `beginCollection`, optional pause/resume, and on end `stopActivity`; once the session
/// reports `.stopped`, `endCollection`, `finishWorkout` and finally `end`.
///
/// Main-actor isolated. HealthKit calls its delegates on a background queue, so delegate
/// duties live in ``HealthEventRelay``, whose ordered event stream this class consumes on
/// the main actor. Every failure is logged and turns into ``HealthSessionState/unavailable``
/// rather than an error the user must handle: logging sets never depends on HealthKit.
@Observable
final class HealthKitWorkoutManager: WorkoutSessionManaging {
    private(set) var state: HealthSessionState = .idle
    private(set) var heartRate: Double?
    private(set) var activeKilocalories: Double?
    private(set) var recoveryStatus: HealthRecoveryStatus = .notAttempted
    private(set) var recoveredSessionID: UUID?

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var relay: HealthEventRelay?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var stoppedContinuation: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var stopTimeoutTask: Task<Void, Never>?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.wholeset.watchkitapp", category: "Health")

    /// How long `end` waits for the session to confirm it stopped before saving anyway.
    private static let stopTimeout: Duration = .seconds(5)

    private static var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate)]
    }

    private static var readTypes: Set<HKObjectType> {
        [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
        } catch {
            logger.error("Health authorization failed: \(error, privacy: .public)")
        }
    }

    // MARK: - Lifecycle

    func prepare() async {
        // A previous workout may still be saving; never let two sessions share this manager.
        var waited: Duration = .zero
        while state == .ending, waited < Self.stopTimeout + .seconds(5) {
            try? await Task.sleep(for: .milliseconds(200))
            waited += .milliseconds(200)
        }
        heartRate = nil
        activeKilocalories = nil
        guard HKHealthStore.isHealthDataAvailable(),
              store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            logger.info("Health unavailable or not authorised; workout continues without it")
            state = .unavailable
            return
        }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            attach(session: session, builder: session.associatedWorkoutBuilder())
            state = .preparing
            session.prepare()
        } catch {
            logger.error("Could not create workout session: \(error, privacy: .public)")
            state = .unavailable
        }
    }

    func start(at date: Date, metadata: [String: String]) async {
        guard let session, let builder else { return }
        session.startActivity(with: date)
        do {
            try await builder.beginCollection(at: date)
            try await builder.addMetadata(metadata)
        } catch {
            logger.error("Could not begin collection: \(error, privacy: .public)")
        }
    }

    func pause() {
        session?.pause()
    }

    func resume() {
        session?.resume()
    }

    func end(at date: Date) async -> HealthWorkoutSummary? {
        guard let session, let builder else { return nil }
        state = .ending
        if session.state == .running || session.state == .paused {
            session.stopActivity(with: date)
            await waitUntilStopped(session)
        }
        var workout: HKWorkout?
        do {
            try await builder.endCollection(at: date)
            workout = try await builder.finishWorkout()
        } catch {
            logger.error("Could not save workout: \(error, privacy: .public)")
        }
        session.end()

        let heartRateType = HKQuantityType(.heartRate)
        let energyType = HKQuantityType(.activeEnergyBurned)
        let heartRate = workout?.statistics(for: heartRateType) ?? builder.statistics(for: heartRateType)
        let energy = workout?.statistics(for: energyType) ?? builder.statistics(for: energyType)
        let summary = HealthWorkoutSummary(
            workoutID: workout?.uuid,
            averageHeartRate: heartRate?.averageQuantity()?.doubleValue(for: HealthUnits.beatsPerMinute),
            maxHeartRate: heartRate?.maximumQuantity()?.doubleValue(for: HealthUnits.beatsPerMinute),
            activeKilocalories: energy?.sumQuantity()?.doubleValue(for: .kilocalorie())
        )
        // Only tear down if no other session was attached while this one was saving.
        if self.session === session {
            detach()
            state = .ended
        }
        return summary
    }

    func discard() async {
        guard let session, let builder else { return }
        builder.discardWorkout()
        session.end()
        if self.session === session {
            detach()
            state = .idle
        }
    }

    // MARK: - Recovery

    func recoverActiveSession() async {
        recoveryStatus = .recovering
        do {
            guard let session = try await store.recoverActiveWorkoutSession() else {
                recoveryStatus = .failed
                return
            }
            let builder = session.associatedWorkoutBuilder()
            attach(session: session, builder: builder)
            recoveredSessionID = (builder.metadata[HealthKitMetadataKey.sessionID] as? String).flatMap(UUID.init(uuidString:))
            state = session.state == .paused ? .paused : .running
            recoveryStatus = .recovered
            logger.info("Recovered active workout session")
        } catch {
            logger.error("Could not recover workout session: \(error, privacy: .public)")
            recoveryStatus = .failed
        }
    }

    // MARK: - Plumbing

    private func attach(session: HKWorkoutSession, builder: HKLiveWorkoutBuilder) {
        detach()
        let relay = HealthEventRelay()
        session.delegate = relay
        builder.delegate = relay
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: session.workoutConfiguration)
        self.session = session
        self.builder = builder
        self.relay = relay
        eventTask = Task { [weak self] in
            for await event in relay.events {
                self?.handle(event, from: relay)
            }
        }
    }

    private func detach() {
        relay?.finish()
        eventTask?.cancel()
        eventTask = nil
        relay = nil
        session = nil
        builder = nil
        resumeStoppedWaiter()
    }

    private func handle(_ event: HealthEventRelay.Event, from source: HealthEventRelay) {
        // Events still buffered from a session that has since been detached are stale.
        guard source === relay else { return }
        switch event {
        case .stateChanged(let newState):
            switch newState {
            case .running: if state != .ending { state = .running }
            case .paused: if state != .ending { state = .paused }
            case .stopped, .ended: resumeStoppedWaiter()
            case .notStarted, .prepared: break
            @unknown default: break
            }
        case .failed(let error):
            logger.error("Workout session failed: \(error, privacy: .public)")
            if state != .ending { state = .unavailable }
            resumeStoppedWaiter()
        case .metrics(let heartRate, let kilocalories):
            if let heartRate { self.heartRate = heartRate }
            if let kilocalories { activeKilocalories = kilocalories }
        }
    }

    private func waitUntilStopped(_ session: HKWorkoutSession) async {
        guard session.state != .stopped, session.state != .ended else { return }
        await withCheckedContinuation { continuation in
            resumeStoppedWaiter()
            stoppedContinuation = continuation
            stopTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: Self.stopTimeout)
                guard !Task.isCancelled else { return }
                self?.resumeStoppedWaiter()
            }
        }
    }

    /// Resumes the pending stop wait, if any, and cancels its timeout so a stale
    /// timeout can never cut a later wait short.
    private func resumeStoppedWaiter() {
        stopTimeoutTask?.cancel()
        stopTimeoutTask = nil
        stoppedContinuation?.resume()
        stoppedContinuation = nil
    }
}
