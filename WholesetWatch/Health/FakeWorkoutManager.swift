// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import Foundation
import Observation
import WholesetKit

/// A stand-in for HealthKit in DEBUG demos and previews: no sensors, canned numbers.
@Observable
final class FakeWorkoutManager: WorkoutSessionManaging {
    private(set) var state: HealthSessionState = .idle
    private(set) var heartRate: Double?
    private(set) var activeKilocalories: Double?
    var recoveryStatus: HealthRecoveryStatus = .notAttempted
    var recoveredSessionID: UUID?

    /// Creates a fake reporting the given live values once started.
    init(heartRate: Double? = 132, activeKilocalories: Double? = 184) {
        self.heartRate = heartRate
        self.activeKilocalories = activeKilocalories
    }

    /// Puts the fake straight into the recording state, as if a workout were running.
    func simulateRunning() {
        state = .running
    }

    func requestAuthorization() async {}

    func prepare() async {
        state = .preparing
    }

    func start(at date: Date, metadata: [String: String]) async {
        state = .running
    }

    func pause() {
        state = .paused
    }

    func resume() {
        state = .running
    }

    func end(at date: Date) async -> HealthWorkoutSummary? {
        state = .ended
        return HealthWorkoutSummary(workoutID: UUID(), averageHeartRate: 128, maxHeartRate: 161, activeKilocalories: activeKilocalories)
    }

    func discard() async {
        state = .idle
    }

    func recoverActiveSession() async {
        recoveryStatus = .recovered
        state = .running
    }
}
#endif
