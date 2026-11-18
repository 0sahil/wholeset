// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import WholesetKit

/// The current set of an exercise: the exercise name, the set dots, two big tiles (weight,
/// reps), the sets already logged when there is room, and the ••• + "Log set N" row at the
/// bottom where the thumb lands. The elapsed clock is in the top bar.
struct ExercisePage: View {
    let controller: WorkoutController
    let engine: WorkoutEngine
    let entry: SessionExercise
    let set: SetLog
    let selection: ValueTile?
    /// The Crown edit to show on the weight tile instead of the stored weight.
    let weightEdit: CrownEdit?
    /// The Crown edit to show on the reps tile instead of the stored reps.
    let repsEdit: CrownEdit?
    let toggle: (ValueTile) -> Void
    let adjust: (ValueTile, Int) -> Void
    let openMenu: () -> Void
    /// Whether "Log set" is the Double Tap primary action: only while this page is on screen
    /// and no sheet is up.
    let isPrimaryAction: Bool
    let applyHint: () -> Void
    let log: () -> Void

    var body: some View {
        let stored = engine.values(for: set)
        let lastLine = engine.lastLine(for: set)
        let hint = engine.currentProgressionHint
        let scale = controller.scale
        let weightKg = weightEdit.map { scale.kilograms(forSteps: $0.value) } ?? stored.weightKg
        let reps = repsEdit?.value ?? stored.reps
        let sets = entry.sortedSets
        let statuses = engine.statuses(of: entry)
        let number = (sets.firstIndex { $0.id == set.id } ?? 0) + 1
        let loggedRows = LoggedSetRow.rows(for: sets)
        // Both tiles size their number for the widest weight, so neither changes size while
        // stepping and the two numbers always match.
        let sizingTemplate = WeightFormat.widestString(scale: scale)
        VStack(alignment: .leading, spacing: 4) {
            ScreenHeader(title: entry.exercise?.name ?? "")
            SetLine(
                label: set.isWarmup
                    ? String(localized: "Warm-up · set \(number) of \(statuses.count)")
                    : String(localized: "Set \(number) of \(statuses.count)"),
                statuses: statuses
            )
            HStack(spacing: 5) {
                ValueTileView(
                    // While selected, all fraction digits ("62.0", "62.5"): no character
                    // appears or disappears between detents.
                    value: weightKg.map {
                        WeightFormat.string(kilograms: $0, scale: scale, showsAllFractionDigits: selection == .weight)
                    } ?? "–",
                    sizingTemplate: sizingTemplate,
                    unitLabel: controller.unit.symbol,
                    isSelected: selection == .weight,
                    accessibilityName: String(localized: "Weight"),
                    accessibilityValue: weightKg.map { SpokenWeight.string(kilograms: $0, scale: scale) } ?? String(localized: "Not set"),
                    onTap: { toggle(.weight) },
                    onLongPress: openMenu,
                    adjust: { adjust(.weight, $0) }
                )
                ValueTileView(
                    value: reps.map { "\($0)" } ?? "–",
                    sizingTemplate: sizingTemplate,
                    unitLabel: String(localized: "reps"),
                    isSelected: selection == .reps,
                    accessibilityName: String(localized: "Reps"),
                    accessibilityValue: reps.map { inflectedString("^[\($0) rep](inflect: true)") } ?? String(localized: "Not set"),
                    onTap: { toggle(.reps) },
                    onLongPress: openMenu,
                    adjust: { adjust(.reps, $0) }
                )
            }
            // "last 60 × 10" and the ↑ chip, then the sets logged so far, only when every row
            // fits above the buttons: Log never moves down for them (on a 40 mm watch the
            // table usually shows on the done page only). If even the line does not fit at
            // its normal size, it shrinks rather than pushing Log.
            let line = { (isCompact: Bool) in
                LastLineView(line: lastLine, hint: hint, scale: scale, isCompact: isCompact, apply: applyHint)
            }
            if loggedRows.isEmpty {
                ViewThatFits(in: .vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        line(false)
                        Spacer(minLength: 2)
                    }
                    line(true)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            } else {
                ViewThatFits(in: .vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        line(false)
                        LoggedSetTable(rows: loggedRows, scale: scale)
                            .padding(.top, 2)
                        Spacer(minLength: 2)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        line(false)
                        Spacer(minLength: 2)
                    }
                    line(true)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            HStack(spacing: 6) {
                MoreButton(action: openMenu)
                Button(action: log) {
                    Text("Log set \(number)")
                }
                .buttonStyle(AccentButtonStyle())
                .handGestureShortcut(.primaryAction, isEnabled: isPrimaryAction)
                .accessibilityHint("Saves this set and starts the rest timer.")
            }
        }
    }
}

/// "last 60 × 10" (or "first time") and, when the progression rule fires, the accent chip
/// "↑ 62.5 × 8" on the same line. Tapping the chip applies it to the remaining sets.
struct LastLineView: View {
    let line: LastLine
    let hint: ProgressionHint?
    let scale: WeightScale
    /// The smaller fallback used when the normal line does not fit.
    let isCompact: Bool
    let apply: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(lastText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityLabel(spokenLast)
            Spacer(minLength: 2)
            if let hint {
                Button(action: apply) {
                    Text("↑ \(WatchSetText.spaced(hint.values, scale: scale))")
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 7)
                        .padding(.vertical, isCompact ? 1 : 2)
                        .background(Theme.accent.opacity(0.18), in: Capsule())
                        // A taller touch area than the chip draws, without moving anything.
                        .contentShape(Capsule().inset(by: -4))
                }
                .buttonStyle(.plain)
                .layoutPriority(1)
                .accessibilityLabel("Suggested: \(WatchSetText.spoken(hint.values, scale: scale))")
                .accessibilityHint("Uses this weight and reps for the remaining sets.")
            }
        }
        .font(isCompact ? .caption2 : .footnote)
        .padding(.horizontal, 2)
    }

    private var lastText: String {
        switch line {
        case .firstTime: String(localized: "first time")
        case .previous(let values): String(localized: "last \(WatchSetText.spaced(values, scale: scale))")
        case .none: ""
        }
    }

    private var spokenLast: String {
        switch line {
        case .firstTime: String(localized: "First time doing this exercise")
        case .previous(let values): String(localized: "Last time: \(WatchSetText.spoken(values, scale: scale))")
        case .none: ""
        }
    }
}

/// A skipped exercise: "Skipped", the sets it got before, and Resume.
struct ExerciseSkippedPage: View {
    let controller: WorkoutController
    let engine: WorkoutEngine
    let entry: SessionExercise
    let openMenu: () -> Void

    var body: some View {
        let rows = LoggedSetRow.rows(for: entry.sortedSets)
        VStack(alignment: .leading, spacing: 3) {
            ScreenHeader(title: entry.exercise?.name ?? "")
            SetLine(label: String(localized: "Skipped"), statuses: engine.statuses(of: entry))
            if rows.isEmpty {
                Spacer(minLength: 2)
            } else {
                ViewThatFits(in: .vertical) {
                    VStack(spacing: 0) {
                        LoggedSetTable(rows: rows, scale: controller.scale)
                        Spacer(minLength: 2)
                    }
                    Spacer(minLength: 2)
                }
            }
            HStack(spacing: 6) {
                MoreButton(action: openMenu)
                Button("Resume") {
                    controller.setSkipped(false, for: entry)
                }
                .buttonStyle(AccentButtonStyle())
                .accessibilityLabel("Resume \(entry.exercise?.name ?? "")")
            }
        }
    }
}

/// A workout without exercises yet: "No exercises yet" and Add exercise.
struct EmptyWorkoutPage: View {
    let controller: WorkoutController
    let openMenu: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScreenHeader(title: controller.engine?.session.name ?? "")
            Text("No exercises yet")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            Spacer(minLength: 2)
            HStack(spacing: 6) {
                MoreButton(action: openMenu)
                Button("Add exercise") {
                    controller.openMenu(at: [.exercises(.add)])
                }
                .buttonStyle(AccentButtonStyle())
            }
        }
    }
}

/// "Done · 3 of 3 sets": shown after the last set of an exercise, with the table of its
/// logged sets and a button to the next unfinished exercise. Never jumps there by itself.
///
/// When the header, every row and the "Next: …" line fit above the ••• / Next row, the page
/// is static and the Crown keeps moving between exercises. Otherwise that content scrolls
/// (Crown and touch) while the ••• / Next row stays pinned at the bottom.
struct ExerciseDonePage: View {
    let controller: WorkoutController
    let engine: WorkoutEngine
    let entry: SessionExercise
    /// Focus for the scrolling layout, so the Crown scrolls it.
    let crownFocus: CrownFocus
    /// The page's Crown, used by the static layout only.
    let pageCrown: PageCrown
    /// Whether "Next" is the Double Tap primary action: only while this page is on screen
    /// and no sheet is up. "End workout" never is.
    let isPrimaryAction: Bool
    let openMenu: () -> Void

    var body: some View {
        let next = nextEntry
        VStack(alignment: .leading, spacing: 4) {
            // The buttons are built once, below the choice of layout, so there is only ever
            // one "Next" (and one primary action) in the hierarchy.
            ViewThatFits(in: .vertical) {
                summary(next: next)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .modifier(pageCrown)

                ScrollView {
                    summary(next: next)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .claimsCrown(.doneTable, with: crownFocus)
            }
            actions(next: next)
        }
    }

    /// The next unfinished exercise and its index, if any.
    private var nextEntry: (index: Int, name: String)? {
        guard let next = engine.nextUnfinishedEntry(after: entry),
              let index = engine.entries.firstIndex(where: { $0 === next }) else { return nil }
        return (index, next.exercise?.name ?? "")
    }

    /// Name, "Done · 3 of 3 sets", the logged sets and "Next: …".
    private func summary(next: (index: Int, name: String)?) -> some View {
        let progress = engine.progress(of: entry)
        return VStack(alignment: .leading, spacing: 3) {
            ScreenHeader(title: entry.exercise?.name ?? "")
            SetLine(
                label: String(localized: "Done · \(progress.completed) of \(progress.total) sets"),
                statuses: engine.statuses(of: entry)
            )
            LoggedSetTable(rows: LoggedSetRow.rows(for: entry.sortedSets), scale: controller.scale)
            if let next {
                // The full name sits here so the button label can stay short.
                Text("Next: \(next.name)")
                    .font(.footnote.weight(.medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
    }

    /// ••• and Next (or End workout after the last exercise).
    private func actions(next: (index: Int, name: String)?) -> some View {
        HStack(spacing: 6) {
            MoreButton(action: openMenu)
            if let next {
                Button("Next") {
                    controller.selectEntry(at: next.index)
                }
                .buttonStyle(AccentButtonStyle())
                .handGestureShortcut(.primaryAction, isEnabled: isPrimaryAction)
                .accessibilityLabel("Next: \(next.name)")
            } else {
                Button("End workout") {
                    controller.sheet = .endConfirm
                }
                .buttonStyle(AccentButtonStyle())
            }
        }
    }
}

/// The logged sets of an exercise, one row each: the set number on the left ("W" for a
/// warm-up, whose row is drawn secondary), "60 kg × 10" on the right, thin rules between.
struct LoggedSetTable: View {
    let rows: [LoggedSetRow]
    let scale: WeightScale

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(Theme.idleDot)
                        .frame(height: 0.5)
                        .accessibilityHidden(true)
                }
                LoggedSetRowView(row: row, scale: scale)
            }
        }
    }
}

private struct LoggedSetRowView: View {
    let row: LoggedSetRow
    let scale: WeightScale

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(row.isWarmup ? String(localized: "W", comment: "Warm-up set, in the logged-sets table") : "\(row.number)")
                .frame(minWidth: 14, alignment: .leading)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(row.valueText(scale: scale))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.footnote.monospacedDigit())
        .foregroundStyle(row.isWarmup ? .secondary : .primary)
        // No vertical padding: the line height leaves room above and below the rules.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenRow)
    }

    /// "Set 2, 60 kilograms, 10 reps"; "Warm-up, 20 kilograms, 10 reps".
    private var spokenRow: String {
        var parts = [row.isWarmup ? String(localized: "Warm-up") : String(localized: "Set \(row.number)")]
        if let weight = row.weightKg {
            parts.append(SpokenWeight.string(kilograms: weight, scale: scale))
        }
        parts.append(row.reps.map { inflectedString("^[\($0) rep](inflect: true)") } ?? String(localized: "reps not recorded"))
        return parts.formatted(.list(type: .and, width: .narrow))
    }
}

/// A weight as VoiceOver should say it, e.g. "60 kilograms".
enum SpokenWeight {
    static func string(kilograms: Double, scale: WeightScale) -> String {
        let unit: UnitMass = scale.unit == .kg ? .kilograms : .pounds
        return Measurement(value: scale.displayValue(forKilograms: kilograms), unit: unit)
            .formatted(.measurement(width: .wide, numberFormatStyle: .number.precision(.fractionLength(0...scale.fractionDigits))))
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
    /// The widest text `value` can become (e.g. "888.8"); the number is laid out at its width.
    let sizingTemplate: String
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
            Text(paddedValue)
                .font(Theme.number(.title))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.identity)
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

    /// `value` followed by invisible characters that make it as wide as `sizingTemplate`
    /// (digits are tabular), so shrink-to-fit picks one font size for every value instead
    /// of jumping between e.g. "100" and "100.5".
    private var paddedValue: AttributedString {
        var text = AttributedString(value)
        var filler = AttributedString(StableNumberWidth.filler(for: value, toMatch: sizingTemplate))
        filler.foregroundColor = .clear
        text.append(filler)
        return text
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
        .accessibilityHint("Swap, skip or add exercises, change sets, see all exercises, or end the workout.")
    }
}
