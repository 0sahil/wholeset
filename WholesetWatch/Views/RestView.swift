// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import WholesetKit

/// The rest countdown with +30 s and Skip. Shown in place of the exercise page while
/// resting; when the rest ends the current set is back on screen.
struct RestView: View {
    let rest: RestTimer
    let clock: WorkoutClock?
    let extend: () -> Void
    let skip: () -> Void

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        VStack(spacing: 2) {
            ScreenHeader(title: String(localized: "Rest")) {
                if let clock {
                    ElapsedText(clock: clock)
                }
            }
            TimelineView(.periodic(from: rest.startedAt, by: isLuminanceReduced ? 60 : 1)) { context in
                let remaining = rest.remaining(at: context.date)
                RestRing(
                    fraction: rest.fractionRemaining(at: context.date),
                    text: isLuminanceReduced ? TimeText.minutesLeft(remaining) : TimeText.clock(remaining.rounded(.up))
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Rest")
                .accessibilityValue(
                    Duration.seconds(Int(remaining.rounded(.up)))
                        .formatted(.units(allowed: [.minutes, .seconds], width: .wide))
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 6) {
                Button("+30 s", action: extend)
                    .accessibilityLabel("Add 30 seconds")
                Button("Skip", action: skip)
                    .accessibilityLabel("Skip rest")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }
}

/// The progress ring as large as the space it is given, with the remaining time sized to
/// sit inside the ring's inner diameter ("0:45" through "10:00").
private struct RestRing: View {
    let fraction: Double
    let text: String

    private static let lineWidth: CGFloat = 8
    /// Share of the inner diameter the time may span; the rest is clear space to the ring.
    private static let textWidthRatio: CGFloat = 0.74
    /// Starting font size relative to the inner diameter; long values scale down from here.
    private static let fontSizeRatio: CGFloat = 0.36

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let inner = max(1, diameter - 2 * Self.lineWidth)
            ZStack {
                Circle()
                    .strokeBorder(Theme.idleDot, lineWidth: Self.lineWidth)
                Circle()
                    .inset(by: Self.lineWidth / 2)
                    .trim(from: 0, to: fraction)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(text)
                    .font(.system(size: inner * Self.fontSizeRatio, weight: .semibold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                    .frame(width: inner * Self.textWidthRatio)
            }
            .frame(width: diameter, height: diameter)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}
