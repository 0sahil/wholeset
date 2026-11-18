// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import SwiftUI
import UIKit
import WholesetKit

/// The Settings tab: units, default rest, progression steps, the Watch's Crown speed, and
/// the status of Apple Health and iCloud sync.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    /// Oldest first: the row that survives when sync duplicates are merged, so this screen
    /// never holds a row that a merge deletes.
    @Query(sort: \AppSettings.createdAt) private var rows: [AppSettings]

    var body: some View {
        @Bindable var navigation = navigation
        NavigationStack(path: $navigation.settingsPath) {
            Group {
                if let settings = rows.first {
                    SettingsForm(settings: settings, health: model.health, sync: model.store.sync)
                } else {
                    ProgressView()
                        .task { _ = try? AppSettings.current(in: modelContext) }
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .progressionSteps:
                    if let settings = rows.first {
                        ProgressionStepsView(settings: settings)
                    }
                }
            }
        }
    }
}

private struct SettingsForm: View {
    @Bindable var settings: AppSettings
    let health: HealthPermission
    let sync: SyncMonitor

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Form {
            Section {
                LabeledContent("Units") {
                    Picker("Units", selection: binding(\.unit) { SettingsEditing.setUnit($0, on: $1, now: $2) }) {
                        Text(verbatim: WeightUnit.kg.symbol).tag(WeightUnit.kg)
                        Text(verbatim: WeightUnit.lb.symbol).tag(WeightUnit.lb)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("Weight unit")
                }
                RestPicker(String(localized: "Default Rest"), seconds: binding(\.defaultRestSeconds, SettingsEditing.setDefaultRest))
                NavigationLink(value: SettingsDestination.progressionSteps) {
                    LabeledContent("Progression Steps", value: String(localized: "By Equipment"))
                }
            } footer: {
                Text("Weights are always stored in kilograms; the unit only changes how they're shown and entered. Default rest applies when neither the routine nor the exercise sets one.")
            }

            Section {
                Picker("Weight", selection: binding(\.weightCrownSensitivity, SettingsEditing.setWeightCrownSensitivity)) {
                    ForEach(CrownSensitivity.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Reps", selection: binding(\.repsCrownSensitivity, SettingsEditing.setRepsCrownSensitivity)) {
                    ForEach(CrownSensitivity.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Digital Crown Speed")
            } footer: {
                Text("How fast turning the Crown changes weight and reps on Apple Watch.")
            }

            Section("Status") {
                HealthStatusRow(health: health)
                NavigationLink {
                    SyncStatusView(sync: sync)
                } label: {
                    LabeledContent("iCloud Sync", value: SyncStatusText.summary(sync.status))
                }
            }

            Section("About") {
                LabeledContent("Version", value: Self.version)
                LabeledContent("License", value: "GPL-3.0")
            }
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }

    /// A binding that writes through a `SettingsEditing` function and saves.
    private func binding<Value>(
        _ keyPath: KeyPath<AppSettings, Value>,
        _ write: @escaping (Value, AppSettings, Date) -> Void
    ) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                write(value, settings, .now)
                modelContext.saveLogged()
            }
        )
    }
}

/// Apple Health permission, worded for what iOS actually reveals.
private struct HealthStatusRow: View {
    let health: HealthPermission
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Apple Health", value: value)
            Text(explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
            switch health.status {
            case .notDetermined:
                Button("Connect to Apple Health") {
                    Task { await health.request() }
                }
            case .allowed, .denied:
                Button("Open the Health App") {
                    if let url = URL(string: "x-apple-health://") {
                        openURL(url) { accepted in
                            if !accepted, let settings = URL(string: UIApplication.openSettingsURLString) {
                                openURL(settings)
                            }
                        }
                    }
                }
            case .unavailable:
                EmptyView()
            }
        }
        .padding(.vertical, 2)
    }

    private var value: String {
        switch health.status {
        case .unavailable: String(localized: "Not available")
        case .notDetermined: String(localized: "Not connected")
        case .allowed: String(localized: "Can save workouts")
        case .denied: String(localized: "Can't save workouts")
        }
    }

    private var explanation: String {
        switch health.status {
        case .unavailable:
            String(localized: "Apple Health isn't available on this device.")
        case .notDetermined:
            String(localized: "Wholeset hasn't asked for access yet. Logging works without it; workouts just won't appear in Fitness.")
        case .allowed, .denied:
            String(localized: "iOS only tells apps whether they may save workouts, never whether they may read data such as heart rate. Change access in the Health app under your profile, Apps, Wholeset.")
        }
    }
}
