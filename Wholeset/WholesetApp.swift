// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import SwiftUI
import WholesetKit

@main
struct WholesetApp: App {
    private let model: AppModel?
    #if DEBUG
    /// Launched with `CloudKitSchemaSetupView.launchArgument`: the store is never opened.
    private let initializesCloudKitSchema: Bool
    #endif

    init() {
        #if DEBUG
        initializesCloudKitSchema = CloudKitSchemaSetupView.isRequested()
        if initializesCloudKitSchema {
            model = nil
            return
        }
        #endif
        model = AppModel.launch()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if initializesCloudKitSchema {
                CloudKitSchemaSetupView()
            } else {
                content
            }
            #else
            content
            #endif
        }
    }

    @ViewBuilder private var content: some View {
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
