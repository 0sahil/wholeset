// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import WholesetKit

/// The History tab: every finished workout, newest first, grouped by month, searchable by
/// routine or exercise name.
struct HistoryView: View {
    @Environment(HistoryModel.self) private var history
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        NavigationStack(path: $navigation.historyPath) {
            content
                .navigationTitle("History")
                .searchable(text: $navigation.historySearch, prompt: Text("Routine or exercise"))
                .appDestinations()
        }
    }

    /// Always a list, so the large title and search field are there from the first frame,
    /// with a loading row until the first index arrives.
    private var content: some View {
        let months = history.sections(matching: navigation.historySearch)
        return List {
            if !history.isLoaded {
                HistoryLoadingRow()
            }
            ForEach(months) { month in
                Section(HistoryFormat.month(month.start)) {
                    ForEach(month.rows) { row in
                        NavigationLink(value: AppDestination.session(row.id)) {
                            HistoryRowView(row: row)
                        }
                    }
                }
            }
        }
        .overlay {
            if history.isLoaded && history.index.rows.isEmpty {
                ContentUnavailableView {
                    Label("No Workouts Yet", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Workouts you finish on Apple Watch appear here, with every set, record and note.")
                }
            } else if history.isLoaded && months.isEmpty {
                ContentUnavailableView.search(text: navigation.historySearch)
            }
        }
    }
}

/// A light "Loading…" row, shown in a list while the history index is first built.
struct HistoryLoadingRow: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Loading History…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .combine)
    }
}

/// A workout in the History list: name with its PRs, day, duration and sets, and volume.
private struct HistoryRowView: View {
    let row: HistoryRow
    @Environment(\.weightUnit) private var unit

    var body: some View {
        LabeledContent {
            if row.volumeKg > 0 {
                Text(HistoryFormat.volume(row.volumeKg, unit: unit))
                    .monospacedDigit()
            }
        } label: {
            title
            Text(detail)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    /// "Push Day · 2 PRs" with the PRs in the accent colour, or "Pull Day · imported".
    private var title: Text {
        var text = Text(HistoryFormat.sessionName(row.name))
        if row.prCount > 0 {
            let badge = Text(verbatim: " · \(HistoryFormat.prCount(row.prCount))")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tint)
            text = Text("\(text)\(badge)")
        }
        if row.isImported {
            let imported = Text(" · \(String(localized: "imported"))")
                .font(.footnote)
                .foregroundStyle(.secondary)
            text = Text("\(text)\(imported)")
        }
        return text
    }

    /// "Thu 12 · 61 min · 15 sets".
    private var detail: String {
        var parts = [HistoryFormat.dayOfMonth(row.startedAt)]
        if let duration = row.duration { parts.append(HistoryFormat.duration(duration)) }
        parts.append(HistoryFormat.setCount(row.workingSets))
        return parts.joined(separator: " · ")
    }

    private var spokenLabel: String {
        var parts = [HistoryFormat.sessionName(row.name), HistoryFormat.fullDate(row.startedAt)]
        if let duration = row.duration { parts.append(HistoryFormat.spokenDuration(duration)) }
        parts.append(HistoryFormat.setCount(row.workingSets))
        if row.volumeKg > 0 {
            parts.append(String(localized: "Volume \(HistoryFormat.spokenVolume(row.volumeKg, unit: unit))"))
        }
        if row.prCount > 0 { parts.append(HistoryFormat.prCount(row.prCount)) }
        if row.isImported { parts.append(String(localized: "Imported")) }
        return parts.joined(separator: ", ")
    }
}
