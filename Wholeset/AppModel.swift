// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation
import SwiftData
import WholesetKit

/// The iPhone app's long-lived objects.
@Observable
final class AppModel {
    /// The opened store.
    let container: ModelContainer
    /// Library seed, sync dedupe and iCloud sync status.
    let store: StoreCoordinator
    /// Apple Health permission.
    let health: HealthPermission
    /// Tabs, sheets and pushed screens.
    let navigation: AppNavigation
    /// Whether the first-launch screens are showing.
    var showsOnboarding: Bool
    /// The first-launch screen to start on (DEBUG demos start later in the flow).
    let onboardingStep: OnboardingStep

    @ObservationIgnored private let defaults: UserDefaults

    /// The local (not synced) flag that the first-launch screens were completed.
    static let onboardingKey = "onboardingCompleted"

    init(
        container: ModelContainer,
        store: StoreCoordinator,
        health: HealthPermission = HealthPermission(),
        navigation: AppNavigation = AppNavigation(),
        defaults: UserDefaults = .standard,
        showsOnboarding: Bool? = nil,
        onboardingStep: OnboardingStep = .welcome
    ) {
        self.container = container
        self.store = store
        self.health = health
        self.navigation = navigation
        self.defaults = defaults
        self.showsOnboarding = showsOnboarding ?? !defaults.bool(forKey: Self.onboardingKey)
        self.onboardingStep = onboardingStep
    }

    /// Opens the store and starts maintenance, or returns `nil` if no store could be opened.
    static func launch() -> AppModel? {
        #if DEBUG
        if let demo = DemoHarness.requestedState() {
            return DemoHarness.makeModel(for: demo)
        }
        #endif
        let opened = WholesetStore.loadAppContainer(cloudKit: WholesetStore.cloudKitEnabledByDefault)
        guard let container = opened.container, let mode = opened.mode else { return nil }
        // The iPhone never adds starter routines on its own; the Plan screen offers them.
        let store = StoreCoordinator(container: container, sync: SyncMonitor(mode: mode), policy: .manual)
        store.start()
        return AppModel(container: container, store: store)
    }

    /// Records that the first-launch screens are done on this device.
    func finishOnboarding() {
        defaults.set(true, forKey: Self.onboardingKey)
        showsOnboarding = false
    }
}

/// The iPhone app's top-level sections.
enum AppTab: Hashable {
    case plan
    case history
    case exercises
    case settings
}

/// Sheets shown over the Plan tab.
enum PlanSheet: Identifiable, Hashable {
    /// The routine editor for a new routine.
    case newRoutine
    /// The routine editor for an existing routine; `showsPicker` opens the exercise picker too.
    case editRoutine(UUID, showsPicker: Bool = false)
    /// Choosing the routine for a weekday.
    case day(Int)

    var id: Self { self }
}

/// Screens pushed on the Settings tab.
enum SettingsDestination: Hashable {
    /// The default progression step per equipment.
    case progressionSteps
}

/// Where the app is: the selected tab and what each tab shows.
@Observable
final class AppNavigation {
    var tab: AppTab = .plan
    /// The sheet over the Plan tab.
    var planSheet: PlanSheet?
    /// Exercises pushed on the Exercises tab, by id.
    var exercisePath: [UUID] = []
    /// Screens pushed on the Settings tab.
    var settingsPath: [SettingsDestination] = []

    init(tab: AppTab = .plan, planSheet: PlanSheet? = nil, exercisePath: [UUID] = [], settingsPath: [SettingsDestination] = []) {
        self.tab = tab
        self.planSheet = planSheet
        self.exercisePath = exercisePath
        self.settingsPath = settingsPath
    }
}
