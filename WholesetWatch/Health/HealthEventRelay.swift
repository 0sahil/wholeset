// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import HealthKit

/// Receives HealthKit's delegate callbacks, which arrive on a HealthKit-owned background
/// queue, and forwards them in order as plain `Sendable` values through an `AsyncStream`.
///
/// It is `nonisolated` (the app target defaults to the main actor) and genuinely
/// `Sendable`: its only stored properties are the immutable stream and its continuation,
/// which are thread-safe. Statistics are read synchronously inside the callback, so no
/// HealthKit object crosses to another thread.
nonisolated final class HealthEventRelay: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate, Sendable {
    /// One callback, reduced to the values the app needs.
    enum Event: Sendable {
        case stateChanged(HKWorkoutSessionState)
        case failed(any Error)
        case metrics(heartRate: Double?, activeKilocalories: Double?)
    }

    /// Events in the order HealthKit delivered them.
    let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation

    override init() {
        (events, continuation) = AsyncStream.makeStream(of: Event.self)
        super.init()
    }

    /// Ends the stream, letting its consumer finish.
    func finish() {
        continuation.finish()
    }

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        continuation.yield(.stateChanged(toState))
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        continuation.yield(.failed(error))
    }

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRateType = HKQuantityType(.heartRate)
        let energyType = HKQuantityType(.activeEnergyBurned)
        var heartRate: Double?
        var kilocalories: Double?
        if collectedTypes.contains(heartRateType) {
            heartRate = workoutBuilder.statistics(for: heartRateType)?
                .mostRecentQuantity()?
                .doubleValue(for: HealthUnits.beatsPerMinute)
        }
        if collectedTypes.contains(energyType) {
            kilocalories = workoutBuilder.statistics(for: energyType)?
                .sumQuantity()?
                .doubleValue(for: .kilocalorie())
        }
        guard heartRate != nil || kilocalories != nil else { return }
        continuation.yield(.metrics(heartRate: heartRate, activeKilocalories: kilocalories))
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

/// HealthKit units used by the app.
nonisolated enum HealthUnits {
    /// Beats per minute.
    static var beatsPerMinute: HKUnit { .count().unitDivided(by: .minute()) }
}
