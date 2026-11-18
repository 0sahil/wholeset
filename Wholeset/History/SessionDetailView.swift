// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import SwiftUI
import WholesetKit

/// One finished workout: summary, notes, and every exercise with its logged sets, PRs and
/// rest times. Edit opens ``SessionEditView``; deleting the workout there pops this screen.
struct SessionDetailView: View {
    let sessionID: UUID

    @Environment(HistoryModel.self) private var history
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.weightUnit) private var unit
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var editor: EditorRequest?
    @State private var deletesOnDismiss = false

    /// An open editor, with the draft it started from.
    private struct EditorRequest: Identifiable {
        let id = UUID()
        let draft: SessionDraft
        let confirmsDeletion: Bool
    }

    var body: some View {
        let detail = history.detail(forSession: sessionID)
        Group {
            if let detail {
                SessionDetailList(detail: detail, unit: unit)
                    .navigationTitle(HistoryFormat.sessionName(detail.session.displayName))
                    .navigationSubtitle(subtitle(for: detail.session))
            } else if history.isLoaded {
                ContentUnavailableView("Workout Deleted", systemImage: "trash", description: Text("This workout is no longer in your history."))
            } else {
                List { HistoryLoadingRow() }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { openEditor() }
                    .disabled(detail == nil)
            }
        }
        .sheet(item: $editor, onDismiss: deleteIfConfirmed) { request in
            SessionEditView(draft: request.draft, confirmsDeletionInitially: request.confirmsDeletion) {
                deletesOnDismiss = true
            }
        }
        .task { revealDemoEditor() }
    }

    /// "Mon, 9 Nov 2026 · 18:04 – 19:02".
    private func subtitle(for session: HistorySession) -> String {
        "\(HistoryFormat.fullDate(session.startedAt)) · \(HistoryFormat.timeRange(from: session.startedAt, to: session.endedAt))"
    }

    private func openEditor(confirmsDeletion: Bool = false) {
        let id = sessionID
        guard let session = try? modelContext.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })).first else { return }
        editor = EditorRequest(draft: SessionDraft(session: session, unit: unit), confirmsDeletion: confirmsDeletion)
    }

    /// Deletes the workout once the editor that asked for it has closed, then pops back.
    private func deleteIfConfirmed() {
        guard deletesOnDismiss else { return }
        deletesOnDismiss = false
        do {
            try SessionEditing.deleteSession(id: sessionID, in: modelContext)
            modelContext.saveLogged()
        } catch {
            modelContext.rollback()
        }
        dismiss()
    }

    /// Opens the editor (and its delete confirmation) when the DEBUG demo harness asks.
    private func revealDemoEditor() {
        #if DEBUG
        switch navigation.demoReveal {
        case .sessionEdit:
            navigation.demoReveal = nil
            openEditor()
        case .sessionDeleteConfirmation:
            navigation.demoReveal = nil
            openEditor(confirmsDeletion: true)
        default:
            break
        }
        #endif
    }
}

/// The list part of the session screen.
private struct SessionDetailList: View {
    let detail: SessionDetail
    let unit: WeightUnit

    var body: some View {
        List {
            Section {
                SessionSummaryGrid(detail: detail, unit: unit)
            }
            if !detail.session.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("Notes") {
                    Text(detail.session.notes)
                }
            }
            ForEach(detail.sections) { section in
                Section {
                    if section.rows.isEmpty {
                        Text("No sets logged")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(section.rows) { row in
                        SetRowView(row: row, unit: unit)
                    }
                } header: {
                    ExerciseSectionHeader(section: section)
                } footer: {
                    if section.isVolumeRecord {
                        Text(HistoryFormat.recordName(.volume))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }
            }
        }
    }
}

/// Duration, volume, heart rate and active energy, two by two. Anything unknown shows a dash.
private struct SessionSummaryGrid: View {
    let detail: SessionDetail
    let unit: WeightUnit
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let items = self.items
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(items, id: \.label) { SummaryItemView(item: $0) }
            }
            .padding(.vertical, 4)
        } else {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    SummaryItemView(item: items[0])
                    SummaryItemView(item: items[1])
                }
                GridRow {
                    SummaryItemView(item: items[2])
                    SummaryItemView(item: items[3])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var items: [SummaryItem] {
        let session = detail.session
        let average = positive(session.averageHeartRate)
        let maximum = positive(session.maximumHeartRate)
        let heartRate: String = switch (average, maximum) {
        case (nil, nil): "—"
        case let (average, maximum): "\(average.map(bpm) ?? "—") / \(maximum.map(bpm) ?? "—")"
        }
        return [
            SummaryItem(
                value: detail.duration.map(HistoryFormat.duration) ?? "—",
                label: String(localized: "Duration"),
                spoken: detail.duration.map(HistoryFormat.spokenDuration)
            ),
            SummaryItem(
                value: detail.volumeKg > 0 ? HistoryFormat.volume(detail.volumeKg, unit: unit) : "—",
                label: String(localized: "Volume"),
                spoken: detail.volumeKg > 0 ? HistoryFormat.spokenVolume(detail.volumeKg, unit: unit) : nil
            ),
            SummaryItem(
                value: heartRate,
                label: String(localized: "Avg / max bpm"),
                spoken: average == nil && maximum == nil ? nil : String(
                    localized: "Average \(average.map(bpm) ?? String(localized: "unknown")), maximum \(maximum.map(bpm) ?? String(localized: "unknown")) beats per minute"
                )
            ),
            SummaryItem(
                value: positive(session.activeKilocalories).map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—",
                label: String(localized: "Active kcal"),
                spoken: positive(session.activeKilocalories).map {
                    String(localized: "\($0.formatted(.number.precision(.fractionLength(0)))) kilocalories")
                }
            ),
        ]
    }

    private func positive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private func bpm(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
}

private struct SummaryItem {
    let value: String
    let label: String
    /// What VoiceOver reads for the value; `nil` reads "Not available".
    let spoken: String?
}

private struct SummaryItemView: View {
    let item: SummaryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(item.label)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.label)
        .accessibilityValue(item.spoken ?? String(localized: "Not available"))
    }
}

/// The exercise's name (opening its history) and what happened to it in this workout.
private struct ExerciseSectionHeader: View {
    let section: SessionDetail.Section

    var body: some View {
        if let exerciseID = section.exerciseID {
            NavigationLink(value: AppDestination.exercise(exerciseID)) {
                label(showsChevron: true)
            }
            .accessibilityHint("Shows this exercise's records and history.")
        } else {
            label(showsChevron: false)
        }
    }

    private func label(showsChevron: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(HistoryFormat.exerciseName(section.exerciseName))
                .foregroundStyle(.primary)
            if let note {
                Text(verbatim: "· \(note)")
                    .foregroundStyle(.secondary)
            }
            if showsChevron {
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .font(.subheadline.weight(.semibold))
        .textCase(nil)
    }

    private var note: String? {
        switch section.note {
        case .added: String(localized: "added")
        case .swappedIn: String(localized: "swapped in")
        case .skipped: String(localized: "skipped")
        case nil: nil
        }
    }
}

/// One logged set: "W" or its number, weight × reps, PR badges and the rest before it.
private struct SetRowView: View {
    let row: SessionDetail.SetRow
    let unit: WeightUnit
    @ScaledMetric(relativeTo: .body) private var numberWidth: CGFloat = 24

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(row.number.map { "\($0)" } ?? String(localized: "W", comment: "Warm-up set marker"))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: numberWidth, alignment: .leading)
            Text(HistoryFormat.set(weightKg: row.weightKg, reps: row.reps, unit: unit))
                .foregroundStyle(row.isWarmup ? .secondary : .primary)
                .monospacedDigit()
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if !row.records.isEmpty {
                    Text(HistoryFormat.recordLabel(row.records))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tint)
                        .multilineTextAlignment(.trailing)
                }
                if let rest = row.restBefore {
                    Text(HistoryFormat.rest(rest))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    private var spokenLabel: String {
        var parts = [row.number.map { String(localized: "Set \($0)") } ?? String(localized: "Warm-up")]
        parts.append(HistoryFormat.spokenSet(weightKg: row.weightKg, reps: row.reps, unit: unit))
        if !row.records.isEmpty { parts.append(HistoryFormat.recordLabel(row.records)) }
        if let rest = row.restBefore { parts.append(HistoryFormat.spokenRest(rest)) }
        return parts.joined(separator: ", ")
    }
}
