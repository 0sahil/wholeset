// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Shown instead of the app when no data store could be opened at all.
struct StoreUnavailableView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Can't Open Your Data", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Wholeset couldn't open its database. Quit and reopen the app to try again.")
        }
    }
}

#Preview {
    StoreUnavailableView()
}
