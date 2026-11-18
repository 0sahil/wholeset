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

/// The elapsed clock in the top bar of the workout pages, left of the system time: yellow
/// like the Workout app, with tabular digits. When paused it stops, dims and gets a pause
/// glyph.
struct WorkoutClockLabel: View {
    let clock: WorkoutClock

    var body: some View {
        HStack(spacing: 2) {
            if clock.isPaused {
                Image(systemName: "pause.fill")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            ElapsedText(clock: clock)
                .accessibilityLabel(clock.isPaused ? Text("Elapsed time, paused") : Text("Elapsed time"))
        }
        .font(Theme.number(.body))
        .foregroundStyle(Theme.elapsed.opacity(clock.isPaused ? 0.6 : 1))
        .lineLimit(1)
        .fixedSize()
    }
}
