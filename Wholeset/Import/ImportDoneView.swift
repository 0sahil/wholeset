// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import SwiftUI
import WholesetKit

/// The end of an import: what was added and what was not, and routines to make from the
/// most repeated workouts. Done creates the routines switched on and closes the flow.
struct ImportDoneView: View {
    @Bindable var model: ImportFlowModel
    let close: () -> Void
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if let summary = model.summary {
            List {
                Section {
                } header: {
                    ImportListHeader {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(inflectedString("Imported ^[\(summary.importedWorkouts) Workout](inflect: true)"))
                                .font(.title2.bold())
                                .foregroundStyle(.primary)
                            if summary.wasCancelled {
                                Text("Stopped after \(summary.importedWorkouts.formatted()) of \(summary.plannedWorkouts.formatted()). Import the file again to add the rest.")
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Section {
                    LabeledContent("Skipped, Already in Wholeset", value: summary.alreadyImported.formatted())
                    if summary.repeatedInFile > 0 {
                        LabeledContent("Skipped, Repeated in the File", value: summary.repeatedInFile.formatted())
                    }
                    if summary.rowsNotReadCount > 0 {
                        NavigationLink(value: ImportFlowModel.Step.rowsNotRead) {
                            LabeledContent {
                                Text(summary.rowsNotReadCount.formatted())
                            } label: {
                                Text("Rows Not Read")
                                if let largest = summary.rowsNotRead.first {
                                    Text(largest.reason.label)
                                }
                            }
                        }
                    } else {
                        LabeledContent("Rows Not Read", value: 0.formatted())
                    }
                    if summary.emptyWorkouts > 0 {
                        LabeledContent("Workouts Without Sets", value: summary.emptyWorkouts.formatted())
                    }
                    LabeledContent("New Exercises", value: summary.newExercises.count.formatted())
                    if summary.aliasesAdded > 0 {
                        LabeledContent("Names Remembered", value: summary.aliasesAdded.formatted())
                    }
                } footer: {
                    Text("Importing the same file again later only adds workouts that aren't here yet.")
                }
                if !model.suggestions.isEmpty {
                    Section {
                        ForEach($model.suggestions) { $choice in
                            Toggle(isOn: $choice.isOn) {
                                Text(choice.suggestion.name)
                                Text(inflectedString("done ^[\(choice.suggestion.timesDone) time](inflect: true) · from your latest one"))
                            }
                        }
                    } header: {
                        Text("Make Routines from Your History?")
                    } footer: {
                        Text("Each routine copies your latest workout with that name: its exercises, sets and rep ranges. Done creates the ones switched on.")
                    }
                }
            }
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.createRoutines(in: modelContext)
                        close()
                    }
                }
            }
        }
    }
}

/// Every row the import did not read, by reason, with its line number and text.
struct ImportRowsNotReadView: View {
    let groups: [(reason: SkipReason, rows: [SkippedRow])]

    var body: some View {
        List {
            ForEach(groups, id: \.reason) { group in
                Section {
                    ForEach(group.rows) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Line \(row.line.formatted())")
                                .font(.subheadline.weight(.semibold))
                            Text(verbatim: row.text)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("\(group.reason.label) (\(group.rows.count.formatted()))")
                } footer: {
                    Text(group.reason.explanation)
                }
            }
        }
        .navigationTitle("Rows Not Read")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView("Every Row Was Read", systemImage: "checkmark.circle")
            }
        }
    }
}
