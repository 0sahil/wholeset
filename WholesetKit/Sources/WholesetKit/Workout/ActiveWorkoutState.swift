// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The parts of a running workout that are not in the data model: pauses, the running
/// rest timer and the exercise on screen. Kept small and saved on every change so a
/// relaunch can put the user back exactly where they were.
public struct ActiveWorkoutState: Codable, Equatable, Sendable {
    /// The session this state belongs to.
    public var sessionID: UUID
    /// Elapsed time and pauses.
    public var clock: WorkoutClock
    /// The rest in progress, if any.
    public var rest: RestTimer?
    /// The exercise on screen.
    public var currentEntryID: UUID?

    /// Creates the state for a session.
    public init(sessionID: UUID, clock: WorkoutClock, rest: RestTimer? = nil, currentEntryID: UUID? = nil) {
        self.sessionID = sessionID
        self.clock = clock
        self.rest = rest
        self.currentEntryID = currentEntryID
    }
}

/// Stores ``ActiveWorkoutState`` in `UserDefaults`, which is written outside the app's
/// process and so survives a crash.
public struct ActiveWorkoutStateStore {
    /// The default key.
    public static let defaultKey = "wholeset.activeWorkoutState"

    private let defaults: UserDefaults
    private let key: String

    /// Creates a store over `defaults` under `key`.
    public init(defaults: UserDefaults = .standard, key: String = ActiveWorkoutStateStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    /// The stored state for `sessionID`, or `nil` if none is stored, it belongs to another
    /// session, or it cannot be decoded.
    public func load(sessionID: UUID) -> ActiveWorkoutState? {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(ActiveWorkoutState.self, from: data),
              state.sessionID == sessionID else { return nil }
        return state
    }

    /// Replaces the stored state.
    public func save(_ state: ActiveWorkoutState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }

    /// Removes the stored state.
    public func clear() {
        defaults.removeObject(forKey: key)
    }
}
