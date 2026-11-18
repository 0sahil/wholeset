// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// An explicit rest split into whole minutes and seconds, for a minutes wheel and a seconds
/// wheel side by side.
///
/// Every value is a valid rest: the total is always rounded and limited by
/// ``RoutineRules/normalizedRest(_:)``, so 0:00 becomes 0:15 and anything past 10:00
/// becomes 10:00. Changing one wheel can therefore move the other (for example choosing
/// 10 minutes sets the seconds to 0).
public struct RestComponents: Equatable, Sendable {
    /// Whole minutes, within ``minuteChoices``.
    public let minutes: Int
    /// Seconds past the minute, one of ``secondChoices``.
    public let seconds: Int

    /// The minutes wheel: 0 to 10.
    public static let minuteChoices: [Int] = Array(0...(RoutineRules.restRange.upperBound / 60))

    /// The seconds wheel: 0, 15, 30 and 45.
    public static let secondChoices: [Int] = Array(stride(from: 0, to: 60, by: RoutineRules.restStep))

    /// Splits `totalSeconds` after making it a valid rest.
    public init(totalSeconds: Int) {
        let total = RoutineRules.normalizedRest(totalSeconds) ?? RoutineRules.restRange.lowerBound
        minutes = total / 60
        seconds = total % 60
    }

    /// Combines a wheel pair into the nearest valid rest.
    public init(minutes: Int, seconds: Int) {
        // Bounded well past the limit first, so no input can overflow.
        let minutes = min(max(minutes, 0), 1_000)
        let seconds = min(max(seconds, 0), 1_000)
        self.init(totalSeconds: minutes * 60 + seconds)
    }

    /// The rest in seconds, within ``RoutineRules/restRange``.
    public var totalSeconds: Int { minutes * 60 + seconds }

    /// The rest after choosing `minutes` on the minutes wheel, keeping the seconds if they
    /// still fit.
    public func settingMinutes(_ minutes: Int) -> RestComponents {
        RestComponents(minutes: minutes, seconds: seconds)
    }

    /// The rest after choosing `seconds` on the seconds wheel, keeping the minutes if they
    /// still fit.
    public func settingSeconds(_ seconds: Int) -> RestComponents {
        RestComponents(minutes: minutes, seconds: seconds)
    }
}
