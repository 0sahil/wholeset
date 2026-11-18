// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import SwiftUI
import WholesetKit

@main
struct WholesetWatchApp: App {
    @WKApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            if let container = appDelegate.container, let controller = appDelegate.controller {
                RootView(controller: controller)
                    .modelContainer(container)
            } else {
                StoreUnavailableView()
            }
        }
    }
}
