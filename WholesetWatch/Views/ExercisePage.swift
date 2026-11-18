// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import WholesetKit

/// The current set of an exercise: two big tiles (weight, reps), the set dots, and the
/// ••• + "Log set N" row at the bottom where the thumb lands.
struct ExercisePage: View {
    let controller: WorkoutController
    let engine: WorkoutEngine
    let entry: SessionExercise
    let set: SetLog
    let selection: ValueTile?
    let toggle: (ValueTile) -> Void
    let adjust: (ValueTile, Int) -> Void
    let openMenu: () -> Void
    let log: () -> Void

    var body: some View {
        let values = engine.values(for: set)
        let statuses = engine.statuses(of: entry)
        let number = (statuses.firstIndex { $0.id == set.id } ?? 0) + 1
        VStack(alignment: .leading, spacing: 4) {
            ScreenHeader(title: entry.exercise?.name ?? "") {
                if let clock = controller.clock {
                    ElapsedText(clock: clock)
                }
            }
            SetLine(
                label: set.isWarmup
                    ? String(localized: "Warm-up · set \(number) of \(statuses.count)")
                    : String(localized: "Set \(number) of \(statuses.count)"),
                statuses: statuses
            )
            HStack(spacing: 5) {
                ValueTileView(
                    value: weightText(values.weightKg),
                    unitLabel: controller.unit.symbol,
                    isSelected: selection == .weight,
                    accessibilityName: String(localized: "Weight"),
                    accessibilityValue: weightAccessibilityValue(values.weightKg),
                    onTap: { toggle(.weight) },
                    onLongPress: openMenu,
                    adjust: { adjust(.weight, $0) }
                )
                ValueTileView(
                    value: values.reps.map { "\($0)" } ?? "–",
                    unitLabel: String(localized: "reps"),
                    isSelected: selection == .reps,
                    accessibilityName: String(localized: "Reps"),
                    accessibilityValue: values.reps.map { inflectedString("^[\($0) rep](inflect: true)") } ?? String(localized: "Not set"),
                    onTap: { toggle(.reps) },
                    onLongPress: openMenu,
                    adjust: { adjust(.reps, $0) }
                )
            }
            Spacer(minLength: 2)
            HStack(spacing: 6) {
                MoreButton(action: openMenu)
                Button(action: log) {
                    Text("Log set \(number)")
                }
                .buttonStyle(AccentButtonStyle())
                .accessibilityHint("Saves this set and starts the rest timer.")
            }
        }
    }

    private func weightText(_ kilograms: Double?) -> String {
        kilograms.map { WeightFormat.string(kilograms: $0, scale: controller.scale) } ?? "–"
    }

    private func weightAccessibilityValue(_ kilograms: Double?) -> String {
        guard let kilograms else { return String(localized: "Not set") }
        let scale = controller.scale
        let unit: UnitMass = scale.unit == .kg ? .kilograms : .pounds
        return Measurement(value: scale.displayValue(forKilograms: kilograms), unit: unit)
            .formatted(.measurement(width: .wide, numberFormatStyle: .number.precision(.fractionLength(0...scale.fractionDigits))))
    }
}

/// "Done · 3 of 3 sets": shown after the last set of an exercise, with a button to the
/// next unfinished exercise. Never jumps there by itself.
struct ExerciseDonePage: View {
    let controller: WorkoutController
    let engine: WorkoutEngine
    let entry: SessionExercise
    let openMenu: () -> Void

    var body: some View {
        let statuses = engine.statuses(of: entry)
        let progress = engine.progress(of: entry)
        let next = engine.nextUnfinishedEntry(after: entry)
        VStack(alignment: .leading, spacing: 4) {
            ScreenHeader(title: entry.exercise?.name ?? "") {
                if let clock = controller.clock {
                    ElapsedText(clock: clock)
                }
            }
            SetLine(label: String(localized: "Done · \(progress.completed) of \(progress.total) sets"), statuses: statuses)
            Text(loggedSummary)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            let nextIndex = next.flatMap { next in engine.entries.firstIndex { $0 === next } }
            let nextName = next?.exercise?.name ?? ""
            if nextIndex != nil {
                // The full name sits above the row so the button label can stay short.
                Text("Next: \(nextName)")
                    .font(.footnote.weight(.medium))
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .accessibilityHidden(true)
            }
            HStack(spacing: 6) {
                MoreButton(action: openMenu)
                if let nextIndex {
                    Button("Next") {
                        controller.selectEntry(at: nextIndex)
                    }
                    .buttonStyle(AccentButtonStyle())
                    .accessibilityLabel("Next: \(nextName)")
                } else {
                    Button("End workout") {
                        controller.sheet = .endConfirm
                    }
                    .buttonStyle(AccentButtonStyle())
                }
            }
        }
    }

    /// "60 × 10 · 60 × 10 · 60 × 9".
    private var loggedSummary: String {
        entry.sortedSets
            .filter { $0.completedAt != nil }
            .map { set in
                let reps = set.reps.map { "\($0)" } ?? "–"
                guard let weight = set.weightKg else { return String(localized: "\(reps) reps") }
                return "\(WeightFormat.string(kilograms: weight, scale: controller.scale)) × \(reps)"
            }
            .joined(separator: " · ")
    }
}

/// "Set 2 of 3 ● ● ○".
struct SetLine: View {
    let label: String
    let statuses: [SetStatus]

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            SetDots(statuses: statuses)
                .layoutPriority(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One dot per set: logged in the accent colour, the current set white, the rest grey.
/// Warm-up sets are drawn as rings.
struct SetDots: View {
    let statuses: [SetStatus]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(statuses) { status in
                dot(for: status)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(statuses.count { $0.isCompleted }) of \(statuses.count) sets logged")
    }

    @ViewBuilder
    private func dot(for status: SetStatus) -> some View {
        let color = status.isCompleted ? Theme.accent : (status.isCurrent ? Color.white : Theme.idleDot)
        if status.isWarmup {
            Circle().strokeBorder(color, lineWidth: 1.5)
        } else {
            Circle().fill(color)
        }
    }
}

/// A weight or reps tile. Tap to select (accent outline) or release; long-press opens the menu.
struct ValueTileView: View {
    let value: String
    let unitLabel: String
    let isSelected: Bool
    let accessibilityName: String
    let accessibilityValue: String
    let onTap: () -> Void
    let onLongPress: () -> Void
    let adjust: (Int) -> Void

    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(Theme.number(.title))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(unitLabel)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.tile, in: shape)
        .overlay {
            shape.strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 2)
        }
        .contentShape(shape)
        .gesture(
            LongPressGesture(minimumDuration: 0.5)
                .exclusively(before: TapGesture())
                .onEnded { result in
                    switch result {
                    case .first: onLongPress()
                    case .second: onTap()
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Double-tap to select, then turn the Digital Crown to change it.")
        .accessibilityAction(.default, onTap)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(1)
            case .decrement: adjust(-1)
            @unknown default: break
            }
        }
    }
}

/// The round ••• button.
struct MoreButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "ellipsis")
                .font(.body.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: Theme.minTapHeight, height: Theme.minTapHeight)
                .background(Theme.control, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More")
        .accessibilityHint("Add or remove a set, mark a warm-up, see all exercises, or end the workout.")
    }
}
