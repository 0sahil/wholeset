// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import WholesetKit

/// The import flow, shown as a sheet: choose a file, check how it was read, match its
/// exercises, import, then optionally make routines. Settings, the empty Plan screen and
/// opening a CSV in Wholeset all start here.
struct ImportFlowView: View {
    @Bindable var model: ImportFlowModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack(path: $model.path) {
            Group {
                if model.summary != nil {
                    ImportDoneView(model: model) { dismiss() }
                } else {
                    ImportStartView(model: model) { dismiss() }
                }
            }
            .navigationDestination(for: ImportFlowModel.Step.self) { step in
                switch step {
                case .howTo(let format): ImportHowToView(format: format, model: model)
                case .columns: ImportColumnsView(model: model)
                case .detected: ImportDetectedView(model: model)
                case .match: ImportMatchView(model: model)
                case .rowsNotRead: ImportRowsNotReadView(groups: model.result?.skippedByReason.map { ($0.reason, $0.rows) } ?? [])
                }
            }
        }
        .fileImporter(isPresented: $model.isPickingFile, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]) { result in
            if case .success(let url) = result {
                model.open(url)
            }
        }
        .interactiveDismissDisabled(model.isWriting || model.summary != nil)
        .alert(
            model.problem?.title ?? "",
            isPresented: Binding(get: { model.problem != nil }, set: { if !$0 { model.problem = nil } }),
            presenting: model.problem
        ) { _ in
            Button("OK") {
                model.problem = nil
                // Back to where the file can be fixed: the columns of another app's file, else the start.
                if model.summary == nil {
                    model.path = model.format == .generic ? [.columns] : []
                }
            }
        } message: { problem in
            Text(problem.message)
        }
    }
}

extension ImportFlowModel.Problem {
    var title: String {
        switch self {
        case .couldNotOpen: String(localized: "Couldn't Open the File")
        case .tooLarge: String(localized: "File Too Large")
        case .notText: String(localized: "Not a CSV File")
        case .empty: String(localized: "Empty File")
        case .noWorkouts: String(localized: "No Workouts Found")
        case .unreadableDates: String(localized: "Dates Not Readable")
        case .writeFailed: String(localized: "Import Stopped")
        }
    }

    var message: String {
        switch self {
        case .couldNotOpen:
            String(localized: "Wholeset couldn't read this file. Save it to Files first, then choose it here.")
        case .tooLarge:
            String(localized: "This file is over 50 MB, far more than a workout export. Check that it's the right file.")
        case .notText:
            String(localized: "This file isn't text. Choose the CSV file your app exported.")
        case .empty:
            String(localized: "This file has no rows.")
        case .noWorkouts(let rows):
            String(localized: "No row could be read as a set (\(inflectedString("^[\(rows) row](inflect: true)")) not read). Check that this is a workout export, or match the columns again.")
        case .unreadableDates(let sample):
            String(localized: "Wholeset couldn't read dates like “\(sample)” in this file.")
        case .writeFailed:
            String(localized: "Something went wrong while saving. Workouts saved before it stay; importing the file again adds the rest.")
        }
    }
}

// MARK: - I1 Choose file

/// The first screen: what import does, the file button and the apps it reads.
struct ImportStartView: View {
    let model: ImportFlowModel
    let cancel: () -> Void

    var body: some View {
        List {
            Section {
                Button("Choose File") { model.isPickingFile = true }
                    .buttonStyle(AccentFillButtonStyle())
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } header: {
                ImportListHeader {
                    Text("Bring your workout history from another app. Export a CSV file there, then choose it here.")
                }
            }
            Section {
                ForEach(ImportFormat.allCases) { format in
                    NavigationLink(value: ImportFlowModel.Step.howTo(format)) {
                        ImportAppRow(format: format)
                    }
                }
            } header: {
                Text("Reads Exports From")
            } footer: {
                Text("Imported workouts aren't added to Apple Health, since they're likely there already.")
            }
        }
        .navigationTitle("Import")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: cancel)
            }
        }
        .overlay {
            if model.activity == .reading || model.activity == .parsing {
                ImportBusyView(title: String(localized: "Reading File…"))
            }
        }
    }
}

/// An app in the list of supported exports, with a beta tag where it applies.
private struct ImportAppRow: View {
    let format: ImportFormat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(format.listName)
                if format.isBeta { BetaTag() }
            }
            if format == .generic {
                Text("Any CSV: you match the columns")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows how to export from this app.")
    }
}

/// A small "Beta" capsule.
struct BetaTag: View {
    var body: some View {
        Text("Beta")
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.secondary)
            .background(.fill.tertiary, in: Capsule())
            .accessibilityLabel("beta")
    }
}

/// The text at the top of an import screen, aligned with the edge of the cards below.
///
/// Use it as a section header, not a row: inset-grouped rows clip their content to the
/// section's rounded corners, so text set close to a row's edge loses the corners of its
/// first letters (a "3" at the start of a line is cut in half). Headers are not clipped.
struct ImportListHeader<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(.body)
            .foregroundStyle(.secondary)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 8, trailing: 4))
    }
}

extension View {
    /// Pins an import screen's action button below its list. The list scrolls under the
    /// bar, behind a hard scroll edge effect, and its last row and footer can scroll fully
    /// above the button.
    func importBottomBar(@ViewBuilder _ content: () -> some View) -> some View {
        safeAreaBar(edge: .bottom) {
            content()
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
        }
        .scrollEdgeEffectStyle(.hard, for: .bottom)
    }
}

/// A centred progress indicator over a dimmed screen.
struct ImportBusyView: View {
    let title: String
    var value: Double?

    var body: some View {
        VStack(spacing: 12) {
            if let value {
                ProgressView(value: value)
                    .frame(maxWidth: 220)
            } else {
                ProgressView()
                    .controlSize(.large)
            }
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - How to export

/// How to export from one app, in Wholeset's own words.
struct ImportHowToView: View {
    let format: ImportFormat
    let model: ImportFlowModel

    var body: some View {
        List {
            Section {
                Text(steps)
            } header: {
                Text("How to Export")
            }
            Section {
                Text(details)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Choose File") { model.isPickingFile = true }
                    .buttonStyle(AccentFillButtonStyle())
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } footer: {
                Text("Rows with only a time or a distance, such as cardio or planks, aren't imported. The summary lists every row that wasn't.")
            }
        }
        .navigationTitle(format.listName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if format.isBeta {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Text(format.listName).font(.headline)
                        BetaTag()
                    }
                }
            }
        }
    }

    private var steps: String {
        switch format {
        case .strong:
            String(localized: "In Strong, open Settings and choose Export Strong Data (on Android, Export Data). Save the CSV file to Files, or share it straight to Wholeset.")
        case .hevy:
            String(localized: "In Hevy, go to your profile, open Settings, then Export & Import Data, and choose Export Workouts. You can also export from the Hevy website.")
        case .fitNotes:
            String(localized: "In FitNotes for Android, open Settings and choose the spreadsheet (CSV) export. The other export is a backup only FitNotes can read.")
        case .fitbod:
            String(localized: "In Fitbod, open the Log tab, tap the settings button and choose to export your workout data. The file is called WorkoutExport.csv.")
        case .strongLifts:
            String(localized: "In StrongLifts, open Settings and choose Export Data. Save the CSV file it makes.")
        case .liftosaur:
            String(localized: "In Liftosaur, open Me, then Import / Export, and choose to export your history to a CSV file.")
        case .generic:
            String(localized: "Export a CSV file from your app or spreadsheet with one row per set. It needs at least a date, an exercise name and the reps.")
        }
    }

    private var details: String {
        switch format {
        case .strong:
            String(localized: "Older Strong exports don't say whether weights are in kilograms or pounds; you choose after picking the file. Warm-up, drop and failure sets keep their type.")
        case .hevy:
            String(localized: "Dates in the file are written in the app's language. If the file can't tell the day from the month, Wholeset asks which comes first.")
        case .fitNotes:
            String(localized: "FitNotes saves no workout names or times, so each day becomes one workout named “Workout”.")
        case .fitbod:
            String(localized: "Fitbod saves every weight in kilograms. Weights you entered in pounds are turned back into the pounds you lifted.")
        case .strongLifts:
            String(localized: "Each row holds one exercise with all its sets. Sets you didn't do aren't imported.")
        case .liftosaur:
            String(localized: "Each workout is named after its day in the program, or the program when the day has no name.")
        case .generic:
            String(localized: "After you pick the file, you tell Wholeset what each column holds. Each date and workout name becomes one workout; dates without a time and no name column make one workout per day.")
        }
    }
}
