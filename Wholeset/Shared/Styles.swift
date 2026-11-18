// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// A full-width button filled with the accent colour, for the one main action of a screen.
///
/// The label is white on the darker light-mode accent and black on the brighter dark-mode
/// accent, which keeps it readable in both.
struct AccentFillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.accentColor.opacity(isEnabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension View {
    /// Draws the label of a button that fills a list row in the standard label colours.
    ///
    /// A list draws button labels in the tint colour, and hierarchical styles inside the
    /// label (`.primary`, `.secondary`, `.tertiary`) are levels of that tint, so a name and its
    /// detail line both come out in the accent colour. Apply this to the label: text then
    /// reads as primary and secondary (dimmed while the button is disabled), and only parts
    /// styled with `.tint`, such as a checkmark, use the accent colour.
    func listRowButtonLabel() -> some View {
        modifier(ListRowButtonLabel())
    }
}

private struct ListRowButtonLabel: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.foregroundStyle(isEnabled ? Color.primary : Color.secondary)
    }
}

/// A capsule filter chip, filled when selected.
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? AnyShapeStyle(.background) : AnyShapeStyle(.primary))
                .background(
                    isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary),
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(isSelected ? "" : String(localized: "Shows only this group."))
    }
}
