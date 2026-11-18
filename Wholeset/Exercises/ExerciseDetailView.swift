// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import SwiftUI
import WholesetKit

/// An exercise's progress: a chart of estimated 1RM, top set or volume per session, its
/// records, and the full log of every session with it. The ⋯ button opens its settings.
struct ExerciseDetailView: View {
    let exercise: Exercise

    @Environment(HistoryModel.self) private var history

    var body: some View {
        let timeline = history.timeline(forExercise: exercise.id)
        Group {
            if let timeline {
                ExerciseProgressList(
                    exercise: exercise,
                    timeline: timeline,
                    records: history.records(forExercise: exercise.id)
                )
            } else if history.isLoaded {
                ContentUnavailableView {
                    Label("No History Yet", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("Log \(exercise.name) on Apple Watch and its records and progress appear here.")
                }
            } else {
                List { HistoryLoadingRow() }
            }
        }
        .navigationTitle(exercise.name)
        .navigationSubtitle(subtitle(sessions: timeline?.sessionCount ?? 0))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: AppDestination.exerciseSettings(exercise.id)) {
                    Label("Exercise Settings", systemImage: "ellipsis")
                }
            }
        }
    }

    /// "Barbell · Chest · 46 sessions".
    private func subtitle(sessions: Int) -> String {
        guard sessions > 0 else { return exercise.detailLine }
        return "\(exercise.detailLine) · \(inflectedString("^[\(sessions) session](inflect: true)"))"
    }
}

/// The chart, records and log of an exercise that has history.
private struct ExerciseProgressList: View {
    let exercise: Exercise
    let timeline: ExerciseTimeline
    let records: ExerciseRecords?

    @Environment(AppNavigation.self) private var navigation
    @Environment(\.weightUnit) private var unit
    @Environment(\.calendar) private var calendar
    @State private var metric: ProgressMetric = .estimatedOneRepMax
    @State private var range: ProgressRange = .oneYear

    var body: some View {
        List {
            Section {
                Picker("Chart", selection: $metric) {
                    ForEach(ProgressMetric.allCases, id: \.self) { metric in
                        Text(MetricFormat.shortName(metric)).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                ProgressCard(timeline: timeline, metric: metric, range: $range, unit: unit, calendar: calendar) { sessionID in
                    navigation.push(.session(sessionID))
                }
            }
            if let records {
                RecordsSection(exerciseID: exercise.id, records: records, unit: unit)
            }
            Section("Log") {
                ForEach(timeline.log) { item in
                    NavigationLink(value: AppDestination.session(item.sessionID)) {
                        LogRow(item: item, unit: unit)
                    }
                }
            }
        }
        .onAppear(perform: revealDemoMetric)
    }

    private func revealDemoMetric() {
        #if DEBUG
        if case .exerciseMetric(let shown) = navigation.demoReveal {
            navigation.demoReveal = nil
            metric = shown
        }
        #endif
    }
}

/// Names and values of the chart's metrics.
enum MetricFormat {
    /// The segment title.
    static func shortName(_ metric: ProgressMetric) -> String {
        switch metric {
        case .estimatedOneRepMax: String(localized: "Est. 1RM")
        case .topSet: String(localized: "Top Set")
        case .volume: String(localized: "Volume")
        }
    }

    /// The full name, for VoiceOver and the chart's value axis.
    static func name(_ metric: ProgressMetric) -> String {
        switch metric {
        case .estimatedOneRepMax: String(localized: "Estimated one-rep max")
        case .topSet: String(localized: "Top set weight")
        case .volume: String(localized: "Session volume")
        }
    }

    /// The value in `unit` without the unit: "82.5", "62.5" or "1,950".
    static func number(_ kilograms: Double, metric: ProgressMetric, unit: WeightUnit) -> String {
        switch metric {
        case .estimatedOneRepMax: unit.value(fromKilograms: kilograms).formatted(.number.precision(.fractionLength(0...1)))
        case .topSet: WeightFormat.preciseString(kilograms: kilograms, unit: unit)
        case .volume: WeightFormat.volume(kilograms: kilograms, unit: unit)
        }
    }

    /// The value in `unit` for charting.
    static func chartValue(_ kilograms: Double, metric: ProgressMetric, unit: WeightUnit) -> Double {
        unit.value(fromKilograms: kilograms)
    }

    /// "82.5 kilograms", for VoiceOver.
    static func spoken(_ kilograms: Double, metric: ProgressMetric, unit: WeightUnit) -> String {
        metric == .volume ? HistoryFormat.spokenVolume(kilograms, unit: unit) : HistoryFormat.spokenWeight(kilograms, unit: unit)
    }
}

/// The latest value, the range picker and the chart.
private struct ProgressCard: View {
    let timeline: ExerciseTimeline
    let metric: ProgressMetric
    @Binding var range: ProgressRange
    let unit: WeightUnit
    let calendar: Calendar
    let onSelect: (UUID) -> Void

    var body: some View {
        let points = chartPoints
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    latestValue
                    Spacer(minLength: 12)
                    rangePicker
                }
                VStack(alignment: .leading, spacing: 8) {
                    latestValue
                    rangePicker
                }
            }
            if points.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .multilineTextAlignment(.center)
            } else {
                ExerciseProgressChart(
                    points: points,
                    includesZero: metric == .volume,
                    valueName: MetricFormat.name(metric),
                    onSelect: onSelect
                )
            }
        }
        .padding(.vertical, 4)
    }

    private var chartPoints: [ProgressChartPoint] {
        timeline.points(in: range, now: .now, calendar: calendar).compactMap { point in
            guard let value = point.value(for: metric) else { return nil }
            return ProgressChartPoint(
                id: point.sessionID,
                date: point.date,
                value: MetricFormat.chartValue(value, metric: metric, unit: unit),
                spokenValue: MetricFormat.spoken(value, metric: metric, unit: unit)
            )
        }
    }

    @ViewBuilder
    private var latestValue: some View {
        if let latest = timeline.latest(metric) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(MetricFormat.number(latest.valueKg, metric: metric, unit: unit))
                        .font(.title.weight(.bold))
                        .monospacedDigit()
                    Text(unit.symbol)
                        .foregroundStyle(.secondary)
                }
                Text("Latest · \(HistoryFormat.shortDate(latest.point.date))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Latest \(MetricFormat.name(metric))"))
            .accessibilityValue("\(MetricFormat.spoken(latest.valueKg, metric: metric, unit: unit)), \(HistoryFormat.shortDate(latest.point.date))")
        } else {
            Text("—")
                .font(.title.weight(.bold))
                .accessibilityLabel(String(localized: "No \(MetricFormat.name(metric)) yet"))
        }
    }

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            Text("3M").tag(ProgressRange.threeMonths)
                .accessibilityLabel("3 months")
            Text("1Y").tag(ProgressRange.oneYear)
                .accessibilityLabel("1 year")
            Text("All").tag(ProgressRange.all)
                .accessibilityLabel("All time")
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }

    private var emptyMessage: String {
        if timeline.latest(metric) == nil {
            return switch metric {
            case .estimatedOneRepMax: String(localized: "No weighted sets of 12 reps or fewer yet.")
            case .topSet, .volume: String(localized: "No weighted sets yet.")
            }
        }
        return switch range {
        case .threeMonths: String(localized: "No sessions in the last 3 months.")
        case .oneYear: String(localized: "No sessions in the last year.")
        case .all: String(localized: "No sessions yet.")
        }
    }
}

/// Heaviest weight, best estimate, best volume, most reps, and the reps-by-weight list.
/// Each record opens the session it was set in.
private struct RecordsSection: View {
    let exerciseID: UUID
    let records: ExerciseRecords
    let unit: WeightUnit

    var body: some View {
        Section("Records") {
            if let heaviest = records.heaviest {
                row(
                    String(localized: "Heaviest Weight"),
                    date: heaviest.date,
                    value: HistoryFormat.set(weightKg: heaviest.weightKg, reps: heaviest.reps, unit: unit),
                    spoken: HistoryFormat.spokenSet(weightKg: heaviest.weightKg, reps: heaviest.reps, unit: unit),
                    session: heaviest.sessionID
                )
            }
            if let best = records.bestOneRepMax {
                row(
                    String(localized: "Best Est. 1RM"),
                    date: best.set.date,
                    value: "\(MetricFormat.number(best.estimateKg, metric: .estimatedOneRepMax, unit: unit)) \(unit.symbol)",
                    spoken: HistoryFormat.spokenWeight(best.estimateKg, unit: unit),
                    session: best.set.sessionID
                )
            }
            if let volume = records.bestSessionVolume {
                row(
                    String(localized: "Best Session Volume"),
                    date: volume.date,
                    value: HistoryFormat.volume(volume.volumeKg, unit: unit),
                    spoken: HistoryFormat.spokenVolume(volume.volumeKg, unit: unit),
                    session: volume.sessionID
                )
            }
            if let most = records.mostReps {
                row(
                    String(localized: "Most Reps Without Weight"),
                    date: most.date,
                    value: HistoryFormat.repsText(most.reps),
                    spoken: HistoryFormat.repsText(most.reps),
                    session: most.sessionID
                )
            }
            if !records.repsByWeight.isEmpty {
                NavigationLink("Most Reps by Weight", value: AppDestination.repsByWeight(exerciseID))
            }
        }
    }

    private func row(_ title: String, date: Date, value: String, spoken: String, session: UUID) -> some View {
        NavigationLink(value: AppDestination.session(session)) {
            LabeledContent {
                Text(value)
                    .monospacedDigit()
            } label: {
                Text(title)
                Text(HistoryFormat.shortDate(date))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue("\(spoken), \(HistoryFormat.shortDate(date))")
        }
    }
}

/// A session in the full log: date, session name, and the working sets.
private struct LogRow: View {
    let item: ExerciseLogItem
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(HistoryFormat.fullDate(item.date))
            Text(sessionLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(summary)
                .font(.subheadline)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    /// "Push Day" or "Pull Day · imported".
    private var sessionLine: String {
        let name = HistoryFormat.sessionName(item.sessionName)
        return item.isImported ? "\(name) · \(String(localized: "imported"))" : name
    }

    /// "62.5 kg × 10, 9, 8 · 65 kg × 5", or "12, 10 reps" without weight.
    private var summary: String {
        let groups = SetGroup.groups(item.sets)
        guard !groups.isEmpty else { return String(localized: "Warm-up sets only") }
        return groups.map { group in
            let reps = group.reps.map { $0.map(String.init) ?? "–" }.joined(separator: ", ")
            guard let weight = group.weightKg else { return String(localized: "\(reps) reps") }
            return "\(HistoryFormat.weight(weight, unit: unit)) × \(reps)"
        }
        .joined(separator: " · ")
    }
}
