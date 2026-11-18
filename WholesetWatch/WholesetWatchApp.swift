// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import SwiftUI
import WholesetKit

@main
struct WholesetWatchApp: App {
    @WKApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            if let container = appDelegate.container, let controller = appDelegate.controller, let store = appDelegate.store {
                RootView(controller: controller)
                    .environment(store)
                    .modelContainer(container)
            } else {
                StoreUnavailableView()
            }
        }
    }
}
