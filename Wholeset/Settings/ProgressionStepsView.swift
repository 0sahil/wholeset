// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import SwiftUI
import WholesetKit

/// Settings → Progression Steps: how much weight the Watch's ↑ suggestion adds, per
/// equipment type, in the display unit. Bodyweight adds a rep instead.
struct ProgressionStepsView: View {
    @Bindable var settings: AppSettings

    @Environment(\.modelContext) private var modelContext

    /// The equipment types with a weight step, in display order.
    static let equipment: [Equipment] = [.barbell, .dumbbell, .machine, .cable, .other]

    var body: some View {
        Form {
            Section {
                ForEach(Self.equipment, id: \.self) { equipment in
                    Picker(equipment.label, selection: selection(for: equipment)) {
                        ForEach(options(for: equipment), id: \.self) { kilograms in
                            StepOptionLabel(kilograms: kilograms, unit: settings.unit, isDefault: isBuiltIn(kilograms, for: equipment))
                                .tag(kilograms)
                        }
                    }
                }
                LabeledContent(Equipment.bodyweight.label, value: String(localized: "+1 rep"))
                    .accessibilityHint("Not adjustable.")
            } footer: {
                Text("When every working set last time reached the top of its rep range, the ↑ suggestion on Apple Watch adds this much and goes back to the bottom of the range. Bodyweight exercises suggest one more rep instead. An exercise can set its own step in its details.")
            }
        }
        .navigationTitle("Progression Steps")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var progression: ProgressionSettings { ProgressionSettings(settings) }

    private func current(for equipment: Equipment) -> Double {
        progression.defaultStep(for: equipment) ?? 0
    }

    private func options(for equipment: Equipment) -> [Double] {
        ProgressionStepChoices.options(for: settings.unit, including: current(for: equipment))
    }

    private func isBuiltIn(_ kilograms: Double, for equipment: Equipment) -> Bool {
        ProgressionStep.builtInDefault(for: equipment, unit: settings.unit).map { ProgressionStep.isSame($0, kilograms) } ?? false
    }

    /// Writes through `SettingsEditing` and saves; choosing the default clears the override.
    private func selection(for equipment: Equipment) -> Binding<Double> {
        Binding(
            get: { ProgressionStepChoices.tag(for: current(for: equipment), unit: settings.unit) },
            set: { kilograms in
                SettingsEditing.setProgressionStep(kilograms: kilograms, for: equipment, on: settings, now: .now)
                modelContext.saveLogged()
            }
        )
    }
}

/// "2.5 kg", with "(Default)" for the built-in step.
struct StepOptionLabel: View {
    let kilograms: Double
    let unit: WeightUnit
    let isDefault: Bool

    var body: some View {
        let text = StepFormat.string(kilograms: kilograms, unit: unit)
        Text(isDefault ? String(localized: "\(text) (Default)") : text)
            .accessibilityLabel(isDefault
                ? String(localized: "\(StepFormat.spoken(kilograms: kilograms, unit: unit)), default")
                : StepFormat.spoken(kilograms: kilograms, unit: unit))
    }
}

/// Formats progression steps, which can be finer than the Crown's input step.
enum StepFormat {
    /// "2.5 kg", "1.25 kg", "5 lb".
    static func string(kilograms: Double, unit: WeightUnit) -> String {
        let value = unit.value(fromKilograms: kilograms)
        return "\(value.formatted(.number.precision(.fractionLength(0...2)))) \(unit.symbol)"
    }

    /// "2.5 kilograms", for VoiceOver.
    static func spoken(kilograms: Double, unit: WeightUnit) -> String {
        Measurement(value: unit.value(fromKilograms: kilograms), unit: unit == .kg ? UnitMass.kilograms : .pounds)
            .formatted(.measurement(width: .wide, numberFormatStyle: .number.precision(.fractionLength(0...2))))
    }
}
