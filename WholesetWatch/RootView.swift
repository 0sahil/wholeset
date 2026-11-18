// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import WholesetKit

/// Switches between the app's top-level screens and reports scene activity to the controller.
struct RootView: View {
    @Bindable var controller: WorkoutController
    @Environment(StoreCoordinator.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .tint(Theme.accent)
            .onChange(of: scenePhase, initial: true) { _, phase in
                controller.sceneDidChange(isActive: phase == .active)
                if phase == .active {
                    controller.refreshSettings()
                }
            }
            .onChange(of: controller.isWorkoutRunning) { _, isRunning in
                // Sync merges held during the workout run once it is over.
                if !isRunning {
                    store.resumeDeferredMaintenance()
                }
            }
            .alert(
                controller.errorMessage ?? "",
                isPresented: Binding(
                    get: { controller.errorMessage != nil },
                    set: { if !$0 { controller.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            }
    }

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .home:
            HomeView(controller: controller)
        case .preparing(let routineName):
            CountdownView(routineName: routineName, info: nil, onFinish: {}, onCancel: controller.cancelStart)
        case .countdown(let info):
            CountdownView(
                routineName: info.routineName,
                info: info,
                onFinish: controller.countdownFinished,
                onCancel: controller.cancelStart
            )
        case .active:
            WorkoutPagesView(controller: controller)
        case .restored:
            RestoredView(controller: controller)
        case .summary(let info):
            SummaryView(info: info, unit: controller.unit) {
                controller.closeSummary()
            }
        }
    }
}
