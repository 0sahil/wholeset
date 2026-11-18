// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The Watch home screen. Placeholder layout only: nothing is actionable yet.
struct HomeView: View {
    var body: some View {
        NavigationStack {
            List {
                StartPlaceholder()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                Label("Other routine", systemImage: "list.bullet")
                Label("Empty workout", systemImage: "plus")
            }
            .navigationTitle {
                Text("Wholeset")
                    .foregroundStyle(Color.accentColor)
            }
            .containerBackground(.black, for: .navigation)
        }
    }
}

/// The large Start button, shown disabled until routines exist.
private struct StartPlaceholder: View {
    var body: some View {
        Button {} label: {
            VStack(spacing: 2) {
                Text("Start")
                    .font(.title3.weight(.semibold))
                Text("No routine planned")
                    .font(.footnote)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.accentColor)
        .foregroundStyle(.black)
        .disabled(true)
        .accessibilityHint("Available once you add a routine on iPhone.")
    }
}

#Preview {
    HomeView()
}
