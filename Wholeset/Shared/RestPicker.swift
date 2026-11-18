// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import WholesetKit

/// A rest setting as list rows, like the Clock app's timer: a row with the current value
/// ("1:30") that expands, on tap, into a minutes wheel and a seconds wheel.
///
/// Where the rest may follow a default instead (`seconds` is `nil`), a "Use Default"
/// switch sits above the wheels and hides them while it is on. Every value written is a
/// valid rest (see ``RestComponents``).
struct RestPicker: View {
    /// What `nil` means where the rest may follow a default.
    struct DefaultOption {
        /// The row's value while following the default, for example "Default (2:00)".
        let summary: String
        /// The switch's subtitle, saying where the default comes from.
        let explanation: String
        /// The rest the default currently stands for: where the wheels start when the
        /// switch is turned off.
        let seconds: Int
    }

    private let title: String
    @Binding private var seconds: Int?
    private let defaultOption: DefaultOption?
    @State private var isExpanded: Bool

    /// A rest that may follow a default: `nil` means "use the default".
    init(_ title: String, seconds: Binding<Int?>, default defaultOption: DefaultOption, isExpanded: Bool = false) {
        self.title = title
        _seconds = seconds
        self.defaultOption = defaultOption
        _isExpanded = State(initialValue: isExpanded)
    }

    /// A rest that always has a value.
    init(_ title: String, seconds: Binding<Int>, isExpanded: Bool = false) {
        self.title = title
        _seconds = Binding(
            get: { seconds.wrappedValue },
            set: { if let value = $0 { seconds.wrappedValue = value } }
        )
        defaultOption = nil
        _isExpanded = State(initialValue: isExpanded)
    }

    var body: some View {
        Button {
            withAnimation { isExpanded.toggle() }
        } label: {
            LabeledContent {
                Text(valueText)
                    .monospacedDigit()
                    .foregroundStyle(isExpanded ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            } label: {
                Text(title)
            }
            .listRowButtonLabel()
        }
        .accessibilityLabel(title)
        .accessibilityValue(spokenValue)
        .accessibilityHint(isExpanded ? String(localized: "Hides the rest picker.") : String(localized: "Shows the rest picker."))
        .accessibilityAddTraits(isExpanded ? [.isSelected] : [])

        if isExpanded {
            if let defaultOption {
                Toggle(isOn: usesDefault(defaultOption)) {
                    Text("Use Default")
                    Text(defaultOption.explanation)
                }
            }
            if let explicit = seconds {
                RestWheels(seconds: Binding(get: { seconds ?? explicit }, set: { seconds = $0 }))
            }
        }
    }

    private var valueText: String {
        if let seconds { return Formatting.rest(seconds) }
        return defaultOption?.summary ?? ""
    }

    private var spokenValue: String {
        if let seconds { return Formatting.spokenRest(seconds) }
        return defaultOption?.summary ?? ""
    }

    private func usesDefault(_ option: DefaultOption) -> Binding<Bool> {
        Binding(
            get: { seconds == nil },
            set: { isOn in
                withAnimation {
                    seconds = isOn ? nil : RestComponents(totalSeconds: option.seconds).totalSeconds
                }
            }
        )
    }
}

/// A minutes wheel and a seconds wheel side by side, labelled "min" and "sec".
private struct RestWheels: View {
    @Binding var seconds: Int

    var body: some View {
        HStack(spacing: 0) {
            wheel(
                String(localized: "Minutes"),
                unit: String(localized: "min", comment: "Short for minutes, next to the minutes wheel"),
                choices: RestComponents.minuteChoices,
                selection: Binding(
                    get: { RestComponents(totalSeconds: seconds).minutes },
                    set: { seconds = RestComponents(totalSeconds: seconds).settingMinutes($0).totalSeconds }
                ),
                spoken: Formatting.spokenMinutes
            )
            wheel(
                String(localized: "Seconds"),
                unit: String(localized: "sec", comment: "Short for seconds, next to the seconds wheel"),
                choices: RestComponents.secondChoices,
                selection: Binding(
                    get: { RestComponents(totalSeconds: seconds).seconds },
                    set: { seconds = RestComponents(totalSeconds: seconds).settingSeconds($0).totalSeconds }
                ),
                spoken: Formatting.spokenSeconds
            )
        }
        .accessibilityElement(children: .contain)
    }

    private func wheel(
        _ title: String,
        unit: String,
        choices: [Int],
        selection: Binding<Int>,
        spoken: @escaping (Int) -> String
    ) -> some View {
        HStack(spacing: 4) {
            Picker(title, selection: selection) {
                ForEach(choices, id: \.self) { value in
                    Text(verbatim: value.formatted())
                        .monospacedDigit()
                        .accessibilityLabel(spoken(value))
                        .tag(value)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity, maxHeight: 160)
            .clipped()
            .accessibilityLabel(title)
            Text(unit)
                .font(.body.weight(.semibold))
                .fixedSize()
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }
}
