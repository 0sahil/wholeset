// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Colours, fonts and button styles of the Watch app: pure black, one orange accent.
enum Theme {
    /// The accent (#FF8A3D): titles, Log/Start buttons, logged-set dots, the focus ring.
    static let accent = Color(red: 1, green: 138 / 255, blue: 61 / 255)
    /// Tile background (#1D1D1F).
    static let tile = Color(red: 29 / 255, green: 29 / 255, blue: 31 / 255)
    /// Secondary button background (#232325).
    static let control = Color(red: 35 / 255, green: 35 / 255, blue: 37 / 255)
    /// Unlogged-set dot (#3A3A3C).
    static let idleDot = Color(red: 58 / 255, green: 58 / 255, blue: 60 / 255)
    /// The elapsed workout clock in the top bar (#FFD60A).
    static let elapsed = Color(red: 1, green: 214 / 255, blue: 10 / 255)
    /// Destructive text (#FF453A).
    static let destructive = Color(red: 1, green: 69 / 255, blue: 58 / 255)

    /// Minimum height of anything tappable.
    static let minTapHeight: CGFloat = 42

    /// Big numbers: SF Pro Rounded, semibold, tabular figures. Scales with Dynamic Type.
    static func number(_ style: Font.TextStyle) -> Font {
        .system(style, design: .rounded, weight: .semibold).monospacedDigit()
    }
}

/// A full-width capsule filled with the accent, black label.
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.black)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: Theme.minTapHeight)
            .padding(.horizontal, 8)
            .background(Theme.accent.opacity(isEnabled ? 1 : 0.4), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// A full-width dark grey capsule.
struct SecondaryButtonStyle: ButtonStyle {
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(foreground)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: Theme.minTapHeight)
            .padding(.horizontal, 8)
            .background(Theme.control, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// A screen title in the accent colour, up to two lines, with an optional trailing accessory.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.accent)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                // Takes the height of both lines before anything below gets squeezed.
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 2)
            trailing
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}
