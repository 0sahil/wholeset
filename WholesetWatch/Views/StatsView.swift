// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import WholesetKit

/// The page to the right of the exercise: heart rate, active energy, volume so far, and
/// Pause/Resume and End. The elapsed time is in the top bar, as on the exercise page.
struct StatsView: View {
    let controller: WorkoutController

    var body: some View {
        // Fits without scrolling at the default text size on the smallest watch, so Pause
        // and End are always on screen; larger text sizes fall back to a scroll view.
        ViewThatFits(in: .vertical) {
            content
                .frame(maxHeight: .infinity, alignment: .top)
            ScrollView {
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 1) {
            ScreenHeader(title: controller.engine?.session.name ?? "") {
                if let rest = controller.rest, controller.isPaused == false {
                    Text("Rest \(Text(timerInterval: rest.startedAt...rest.endDate, countsDown: true))")
                } else if controller.isPaused {
                    Text("Paused")
                }
            }
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
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                Button(controller.isPaused ? "Resume" : "Pause") {
                    controller.togglePause()
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("End") {
                    controller.sheet = .endConfirm
                }
                .buttonStyle(SecondaryButtonStyle(foreground: Theme.destructive))
                .accessibilityLabel("End workout")
            }
        }
        .padding(.horizontal, 4)
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
