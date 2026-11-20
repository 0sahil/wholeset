// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import WatchKit
import WholesetKit

/// The page to the left of the exercise: the system Now Playing controls, which drive
/// whatever is playing on the iPhone or the Watch. The system view gets the whole content
/// area below the top bar, with the system's own safe areas (top bar, page dots); the rest
/// countdown lives in the top bar instead (see ``NowPlayingTopBar``).
///
/// The Digital Crown sets the volume while this page is showing: no view of the app holds
/// the Crown here (see `WorkoutPagesView`).
struct NowPlayingPage: View {
    var body: some View {
        NowPlayingView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The top bar's leading item while Now Playing is showing: the elapsed clock alone, as on
/// the other pages, or while resting the clock, a timer glyph and the countdown. A glyph
/// rather than words, because the width the bar offers its leading item does not leave room
/// for the system time. If the countdown does not fit, the clock stands alone; nothing is
/// clipped.
///
/// VoiceOver reads the clock as on every page; the system Now Playing view below already
/// announces itself and what is playing, so the bar adds no title of its own. While resting
/// the countdown reads as "Rest" and the time left.
struct NowPlayingTopBar: View {
    let clock: WorkoutClock
    /// The running rest, or `nil` when not resting (or paused).
    let rest: RestTimer?

    var body: some View {
        if let rest {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    WorkoutClockLabel(clock: clock)
                    RestCountdown(rest: rest)
                }
                WorkoutClockLabel(clock: clock)
            }
        } else {
            WorkoutClockLabel(clock: clock)
        }
    }

    /// The timer glyph and the countdown: accent, one line at its natural width (so
    /// `ViewThatFits` measures it truthfully), one VoiceOver element.
    private struct RestCountdown: View {
        let rest: RestTimer

        var body: some View {
            HStack(spacing: 1) {
                Image(systemName: "timer")
                Text(timerInterval: rest.startedAt...rest.endDate, countsDown: true)
            }
            .font(.footnote.weight(.semibold).monospacedDigit())
            .foregroundStyle(Theme.accent)
            .lineLimit(1)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Rest"))
            .accessibilityValue(Text(timerInterval: rest.startedAt...rest.endDate, countsDown: true))
        }
    }
}
