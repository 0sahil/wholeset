// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import SwiftUI
import WholesetKit

/// Every distinct exercise name in the file with what it will become. Only the uncertain
/// ones need a look; tapping a name rematches it or makes a custom exercise. The bottom
/// button imports, with progress, and can stop between batches.
struct ImportMatchView: View {
    @Bindable var model: ImportFlowModel
    @State private var editing: ImportFlowModel.MatchRow?

    private var checkRows: [ImportFlowModel.MatchRow] { model.matches.filter(\.found.needsLook) }
    private var matchedRows: [ImportFlowModel.MatchRow] { model.matches.filter { !$0.found.needsLook } }

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $model.showsAllMatches) {
                    Text("Check (\(checkRows.count))").tag(false)
                    Text("All \(model.matches.count)").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if !model.showsAllMatches {
                Section {
                    if checkRows.isEmpty {
                        Text("Every name matched an exercise.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(checkRows) { row in rowButton(row) }
                } footer: {
                    Text("Tap a name to choose another exercise or make a custom one. Choices are remembered for your next import.")
                }
            } else {
                if !checkRows.isEmpty {
                    Section("Check") {
                        ForEach(checkRows) { row in rowButton(row) }
                    }
                }
                Section("Matched") {
                    ForEach(matchedRows) { row in rowButton(row) }
                }
            }
        }
        .disabled(model.isWriting)
        .importBottomBar { bottomBar }
        .navigationTitle("Match Exercises")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.isWriting)
        .sheet(item: $editing) { row in
            ImportMatchSheet(model: model, row: row)
        }
    }

    private func rowButton(_ row: ImportFlowModel.MatchRow) -> some View {
        Button {
            editing = row
        } label: {
            ImportMatchRowView(row: row)
                .listRowButtonLabel()
                .contentShape(Rectangle())
        }
        .accessibilityHint("Choose another exercise or make a custom one.")
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 8) {
            if case .writing(let progress) = model.activity {
                ProgressView(value: progress.fraction) {
                    Text("Importing…")
                } currentValueLabel: {
                    Text("\(progress.saved.formatted()) of \(inflectedString("^[\(progress.total) workout](inflect: true)")) saved")
                }
                Button("Stop Import", role: .destructive) { model.stopImport() }
                    .frame(maxWidth: .infinity, minHeight: 44)
                Text("Workouts saved so far stay. Importing the file again adds the rest.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                let count = model.plan?.insertCount ?? 0
                Button(count > 0
                       ? inflectedString("Import ^[\(count) Workout](inflect: true)")
                       : String(localized: "Nothing New to Import")) {
                    model.startImport()
                }
                .buttonStyle(AccentFillButtonStyle())
                .disabled(count == 0)
                if let plan = model.plan, plan.alreadyImported + plan.repeatedInFile > 0 {
                    Text("\(inflectedString("^[\(plan.alreadyImported + plan.repeatedInFile) workout](inflect: true)")) already in Wholeset will be skipped.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
}

/// "Cable Crossover → Cable Fly · similar name   Check".
private struct ImportMatchRowView: View {
    let row: ImportFlowModel.MatchRow

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.importedName)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            marker
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    @ViewBuilder
    private var marker: some View {
        if row.needsLook, case .check = row.found {
            Text("Check")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
        } else if row.choice != nil || !row.found.needsLook {
            Image(systemName: "checkmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
        }
    }

    /// "→ Cable Fly · similar name".
    private var detail: String {
        switch row.choice {
        case .exercise(let candidate)?:
            return "→ \(candidate.name) · \(String(localized: "your choice"))"
        case .newCustom(let name, _)?:
            return name == row.importedName
                ? "→ \(String(localized: "new custom exercise"))"
                : "→ \(String(localized: "new custom exercise “\(name)”"))"
        case nil:
            switch row.found {
            case .matched(let candidate, _), .check(let candidate, _):
                let reason = row.found.reason(importedName: row.importedName).map { " · \($0)" } ?? ""
                return "→ \(candidate.name)\(reason)"
            case .newCustom:
                return "→ \(String(localized: "new custom exercise"))"
            }
        }
    }

    private var spoken: String {
        var parts = [row.importedName, detail.replacingOccurrences(of: "→ ", with: String(localized: "becomes "))]
        if row.needsLook, case .check = row.found { parts.append(String(localized: "needs a check")) }
        return parts.joined(separator: ", ")
    }
}

/// Rematching one imported name: keep the suggestion, choose another exercise, or make a
/// custom exercise (created when the import runs).
private struct ImportMatchSheet: View {
    let model: ImportFlowModel
    let row: ImportFlowModel.MatchRow

    @State private var name: String
    @State private var equipment: Equipment
    @State private var isPicking = false
    @Query private var exercises: [Exercise]
    @Environment(\.dismiss) private var dismiss

    init(model: ImportFlowModel, row: ImportFlowModel.MatchRow) {
        self.model = model
        self.row = row
        if case let .newCustom(name, equipment)? = row.choice {
            _name = State(initialValue: name)
            _equipment = State(initialValue: equipment)
        } else {
            _name = State(initialValue: row.importedName)
            _equipment = State(initialValue: ExerciseMatcher.guessedEquipment(for: row.importedName))
        }
    }

    private var nameProblem: ExerciseCatalog.NameProblem? {
        if case .failure(let problem) = ExerciseCatalog.validateNewName(name, existing: exercises) { return problem }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("In the File", value: row.importedName)
                    LabeledContent("Sets", value: row.setCount.formatted())
                }
                Section {
                    if let suggested = row.found.candidate {
                        Button {
                            if row.found.needsLook {
                                model.choose(suggested, for: row.importedName)
                            } else {
                                model.resetChoice(for: row.importedName)
                            }
                            dismiss()
                        } label: {
                            Label("Use \(suggested.name)", systemImage: "checkmark.circle")
                        }
                    }
                    Button {
                        isPicking = true
                    } label: {
                        Label("Choose Another Exercise…", systemImage: "list.bullet")
                    }
                } footer: {
                    Text("Wholeset remembers the name, so your next import matches it at once.")
                }
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    Picker("Equipment", selection: $equipment) {
                        ForEach(Equipment.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Button("Use a New Custom Exercise") {
                        model.chooseCustom(name: name.trimmingCharacters(in: .whitespacesAndNewlines), equipment: equipment, for: row.importedName)
                        dismiss()
                    }
                    .disabled(nameProblem != nil)
                } header: {
                    Text("Or Create a Custom Exercise")
                } footer: {
                    switch nameProblem {
                    case .duplicate(let existing, _)?:
                        Text("“\(existing)” already exists. Choose it with Choose Another Exercise.")
                    case .empty?:
                        Text("Enter a name.")
                    case nil:
                        Text("It's created when the import runs.")
                    }
                }
            }
            .navigationTitle("Match Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $isPicking) {
                ExercisePickerView(title: "Choose Exercise", limit: 1, excluded: []) { picked in
                    guard let exercise = picked.first else { return }
                    model.choose(ExerciseCandidate(exercise), for: row.importedName)
                    dismiss()
                }
            }
        }
    }
}
