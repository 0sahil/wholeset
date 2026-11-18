// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// 3-2-1 while the Health session warms up the sensors. Tap to skip.
/// With `info == nil` it shows a spinner while permissions are requested.
struct CountdownView: View {
    let routineName: String
    let info: CountdownInfo?
    let onFinish: () -> Void
    let onCancel: () -> Void

    private static let length: TimeInterval = 3

    var body: some View {
        VStack(spacing: 8) {
            if let info {
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    let left = remaining(info: info, at: context.date)
                    ZStack {
                        Circle()
                            .stroke(Theme.idleDot, lineWidth: 10)
                        Circle()
                            .trim(from: 0, to: left / Self.length)
                            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(max(1, Int(left.rounded(.up))))")
                            .font(Theme.number(.largeTitle))
                            .contentTransition(.numericText(countsDown: true))
                    }
                    .frame(maxWidth: 120, maxHeight: 120)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Starting in \(max(1, Int(left.rounded(.up)))) seconds")
                }
                .task(id: info.endsAt) {
                    guard !info.isFrozen else { return }
                    try? await Task.sleep(for: .seconds(max(0, info.endsAt.timeIntervalSinceNow)))
                    guard !Task.isCancelled else { return }
                    onFinish()
                }
            } else {
                ProgressView()
                    .accessibilityLabel("Preparing workout")
            }
            Text(routineName)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Button("Cancel", action: onCancel)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .frame(minHeight: 32)
                .accessibilityHint("Goes back without starting the workout.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: onFinish)
        .accessibilityAction(named: "Start now", onFinish)
    }

    private func remaining(info: CountdownInfo, at date: Date) -> Double {
        let now = info.isFrozen ? info.endsAt.addingTimeInterval(-2) : date
        return min(Self.length, max(0, info.endsAt.timeIntervalSince(now)))
    }
}
