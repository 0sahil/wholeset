// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import Foundation
import SwiftData
import WholesetKit

/// Screens the DEBUG demo harness can open straight into, for screenshots.
///
/// Launch with `-WholesetDemo <screen>`, optionally `-WholesetDemoUnit lb` (as if pounds
/// had been chosen on iPhone and synced). The app then uses an in-memory store with the
/// library and starter routines, canned workout data and a fake HealthKit manager.
/// Nothing of this is compiled into Release builds.
enum DemoScreen: String, CaseIterable {
    case home
    /// Home on a first launch while the Watch waits for iCloud before adding starter routines.
    case homeSyncing = "home-syncing"
    case countdown
    case exercise
    case exerciseSelected = "exercise-selected"
    /// Set 3 of 3 with two sets logged, for the logged-sets table on the exercise page.
    case exerciseLogged = "exercise-logged"
    case done
    /// A warm-up and four working sets logged: the done page's table scrolls.
    case doneLong = "done-long"
    case rest
    case menu
    case stats
    case endConfirm = "end-confirm"
    case summary
    case restored
    case restoredNoHealth = "restored-nohealth"
}

enum DemoHarness {
    private static let screenArgument = "-WholesetDemo"
    private static let unitArgument = "-WholesetDemoUnit"

    /// The screen requested on the command line, if any.
    static func requestedScreen(arguments: [String] = ProcessInfo.processInfo.arguments) -> DemoScreen? {
        value(after: screenArgument, in: arguments).flatMap(DemoScreen.init(rawValue:))
    }

    private static func requestedUnit(arguments: [String] = ProcessInfo.processInfo.arguments) -> WeightUnit {
        value(after: unitArgument, in: arguments).flatMap(WeightUnit.init(rawValue:)) ?? .kg
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// Builds an in-memory store and a controller showing `screen`.
    static func makeLaunch(for screen: DemoScreen) -> (container: ModelContainer?, controller: WorkoutController?, store: StoreCoordinator?) {
        guard let container = try? WholesetStore.makeContainer(inMemory: true) else { return (nil, nil, nil) }
        let context = container.mainContext
        // An in-memory store cannot sync, so the coordinator seeds the starters at once;
        // the syncing demo pretends CloudKit is on and no import has finished.
        let sync = screen == .homeSyncing
            ? SyncMonitor(mode: .cloudKit) { .available }
            : SyncMonitor(mode: .inMemory)
        let store = StoreCoordinator(container: container, sync: sync, policy: .automatic, patience: .seconds(3_600))
        store.start()
        let unit = requestedUnit()
        if let settings = try? AppSettings.current(in: context) {
            SettingsEditing.setUnit(unit, on: settings)
            try? context.save()
        }

        let suite = "wholeset.demo"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)

        let health = FakeWorkoutManager()
        let controller = WorkoutController(
            context: context,
            health: health,
            alerts: RestAlertScheduler(isEnabled: false),
            stateStore: ActiveWorkoutStateStore(defaults: defaults)
        )
        AppDelegate.connect(store, to: controller)
        do {
            try configure(controller, health: health, for: screen, unit: unit, context: context)
        } catch {
            assertionFailure("Demo setup failed: \(error)")
        }
        return (container, controller, store)
    }

    private static func configure(
        _ controller: WorkoutController,
        health: FakeWorkoutManager,
        for screen: DemoScreen,
        unit: WeightUnit,
        context: ModelContext
    ) throws {
        switch screen {
        case .home, .homeSyncing:
            return
        case .countdown:
            controller.installDemoPhase(.countdown(CountdownInfo(routineName: "Push", endsAt: .now.addingTimeInterval(2), isFrozen: true)))
            return
        case .summary:
            controller.installDemoPhase(.summary(WorkoutSummaryInfo(
                sessionID: UUID(),
                routineName: "Push",
                duration: 58 * 60,
                workingSets: 15,
                volumeKg: 6240,
                averageHeartRate: 128,
                maxHeartRate: 161,
                activeKilocalories: 412,
                health: .saved
            )))
            return
        default:
            break
        }

        guard let push = TodayPlanResolver.sortedRoutines(try context.fetch(FetchDescriptor<Routine>())).first else { return }
        let engine = try WorkoutEngine.start(routine: push, in: context, defaultRestSeconds: 90)
        let startedAt = Date.now.addingTimeInterval(-(23 * 60 + 41))
        engine.session.startedAt = startedAt
        let bar = unit == .kg ? 60 : WeightUnit.lb.kilograms(fromValue: 135)

        func log(_ weight: Double, _ reps: Int) throws {
            engine.setCurrentWeight(weight)
            engine.setCurrentReps(reps)
            try engine.logCurrentSet()
        }

        if screen == .doneLong {
            // An empty-bar warm-up first, plus two extra working sets (five sets in all).
            try engine.toggleWarmupOnCurrentSet()
            try log(unit == .kg ? 20 : WeightUnit.lb.kilograms(fromValue: 45), 10)
            try engine.addSet()
            try engine.addSet()
        }
        try log(bar, 10)
        var rest: RestTimer?
        var phase = WorkoutController.Phase.active
        switch screen {
        case .exerciseSelected:
            engine.setCurrentWeight(unit == .kg ? 62.5 : WeightUnit.lb.kilograms(fromValue: 140))
            controller.initialTileSelection = .weight
        case .exerciseLogged:
            try log(bar, 10)
        case .done:
            try log(bar, 10)
            try log(bar, 9)
        case .doneLong:
            try log(bar, 10)
            try log(bar, 9)
            try log(bar, 8)
        case .rest:
            rest = RestTimer.start(duration: 150, now: .now.addingTimeInterval(-40))
        case .menu:
            controller.sheet = .menu
        case .stats:
            controller.page = .stats
        case .endConfirm:
            try log(bar, 10)
            try log(bar, 9)
            controller.sheet = .endConfirm
        case .restored:
            try log(bar, 9)
            health.recoveryStatus = .recovered
            phase = .restored
        case .restoredNoHealth:
            try log(bar, 9)
            health.recoveryStatus = .failed
            phase = .restored
        case .home, .homeSyncing, .countdown, .summary, .exercise:
            break
        }
        try context.save()
        if phase == .active || health.recoveryStatus == .recovered {
            health.simulateRunning()
        }
        controller.installDemoWorkout(engine: engine, clock: WorkoutClock(startedAt: startedAt), rest: rest, phase: phase)
    }
}
#endif
