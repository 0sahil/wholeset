// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import WholesetKit

// MARK: - I2 Detected

/// What was found in the file: the app, how many workouts over which months, the first
/// workout as it will be imported, the unit, and the date order when the file needs one.
struct ImportDetectedView: View {
    @Bindable var model: ImportFlowModel

    var body: some View {
        Group {
            if let result = model.result {
                content(result)
            } else {
                ImportBusyView(title: String(localized: "Reading File…"))
            }
        }
        .navigationTitle("Import")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ result: ImportParseResult) -> some View {
        List {
            Section {
            } header: {
                ImportListHeader {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(result.format.exportTitle)
                                .font(.title2.bold())
                                .foregroundStyle(.primary)
                            if result.format.isBeta { BetaTag() }
                        }
                        Text(summaryLine(result))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if let first = result.workouts.first {
                Section("First Workout in File") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(HistoryFormat.sessionName(first.name))
                        Text(firstLine(first, result: result))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    if let exercise = first.exercises.first {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                            Text(setsLine(exercise, unit: previewUnit(result)))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if let sample = model.dateOrderSample {
                Section {
                    Picker("Dates", selection: Binding(get: { model.dateOrder ?? .dayMonthYear }, set: { model.setDateOrder($0) })) {
                        // Only orders that can apply to dates written with the year last.
                        ForEach([DateOrder.dayMonthYear, .monthDayYear]) { order in
                            Text(order.label).tag(order)
                        }
                    }
                } header: {
                    Text("Dates")
                } footer: {
                    Text("The file writes dates like “\(sample)”, which can be read two ways. Choose how; the first workout above shows the result.")
                }
            }
            Section {
                unitRow(result)
            } header: {
                Text("Units")
            } footer: {
                Text(unitFooter(result))
            }
            if !result.skippedRows.isEmpty {
                Section {
                    NavigationLink(value: ImportFlowModel.Step.rowsNotRead) {
                        LabeledContent("Rows Not Read", value: result.skippedRows.count.formatted())
                    }
                } footer: {
                    Text("These rows hold no set Wholeset can import, such as cardio. Nothing is left out without being listed.")
                }
            }
            if result.encoding.isFallback {
                Section {
                    Label("The file isn't saved as UTF-8, so accented letters may look wrong. Exporting it again may fix this.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .importBottomBar {
            Button("Continue") { model.reviewExercises() }
                .buttonStyle(AccentFillButtonStyle())
                .disabled(model.activity != .idle)
        }
        .overlay {
            if model.activity == .parsing {
                ImportBusyView(title: String(localized: "Reading File…"))
            }
        }
    }

    @ViewBuilder
    private func unitRow(_ result: ImportParseResult) -> some View {
        if model.choosesUnit {
            Picker("Weights in File", selection: Binding(get: { model.chosenUnit }, set: { model.setUnit($0) })) {
                Text(verbatim: WeightUnit.kg.symbol).tag(WeightUnit.kg)
                Text(verbatim: WeightUnit.lb.symbol).tag(WeightUnit.lb)
            }
            .pickerStyle(.menu)
        } else {
            LabeledContent("Weights in File") {
                HStack(spacing: 6) {
                    Text(unitsText(result))
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    /// "214 workouts · Jan 2024 – Nov 2026".
    private func summaryLine(_ result: ImportParseResult) -> String {
        let count = inflectedString("^[\(result.workoutCount) workout](inflect: true)")
        guard let range = result.dateRange else { return count }
        let style = Date.FormatStyle.dateTime.month(.abbreviated).year()
        let first = range.lowerBound.formatted(style)
        let last = range.upperBound.formatted(style)
        return first == last ? "\(count) · \(first)" : "\(count) · \(first) – \(last)"
    }

    /// "5 Jan 2024, 17:00 · 6 exercises" (no time for files that have none).
    private func firstLine(_ workout: ImportedWorkout, result: ImportParseResult) -> String {
        let hasTime = result.format != .fitNotes && ImportDateParser.hasTime(result.dateReading.sample)
        let date = hasTime
            ? workout.startedAt.formatted(date: .abbreviated, time: .shortened)
            : workout.startedAt.formatted(date: .abbreviated, time: .omitted)
        return "\(date) · \(inflectedString("^[\(workout.exercises.count) exercise](inflect: true)"))"
    }

    /// The first exercise's sets in the file's unit: "60 kg × 10, 60 × 10, W 40 × 8".
    private func setsLine(_ exercise: ImportedExercise, unit: WeightUnit) -> String {
        let shown = exercise.sets.prefix(6).enumerated().map { index, set in
            let text = index == 0
                ? HistoryFormat.set(weightKg: set.weightKg, reps: set.reps, unit: unit)
                : HistoryFormat.compactSet(weightKg: set.weightKg, reps: set.reps, unit: unit)
            return set.isWarmup ? "W \(text)" : text
        }
        let more = exercise.sets.count > 6 ? ", …" : ""
        return shown.joined(separator: ", ") + more
    }

    private func previewUnit(_ result: ImportParseResult) -> WeightUnit {
        switch result.weightUnitSource {
        case .header(let unit), .chosen(let unit): unit
        case .column: result.stats.unitsFound.first ?? model.chosenUnit
        }
    }

    private func unitsText(_ result: ImportParseResult) -> String {
        switch result.weightUnitSource {
        case .header(let unit), .chosen(let unit):
            unit.symbol
        case .column:
            result.stats.unitsFound.isEmpty ? model.chosenUnit.symbol : result.stats.unitsFound.map(\.symbol).formatted(.list(type: .and))
        }
    }

    private func unitFooter(_ result: ImportParseResult) -> String {
        switch result.weightUnitSource {
        case .header:
            result.format == .fitbod
                ? String(localized: "Fitbod saves kilograms. Weights entered in pounds are turned back into the pounds you lifted.")
                : String(localized: "Read from the column name. Weights are saved in kilograms and shown in your unit.")
        case .column:
            result.stats.rowsWithAssumedUnit > 0
                ? String(localized: "Read from each row. \(inflectedString("^[\(result.stats.rowsWithAssumedUnit) row](inflect: true)")) had no unit and use the unit of the rows before them.")
                : String(localized: "Read from each row. Weights are saved in kilograms and shown in your unit.")
        case .chosen:
            String(localized: "The file doesn't say. Choose the unit you logged in; the first workout above shows the result.")
        }
    }
}

// MARK: - I5 Columns

/// For other apps' files: what each column holds, with a sample value.
struct ImportColumnsView: View {
    @Bindable var model: ImportFlowModel

    var body: some View {
        Group {
            if let file = model.file, let mapping = model.mapping {
                content(file: file, mapping: mapping)
            } else {
                ImportBusyView(title: String(localized: "Reading File…"))
            }
        }
        .navigationTitle("Columns")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(file: ImportFile, mapping: GenericMapping) -> some View {
        let header = file.table.header
        let samples = GenericMapping.samples(columnCount: header.count, rows: file.table.rows.prefix(50))
        return List {
            Section {
            } header: {
                ImportListHeader {
                    Text("Tell Wholeset what each column holds. \(inflectedString("^[\(header.count) column](inflect: true)")), \(inflectedString("^[\(file.table.rows.count) row](inflect: true)")).")
                }
            }
            Section {
                ForEach(header.names.indices, id: \.self) { index in
                    Picker(selection: role(of: index)) {
                        ForEach(ColumnRole.allCases) { role in
                            Text(role.label).tag(role)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(header.names[index].isEmpty ? String(localized: "Column \(index + 1)") : header.names[index])
                            Text(samples[index].isEmpty ? String(localized: "empty") : "“\(samples[index])”")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Text("Columns")
            } footer: {
                if !mapping.missingRoles.isEmpty {
                    Text("Still needed: \(mapping.missingRoles.map(\.label).formatted(.list(type: .and))).")
                } else {
                    Text("Required: date, exercise and reps. Rows with the same date and workout name become one workout.")
                }
            }
            if mapping.column(for: .weight) != nil, mapping.weightUnitSource(in: header, chosen: model.chosenUnit).isChosen {
                Section {
                    Picker("Weight Unit", selection: $model.chosenUnit) {
                        Text(verbatim: WeightUnit.kg.symbol).tag(WeightUnit.kg)
                        Text(verbatim: WeightUnit.lb.symbol).tag(WeightUnit.lb)
                    }
                    .pickerStyle(.menu)
                } footer: {
                    Text("No column says the unit, so choose the one the weights are in.")
                }
            }
        }
        .importBottomBar {
            Button("Preview") { model.previewColumns() }
                .buttonStyle(AccentFillButtonStyle())
                .disabled(!mapping.isComplete || model.activity != .idle)
        }
        .overlay {
            if model.activity == .parsing {
                ImportBusyView(title: String(localized: "Reading File…"))
            }
        }
    }

    private func role(of index: Int) -> Binding<ColumnRole> {
        Binding(
            get: { model.mapping?.role(ofColumn: index) ?? .ignore },
            set: { model.mapping?.assign($0, toColumn: index) }
        )
    }
}
