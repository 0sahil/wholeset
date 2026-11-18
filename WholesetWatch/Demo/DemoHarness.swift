// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import Foundation
import SwiftData
import WholesetKit

/// Screens the DEBUG demo harness can open straight into, for screenshots.
///
/// Launch with `-WholesetDemo <screen>`, optionally `-WholesetDemoUnit lb`. The app then
/// uses an in-memory store with the starter routines, canned workout data and a fake
/// HealthKit manager. Nothing of this is compiled into Release builds.
enum DemoScreen: String, CaseIterable {
    case home
    case countdown
    case exercise
    case exerciseSelected = "exercise-selected"
    case done
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
    static func makeLaunch(for screen: DemoScreen) -> (container: ModelContainer?, controller: WorkoutController?) {
        guard let container = try? WholesetStore.makeContainer(inMemory: true) else { return (nil, nil) }
        let context = container.mainContext
        let unit = requestedUnit()
        if let settings = try? AppSettings.current(in: context) {
            settings.unit = unit
            settings.updatedAt = .now
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
        do {
            try configure(controller, health: health, for: screen, unit: unit, context: context)
        } catch {
            assertionFailure("Demo setup failed: \(error)")
        }
        return (container, controller)
    }

    private static func configure(
        _ controller: WorkoutController,
        health: FakeWorkoutManager,
        for screen: DemoScreen,
        unit: WeightUnit,
        context: ModelContext
    ) throws {
        switch screen {
        case .home:
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

        try log(bar, 10)
        var rest: RestTimer?
        var phase = WorkoutController.Phase.active
        switch screen {
        case .exerciseSelected:
            engine.setCurrentWeight(unit == .kg ? 62.5 : WeightUnit.lb.kilograms(fromValue: 140))
            controller.initialTileSelection = .weight
        case .done:
            try log(bar, 10)
            try log(bar, 9)
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
        case .home, .countdown, .summary, .exercise:
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
