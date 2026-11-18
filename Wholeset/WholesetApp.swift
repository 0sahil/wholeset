// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import SwiftUI
import WholesetKit

@main
struct WholesetApp: App {
    private let model = AppModel.launch()

    var body: some Scene {
        WindowGroup {
            if let model {
                RootTabView()
                    .environment(model)
                    .environment(model.store)
                    .environment(model.navigation)
                    .environment(model.history)
                    .modelContainer(model.container)
            } else {
                StoreUnavailableView()
            }
        }
    }
}
