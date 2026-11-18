// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A rest countdown defined by its end date rather than a ticking counter, so it stays
/// correct across wrist-down, app suspension and relaunch: the remaining time is always
/// computed from the wall clock.
public struct RestTimer: Codable, Equatable, Sendable {
    /// Seconds added by the "+30 s" button.
    public static let extensionSeconds: TimeInterval = 30
    /// Rest used when neither the routine, the exercise nor the settings give a usable value.
    public static let fallbackSeconds = 90

    /// When the rest started.
    public private(set) var startedAt: Date
    /// When the rest ends (or ended).
    public private(set) var endDate: Date

    /// Starts a rest of `duration` seconds at `now`. Negative durations count as zero.
    public init(duration: TimeInterval, now: Date) {
        startedAt = now
        endDate = now.addingTimeInterval(max(0, duration))
    }

    /// Starts a rest of `duration` seconds at `now`.
    public static func start(duration: TimeInterval, now: Date) -> RestTimer {
        RestTimer(duration: duration, now: now)
    }

    /// The full length of this rest, including any extensions.
    public var totalDuration: TimeInterval {
        endDate.timeIntervalSince(startedAt)
    }

    /// Seconds left at `date`, never negative.
    public func remaining(at date: Date) -> TimeInterval {
        max(0, endDate.timeIntervalSince(date))
    }

    /// Whether the rest is over at `date`.
    public func isFinished(at date: Date) -> Bool {
        date >= endDate
    }

    /// The share of the rest still to go at `date`, from 1 (just started) to 0 (over).
    public func fractionRemaining(at date: Date) -> Double {
        guard totalDuration > 0 else { return 0 }
        return min(1, remaining(at: date) / totalDuration)
    }

    /// Adds `seconds` to the rest. If it had already ended, the extra time counts from `now`.
    public mutating func extend(by seconds: TimeInterval = RestTimer.extensionSeconds, now: Date) {
        endDate = max(endDate, now).addingTimeInterval(max(0, seconds))
    }

    /// Ends the rest at `now`. Has no effect if it has already ended.
    public mutating func skip(now: Date) {
        endDate = min(endDate, max(now, startedAt))
    }

    /// The rest length for a set: the routine slot's value, else the exercise's own
    /// default, else the app setting, else ``fallbackSeconds``. Negative values are ignored;
    /// zero means no rest.
    public static func duration(routineItemSeconds: Int?, exerciseSeconds: Int?, appDefaultSeconds: Int?) -> TimeInterval {
        let chosen = [routineItemSeconds, exerciseSeconds, appDefaultSeconds]
            .compactMap { $0 }
            .first { $0 >= 0 }
        return TimeInterval(chosen ?? fallbackSeconds)
    }
}

/// Elapsed workout time that excludes pauses.
public struct WorkoutClock: Codable, Equatable, Sendable {
    /// When the workout started.
    public let startedAt: Date
    /// When the current pause began; `nil` while running.
    public private(set) var pausedAt: Date?
    /// Total length of all finished pauses.
    public private(set) var pausedDuration: TimeInterval

    /// Creates a running clock that started at `startedAt`.
    public init(startedAt: Date) {
        self.startedAt = startedAt
        self.pausedAt = nil
        self.pausedDuration = 0
    }

    /// Whether the clock is paused.
    public var isPaused: Bool { pausedAt != nil }

    /// Active (unpaused) time between the start and `date`, never negative.
    public func elapsed(at date: Date) -> TimeInterval {
        let end = pausedAt.map { min($0, date) } ?? date
        return max(0, end.timeIntervalSince(startedAt) - pausedDuration)
    }

    /// The start date a plain running timer would need to show ``elapsed(at:)``:
    /// `startedAt` shifted by all finished pauses.
    public var effectiveStart: Date {
        startedAt.addingTimeInterval(pausedDuration)
    }

    /// Pauses at `date`. Has no effect if already paused.
    public mutating func pause(at date: Date) {
        guard pausedAt == nil else { return }
        pausedAt = max(date, startedAt)
    }

    /// Resumes at `date`. Has no effect if running.
    public mutating func resume(at date: Date) {
        guard let pausedAt else { return }
        pausedDuration += max(0, date.timeIntervalSince(pausedAt))
        self.pausedAt = nil
    }
}
