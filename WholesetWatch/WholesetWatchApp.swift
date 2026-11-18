// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import SwiftUI
import WholesetKit

@main
struct WholesetWatchApp: App {
    private let store = WholesetStore.loadAppContainer(cloudKit: WholesetStore.cloudKitEnabledByDefault)

    var body: some Scene {
        WindowGroup {
            if let container = store.container {
                HomeView()
                    .modelContainer(container)
            } else {
                StoreUnavailableView()
            }
        }
    }
}
