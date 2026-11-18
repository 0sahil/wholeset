// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import WholesetKit

/// Formats durations for the Watch.
enum TimeText {
    /// "0:45", "12:41" or "1:02:03".
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded(.down)))
        let pattern: Duration.TimeFormatStyle.Pattern = whole >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(whole).formatted(.time(pattern: pattern))
    }

    /// Whole minutes for the reduced-luminance display, e.g. "12 min".
    static func minutes(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    /// Rest left for the reduced-luminance display, rounded up to whole minutes ("2 min").
    static func minutesLeft(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded(.up))
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.minutes], width: .abbreviated))
    }
}

/// Localized text with automatic grammar agreement (`^[\(n) set](inflect: true)`) as a
/// plain string, for places that take a `String` such as accessibility values.
func inflectedString(_ value: String.LocalizationValue) -> String {
    String(AttributedString(localized: value).inflected().characters)
}

/// The workout's elapsed time. Ticks every second normally; with reduced luminance
/// (always-on, wrist down) it shows whole minutes only and updates once a minute.
struct ElapsedText: View {
    let clock: WorkoutClock
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        Group {
            if isLuminanceReduced {
                TimelineView(.everyMinute) { context in
                    Text(TimeText.minutes(clock.elapsed(at: context.date)))
                }
            } else if let pausedAt = clock.pausedAt {
                Text(TimeText.clock(clock.elapsed(at: pausedAt)))
            } else {
                Text(timerInterval: clock.effectiveStart...Date.distantFuture, countsDown: false)
            }
        }
        .accessibilityLabel("Elapsed time")
    }
}
