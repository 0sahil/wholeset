// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import WatchKit
import WholesetKit

/// The page to the left of the exercise: the system Now Playing controls, which drive
/// whatever is playing on the iPhone or the Watch. The system view gets the whole content
/// area below the top bar, with the system's own safe areas (top bar, page dots); the page
/// title and the rest countdown live in the top bar instead (see ``NowPlayingTopBar``).
///
/// The Digital Crown sets the volume while this page is showing: no view of the app holds
/// the Crown here (see `WorkoutPagesView`).
struct NowPlayingPage: View {
    var body: some View {
        NowPlayingView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The top bar's leading item while Now Playing is showing: the elapsed clock as on the
/// other pages, then "Now Playing", or "Rest 1:16" while resting. When the bar is too narrow
/// for the words (small watch, large text), a glyph replaces them (a note, or a timer with
/// the countdown), and if even that does not fit, the clock stands alone; nothing is clipped.
struct NowPlayingTopBar: View {
    let clock: WorkoutClock
    /// The running rest, or `nil` when not resting (or paused).
    let rest: RestTimer?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
                WorkoutClockLabel(clock: clock)
                fullTitle
            }
            HStack(spacing: 4) {
                WorkoutClockLabel(clock: clock)
                compactTitle
            }
            WorkoutClockLabel(clock: clock)
        }
    }

    private var fullTitle: some View {
        Group {
            if let rest {
                Text("Rest \(Text(timerInterval: rest.startedAt...rest.endDate, countsDown: true))")
            } else {
                Text("Now Playing")
            }
        }
        .modifier(TitleStyle(rest: rest))
    }

    private var compactTitle: some View {
        Group {
            if let rest {
                HStack(spacing: 1) {
                    Image(systemName: "timer")
                    Text(timerInterval: rest.startedAt...rest.endDate, countsDown: true)
                }
            } else {
                Image(systemName: "music.note")
            }
        }
        .modifier(TitleStyle(rest: rest))
    }

    /// Accent, one line at its natural width (so `ViewThatFits` measures it truthfully),
    /// one VoiceOver element.
    private struct TitleStyle: ViewModifier {
        let rest: RestTimer?

        func body(content: Content) -> some View {
            content
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rest == nil ? Text("Now Playing") : Text("Rest"))
                .accessibilityValue(rest.map { Text(timerInterval: $0.startedAt...$0.endDate, countsDown: true) } ?? Text(""))
        }
    }
}
