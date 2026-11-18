// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import WholesetKit

/// The page to the right of the exercise: heart rate, active energy, volume so far,
/// Pause/Resume and End, then every exercise with its progress (tap one to go to it). The
/// elapsed time is in the top bar, as on the other pages.
///
/// Metrics and buttons come first and are short enough that Pause and End are on screen
/// without scrolling at the default text size on the smallest watch; the exercise list
/// follows below them and the page scrolls with the Crown (everything scrolls at larger
/// text sizes). The page takes the Crown only while it is showing.
struct StatsView: View {
    let controller: WorkoutController
    /// Counts sheets that finished closing: a sheet takes focus and does not give it back.
    let sheetDismissals: Int

    @FocusState private var isScrollFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    header
                    metrics
                    buttons
                        .padding(.top, 6)
                    if let engine = controller.engine, !engine.entries.isEmpty {
                        ExerciseList(controller: controller, engine: engine)
                            .padding(.top, 10)
                            .id(ScrollAnchor.exercises)
                    }
                }
                .padding(.horizontal, 4)
            }
            #if DEBUG
            .task(id: controller.page == .stats) {
                // `-WholesetDemoScroll exercises`: show the list for a screenshot.
                guard controller.page == .stats, DemoHarness.requestedScrollAnchor() == .exercises else { return }
                await Task.yield()
                proxy.scrollTo(ScrollAnchor.exercises, anchor: .top)
            }
            #endif
        }
        .focused($isScrollFocused)
        .task(id: crownClaim) {
            guard crownClaim.isEligible else { return }
            isScrollFocused = true
        }
        .onChange(of: controller.page) { _, page in
            if page != .stats { isScrollFocused = false }
        }
    }

    /// When the list takes the Crown: each time the page shows, and after a sheet closes.
    private var crownClaim: CrownClaim {
        CrownClaim(
            isEligible: scenePhase == .active && controller.page == .stats && controller.sheet == nil,
            sheetDismissals: sheetDismissals
        )
    }

    private var header: some View {
        ScreenHeader(title: controller.engine?.session.name ?? "") {
            if let rest = controller.rest, controller.isPaused == false {
                Text("Rest \(Text(timerInterval: rest.startedAt...rest.endDate, countsDown: true))")
            } else if controller.isPaused {
                Text("Paused")
            }
        }
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 1) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    heartRate
                    energy
                }
                VStack(alignment: .leading, spacing: 1) {
                    heartRate
                    energy
                }
            }
            MetricRow(
                value: controller.engine.map { WeightFormat.volume(kilograms: $0.totals.volumeKg, unit: controller.unit) },
                unit: controller.unit.symbol,
                label: String(localized: "Volume")
            )
        }
    }

    /// Pause (or Resume) and End side by side, each label on one line at its full size. If
    /// the two do not fit side by side (larger text, longer translations), they stack, still
    /// one line each.
    private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                pauseButton
                endButton
            }
            VStack(spacing: 4) {
                pauseButton
                endButton
            }
        }
    }

    private var pauseButton: some View {
        Button(controller.isPaused ? "Resume" : "Pause") {
            controller.togglePause()
        }
        .buttonStyle(SecondaryButtonStyle(isSingleLine: true))
        .accessibilityLabel(controller.isPaused ? "Resume workout" : "Pause workout")
    }

    private var endButton: some View {
        Button("End") {
            controller.sheet = .endConfirm
        }
        .buttonStyle(SecondaryButtonStyle(foreground: Theme.destructive, isSingleLine: true))
        .accessibilityLabel("End workout")
    }

    private var heartRate: some View {
        MetricRow(
            value: controller.health.heartRate.map { "\(Int($0.rounded()))" },
            unit: String(localized: "bpm"),
            label: String(localized: "Heart rate")
        )
    }

    private var energy: some View {
        MetricRow(
            value: controller.health.activeKilocalories.map { "\(Int($0.rounded()))" },
            unit: String(localized: "kcal"),
            label: String(localized: "Active energy")
        )
    }
}

/// Every exercise of the workout with "logged/target" (accent when complete) or "Skipped",
/// the current one outlined. Tapping one goes to it on the exercise page, as in the menu's
/// All exercises.
private struct ExerciseList: View {
    let controller: WorkoutController
    let engine: WorkoutEngine

    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Exercises")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(engine.entries.enumerated()), id: \.element.id) { index, entry in
                let isCurrent = index == engine.currentIndex
                Button {
                    controller.jumpToEntry(at: index)
                } label: {
                    ProgressRow(engine: engine, entry: entry, isCurrent: isCurrent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTapHeight, alignment: .leading)
                        .background(Theme.tile, in: shape)
                        .overlay {
                            shape.strokeBorder(isCurrent ? Color.white : .clear, lineWidth: 2)
                        }
                        .contentShape(shape)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows this exercise.")
            }
        }
    }
}

/// "132 bpm", or "--" when the value is not available.
private struct MetricRow: View {
    let value: String?
    let unit: String
    let label: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value ?? "--")
                .font(Theme.number(.headline))
            Text(unit)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value.map { "\($0) \(unit)" } ?? String(localized: "Not available"))
    }
}
