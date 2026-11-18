// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// A tab root with a large title and an empty state, used until the section is built.
struct TabPlaceholderView: View {
    let title: LocalizedStringKey
    let systemImage: String
    let emptyTitle: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(emptyTitle, systemImage: systemImage)
            } description: {
                Text(message)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    TabPlaceholderView(
        title: "History",
        systemImage: "clock.arrow.circlepath",
        emptyTitle: "No Workouts Yet",
        message: "Finished workouts will appear here."
    )
}
