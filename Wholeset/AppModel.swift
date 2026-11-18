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
    /// Records, PRs and the history list, recomputed when the store changes.
    let history: HistoryModel
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
        self.history = HistoryModel(container: container)
        self.defaults = defaults
        self.showsOnboarding = showsOnboarding ?? !defaults.bool(forKey: Self.onboardingKey)
        self.onboardingStep = onboardingStep
        // CloudKit imports (a workout arriving from the Watch) end with a maintenance pass.
        store.onMaintenance = { [weak history = self.history] in history?.reload() }
        history.start()
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

    /// Shows the import flow, reading `url` at once when given (a CSV opened in Wholeset).
    /// A file opened while an import is being written is ignored; otherwise it replaces the
    /// file of an import that is showing.
    func beginImport(opening url: URL? = nil) {
        if let flow = navigation.importFlow {
            guard let url, !flow.isWriting, flow.summary == nil else { return }
            flow.open(url)
            return
        }
        let unit = (try? container.mainContext.fetch(FetchDescriptor<AppSettings>(sortBy: [SortDescriptor(\.createdAt)])).first?.unit) ?? .kg
        let flow = ImportFlowModel(container: container, history: history, unit: unit)
        if let url { flow.open(url) }
        navigation.importFlow = flow
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

/// Screens pushed on the History and Exercises tabs. Either stack can reach every one of
/// them (a session's exercise, that exercise's sessions, and so on).
enum AppDestination: Hashable {
    /// A finished session.
    case session(UUID)
    /// An exercise's records, charts and log.
    case exercise(UUID)
    /// An exercise's settings.
    case exerciseSettings(UUID)
    /// The most reps an exercise was done for at each weight.
    case repsByWeight(UUID)
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
    /// Screens pushed on the History tab.
    var historyPath: [AppDestination] = []
    /// The History search text, kept while switching tabs.
    var historySearch = ""
    /// Screens pushed on the Exercises tab.
    var exercisePath: [AppDestination] = []
    /// Screens pushed on the Settings tab.
    var settingsPath: [SettingsDestination] = []
    /// The import flow, shown as a sheet over every tab.
    var importFlow: ImportFlowModel?
    #if DEBUG
    /// A control the DEBUG demo harness shows open on the screen it opens.
    var demoReveal: DemoReveal?
    #endif

    init(
        tab: AppTab = .plan,
        planSheet: PlanSheet? = nil,
        historyPath: [AppDestination] = [],
        exercisePath: [AppDestination] = [],
        settingsPath: [SettingsDestination] = []
    ) {
        self.tab = tab
        self.planSheet = planSheet
        self.historyPath = historyPath
        self.exercisePath = exercisePath
        self.settingsPath = settingsPath
    }

    /// Pushes `destination` on the stack of the History or Exercises tab, whichever is showing.
    func push(_ destination: AppDestination) {
        switch tab {
        case .history: historyPath.append(destination)
        case .exercises: exercisePath.append(destination)
        case .plan, .settings: break
        }
    }
}
