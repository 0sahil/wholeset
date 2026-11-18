// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import WholesetKit

/// The most reps an exercise was done for at each weight, heaviest first. Each row opens
/// the session the record was set in.
struct RepsByWeightView: View {
    let exercise: Exercise

    @Environment(HistoryModel.self) private var history
    @Environment(\.weightUnit) private var unit

    var body: some View {
        let rows = history.records(forExercise: exercise.id)?.repsByWeight ?? []
        Group {
            if rows.isEmpty && !history.isLoaded {
                List { HistoryLoadingRow() }
            } else if rows.isEmpty {
                ContentUnavailableView("No Weighted Sets Yet", systemImage: "scalemass")
            } else {
                List(rows) { row in
                    NavigationLink(value: AppDestination.session(row.record.sessionID)) {
                        LabeledContent {
                            Text(HistoryFormat.repsText(row.reps))
                                .monospacedDigit()
                        } label: {
                            Text(HistoryFormat.weight(row.weightKg, unit: unit))
                                .monospacedDigit()
                            Text(HistoryFormat.shortDate(row.record.date))
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(HistoryFormat.spokenWeight(row.weightKg, unit: unit))
                        .accessibilityValue("\(HistoryFormat.repsText(row.reps)), \(HistoryFormat.shortDate(row.record.date))")
                    }
                }
            }
        }
        .navigationTitle("Most Reps by Weight")
        .navigationBarTitleDisplayMode(.inline)
        .navigationSubtitle(exercise.name)
    }
}
