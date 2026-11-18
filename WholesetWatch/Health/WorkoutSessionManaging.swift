// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import WholesetKit

/// Where the Health side of a workout is. Logging never waits on it: every state,
/// including ``unavailable``, lets the user keep logging sets.
enum HealthSessionState: Equatable, Sendable {
    /// No Health workout exists.
    case idle
    /// HealthKit is missing, not authorised, or failed; the workout continues without it.
    case unavailable
    /// The session is warming up the sensors.
    case preparing
    /// Recording.
    case running
    /// Paused by the user.
    case paused
    /// Stopping and saving.
    case ending
    /// Saved or discarded.
    case ended
}

/// The outcome of trying to reattach to a Health workout after a relaunch.
enum HealthRecoveryStatus: Equatable, Sendable {
    /// The system has not asked the app to recover a workout (so far).
    case notAttempted
    /// Recovery is in progress.
    case recovering
    /// The Health workout is attached again and still recording.
    case recovered
    /// The system asked, but the workout could not be recovered.
    case failed
}

/// The Health workout behind a Wholeset session. A protocol so the app can run with a
/// fake in DEBUG demos and so the workout engine never depends on HealthKit directly.
@MainActor
protocol WorkoutSessionManaging: AnyObject {
    /// The current state.
    var state: HealthSessionState { get }
    /// The latest heart rate in beats per minute.
    var heartRate: Double? { get }
    /// Active energy so far, in kilocalories.
    var activeKilocalories: Double? { get }
    /// What happened to the last recovery request.
    var recoveryStatus: HealthRecoveryStatus { get }
    /// The session ID stored in a recovered workout's metadata.
    var recoveredSessionID: UUID? { get }

    /// Asks for Health access. Shows the system sheet only the first time.
    func requestAuthorization() async
    /// Creates the Health session and starts warming up sensors. Failure leaves the state ``HealthSessionState/unavailable``.
    func prepare() async
    /// Starts recording at `date` and attaches `metadata` to the workout.
    func start(at date: Date, metadata: [String: String]) async
    /// Pauses recording.
    func pause()
    /// Resumes recording.
    func resume()
    /// Stops recording at `date`, saves the workout and returns its summary, or `nil`
    /// if nothing was recorded.
    func end(at date: Date) async -> HealthWorkoutSummary?
    /// Stops recording and throws the workout away.
    func discard() async
    /// Reattaches to a workout the system kept running while the app was gone.
    func recoverActiveSession() async
}
