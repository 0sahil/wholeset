// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import SwiftUI
import WholesetKit

@main
struct WholesetApp: App {
    private let store = WholesetStore.loadAppContainer(cloudKit: WholesetStore.cloudKitEnabledByDefault)

    var body: some Scene {
        WindowGroup {
            if let container = store.container {
                RootTabView()
                    .modelContainer(container)
            } else {
                StoreUnavailableView()
            }
        }
    }
}
