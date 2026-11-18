// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import SwiftUI
import WholesetKit

/// The tab bar holding the four sections. Each tab owns its own navigation stack. The
/// first-launch screens cover it until they are done on this device.
struct RootTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.scenePhase) private var scenePhase
    /// Oldest first, like Settings: the row that survives a sync merge.
    @Query(sort: \AppSettings.createdAt) private var settingsRows: [AppSettings]

    var body: some View {
        @Bindable var navigation = navigation
        @Bindable var model = model
        TabView(selection: $navigation.tab) {
            Tab("Plan", systemImage: "calendar", value: AppTab.plan) {
                PlanView()
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                HistoryView()
            }
            Tab("Exercises", systemImage: "dumbbell", value: AppTab.exercises) {
                ExercisesView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .environment(\.weightUnit, settingsRows.first?.unit ?? .kg)
        .fullScreenCover(isPresented: $model.showsOnboarding) {
            OnboardingView(step: model.onboardingStep)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.health.refresh()
                model.store.sync.refreshAccountStatus()
            }
        }
    }
}
