// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import WholesetKit

/// "End workout?" naming what is still unlogged, with a separate, confirmed Discard.
struct EndConfirmView: View {
    let controller: WorkoutController
    @State private var isConfirmingDiscard = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("End workout?")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                unfinishedText
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("End") {
                    controller.endWorkout()
                }
                .buttonStyle(SecondaryButtonStyle(foreground: Theme.destructive))
                .accessibilityLabel("End and save workout")
                .padding(.top, 4)
                Button("Keep going") {
                    controller.sheet = nil
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("Discard workout") {
                    isConfirmingDiscard = true
                }
                .font(.footnote)
                .foregroundStyle(Theme.destructive)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: Theme.minTapHeight)
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
        .confirmationDialog("Discard this workout?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) {
                controller.discardWorkout()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its logged sets are deleted and nothing is saved to Apple Health.")
        }
    }

    private var unfinishedText: Text {
        let unfinished = controller.engine?.unfinishedExercises ?? []
        guard !unfinished.isEmpty else { return Text("Every set is logged.") }
        let sets = unfinished.reduce(0) { $0 + $1.remainingSets }
        let names = unfinished.map(\.name).formatted(.list(type: .and))
        return Text("^[\(sets) set](inflect: true) left in \(names).")
    }
}

/// The end-of-workout summary.
struct SummaryView: View {
    let info: WorkoutSummaryInfo
    let unit: WeightUnit
    let done: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                ScreenHeader(title: String(localized: "Done"))
                Text("\(info.routineName) · \(durationText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(WeightFormat.volume(kilograms: info.volumeKg, unit: unit))
                        .font(Theme.number(.title2))
                    Text(unit.symbol)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Volume")
                Group {
                    if let kcal = info.activeKilocalories {
                        Text("^[\(info.workingSets) set](inflect: true) · \(Int(kcal.rounded())) kcal")
                    } else {
                        Text("^[\(info.workingSets) set](inflect: true)")
                    }
                    switch (info.averageHeartRate, info.maxHeartRate) {
                    case let (average?, max?):
                        Text("\(Int(average.rounded())) avg · \(Int(max.rounded())) max bpm")
                    case let (average?, nil):
                        Text("\(Int(average.rounded())) avg bpm")
                    case let (nil, max?):
                        Text("\(Int(max.rounded())) max bpm")
                    case (nil, nil):
                        EmptyView()
                    }
                }
                .font(.footnote.monospacedDigit())
                healthLine
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                Button("Done", action: done)
                    .buttonStyle(AccentButtonStyle())
                    .padding(.top, 6)
            }
            .padding(.horizontal, 4)
        }
    }

    private var durationText: String {
        Duration.seconds(Int(info.duration))
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    @ViewBuilder
    private var healthLine: some View {
        switch info.health {
        case .saving:
            HStack(spacing: 4) {
                ProgressView()
                    .frame(width: 16, height: 16)
                Text("Saving to Apple Health…")
            }
        case .saved:
            Label("Saved to Apple Health", systemImage: "heart.fill")
        case .notSaved:
            Text("Not saved to Apple Health.")
        }
    }
}

/// Shown on launch when a workout was still running (after a crash, force quit or reboot).
struct RestoredView: View {
    let controller: WorkoutController

    var body: some View {
        ScrollView {
            // Kept compact so Continue is on screen without scrolling on the smallest watch.
            VStack(alignment: .leading, spacing: 3) {
                ScreenHeader(title: controller.engine?.session.name ?? "") {
                    Text("Still running")
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let clock = controller.clock {
                        ElapsedText(clock: clock)
                            .font(Theme.number(.title2))
                    }
                    Text("^[\(controller.engine?.totals.completedSets ?? 0) set](inflect: true) logged")
                        .font(.footnote)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                healthLine
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Continue") {
                    controller.continueRestored()
                }
                .buttonStyle(AccentButtonStyle())
                .padding(.top, 4)
                Button("End and save") {
                    controller.endWorkout()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var healthLine: some View {
        switch controller.restoredHealthStatus {
        case .reconnecting:
            Text("Reconnecting to Health…")
        case .recording:
            Text("Health still recording.")
        case .notRecording:
            Text("Health stopped recording. Your sets are safe; End saves them here.")
        }
    }
}
