// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import WholesetKit

/// A choice in a progression step picker.
enum StepChoice: Hashable {
    /// Follow the default step (per-exercise pickers only).
    case followDefault
    /// A step in kilograms.
    case step(Double)
    /// Type a step that none of the presets fit.
    case custom
}

/// Which progression step is being typed in a ``CustomStepSheet``.
struct CustomStepRequest: Identifiable {
    let id = UUID()
    /// The equipment whose default step is edited, or `nil` for an exercise's own step.
    let equipment: Equipment?
    /// The step to start from, in kilograms.
    let kilograms: Double?
}

/// Types a progression step in the display unit, for when no preset fits. Done is enabled
/// only for a valid step (see ``ProgressionStepInput``), which is handed back in kilograms.
struct CustomStepSheet: View {
    /// What the step is for, shown above the field ("Barbell", "Bench Press").
    let subject: String
    let unit: WeightUnit
    let onSave: (Double) -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(subject: String, unit: WeightUnit, kilograms: Double?, onSave: @escaping (Double) -> Void) {
        self.subject = subject
        self.unit = unit
        self.onSave = onSave
        _text = State(initialValue: ProgressionStepInput.text(kilograms: kilograms, unit: unit))
    }

    var body: some View {
        let result = ProgressionStepInput.kilograms(from: text, unit: unit)
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Step") {
                        HStack(spacing: 6) {
                            TextField("Step", text: $text, prompt: Text(verbatim: placeholder))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused($isFocused)
                                .accessibilityLabel(String(localized: "Step in \(unitName)"))
                            Text(verbatim: unit.symbol)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                } header: {
                    Text(subject)
                } footer: {
                    footer(for: result)
                }
            }
            .navigationTitle("Custom Step")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        guard case .success(let kilograms) = result else { return }
                        onSave(kilograms)
                        dismiss()
                    }
                    .disabled(!result.isSuccess)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private var maximum: String {
        "\(ProgressionStepInput.maximumValue(for: unit).formatted(.number.precision(.fractionLength(0...ProgressionStepInput.fractionDigits)))) \(unit.symbol)"
    }

    private var placeholder: String {
        (unit == .kg ? 2.5 : 5).formatted(.number.precision(.fractionLength(0...1)))
    }

    private var unitName: String {
        unit == .kg ? String(localized: "kilograms") : String(localized: "pounds")
    }

    @ViewBuilder
    private func footer(for result: Result<Double, ProgressionStepInput.Problem>) -> some View {
        switch result {
        case .success, .failure(.empty):
            Text("Any step up to \(maximum). The ↑ suggestion on Apple Watch adds this much.")
        case .failure(.notANumber):
            Text("Enter a number, like \(placeholder).")
                .foregroundStyle(.red)
        case .failure(.notPositive):
            Text("Enter a step above 0.")
                .foregroundStyle(.red)
        case .failure(.tooLarge):
            Text("Enter a step of at most \(maximum).")
                .foregroundStyle(.red)
        }
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
