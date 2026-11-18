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
    /// Set 1 of Bench Press with "last 60 × 10" from yesterday's workout, no chip.
    case lastLine = "last-line"
    /// Yesterday every working set hit the top of the range: the ↑ chip shows.
    case progressionChip = "progression-chip"
    /// The menu's Swap screen: alternatives with last time, then Other….
    case swap
    /// The menu's Add exercise screen: recent exercises, then muscle groups.
    case addExercise = "add-exercise"
    /// All exercises in Edit mode, one exercise skipped.
    case allExercisesEdit = "all-exercises-edit"
    /// A workout started without a routine, before anything is added.
    case emptyWorkout = "empty-workout"
    /// After the summary of a Push workout with a swap and an added exercise.
    case updateRoutine = "update-routine"
    /// After the summary of an empty workout that logged sets.
    case saveAsRoutine = "save-as-routine"
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

        let bar = unit == .kg ? 60 : WeightUnit.lb.kilograms(fromValue: 135)
        let exercises = Dictionary(try context.fetch(FetchDescriptor<Exercise>()).map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        try addHistory(exercises: exercises, unit: unit, bar: bar, benchHitsTop: screen == .progressionChip, context: context)

        switch screen {
        case .emptyWorkout:
            let engine = try WorkoutEngine.startEmpty(in: context, defaultRestSeconds: 90, progressionSettings: controller.progression)
            let startedAt = Date.now.addingTimeInterval(-90)
            engine.session.startedAt = startedAt
            try context.save()
            health.simulateRunning()
            controller.installDemoWorkout(engine: engine, clock: WorkoutClock(startedAt: startedAt), rest: nil, phase: .active)
            return
        case .updateRoutine, .saveAsRoutine:
            try installRoutinePrompt(for: screen, controller: controller, exercises: exercises, bar: bar, context: context)
            return
        default:
            break
        }

        guard let push = TodayPlanResolver.sortedRoutines(try context.fetch(FetchDescriptor<Routine>())).first else { return }
        let engine = try WorkoutEngine.start(routine: push, in: context, defaultRestSeconds: 90, progressionSettings: controller.progression)
        let startedAt = Date.now.addingTimeInterval(-(23 * 60 + 41))
        engine.session.startedAt = startedAt

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
        if screen != .lastLine && screen != .progressionChip {
            try log(bar, 10)
        }
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
            controller.openMenu()
        case .swap:
            controller.openMenu(at: [.swap])
        case .addExercise:
            controller.openMenu(at: [.exercises(.add)])
        case .allExercisesEdit:
            try engine.setSkipped(true, for: engine.entries[engine.entries.count - 1])
            controller.openMenu(at: [.allExercises(editing: true)])
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
        case .home, .homeSyncing, .countdown, .summary, .exercise, .lastLine, .progressionChip,
             .emptyWorkout, .updateRoutine, .saveAsRoutine:
            break
        }
        try context.save()
        if phase == .active || health.recoveryStatus == .recovered {
            health.simulateRunning()
        }
        controller.installDemoWorkout(engine: engine, clock: WorkoutClock(startedAt: startedAt), rest: rest, phase: phase)
    }

    /// Yesterday's finished Push workout plus an older one with other exercises, so pre-fill,
    /// the "last" line, swap rows and Recent show real values. Bench Press alternatives are
    /// set as they would be on iPhone.
    private static func addHistory(exercises: [String: Exercise], unit: WeightUnit, bar: Double, benchHitsTop: Bool, context: ModelContext) throws {
        func kilograms(_ kg: Double, _ lb: Double) -> Double {
            unit == .kg ? kg : WeightUnit.lb.kilograms(fromValue: lb)
        }
        let yesterday = Date.now.addingTimeInterval(-86_400)
        let benchReps = benchHitsTop ? [10, 10, 10] : [10, 9, 8]
        insertFinishedSession(named: "Push", startedAt: yesterday, entries: [
            ("Bench Press", benchReps.map { (bar, $0) }),
            ("Overhead Press", [(kilograms(40, 85), 8), (kilograms(40, 85), 8), (kilograms(40, 85), 7)]),
            ("Lateral Raise", [(kilograms(8, 17.5), 15), (kilograms(8, 17.5), 14), (kilograms(8, 17.5), 12)]),
        ], exercises: exercises, context: context)
        insertFinishedSession(named: "Upper", startedAt: yesterday.addingTimeInterval(-3 * 86_400), entries: [
            ("Dumbbell Bench Press", [(kilograms(26, 55), 10), (kilograms(26, 55), 10)]),
            ("Machine Chest Press", [(kilograms(55, 120), 12)]),
            ("Face Pull", [(kilograms(20, 45), 15)]),
        ], exercises: exercises, context: context)
        if let bench = exercises["Bench Press"] {
            RoutineEditing.setAlternatives(["Dumbbell Bench Press", "Machine Chest Press"].compactMap { exercises[$0] }, for: bench)
        }
        try context.save()
    }

    private static func insertFinishedSession(
        named name: String,
        startedAt: Date,
        entries: [(String, [(Double, Int)])],
        exercises: [String: Exercise],
        context: ModelContext
    ) {
        let session = Session(name: name, startedAt: startedAt)
        session.endedAt = startedAt.addingTimeInterval(55 * 60)
        context.insert(session)
        for (order, spec) in entries.enumerated() {
            guard let exercise = exercises[spec.0] else { continue }
            let entry = SessionExercise(order: order, repLow: 6, repHigh: 10)
            context.insert(entry)
            entry.session = session
            entry.exercise = exercise
            for (index, set) in spec.1.enumerated() {
                let log = SetLog(order: index, weightKg: set.0, reps: set.1)
                log.completedAt = startedAt.addingTimeInterval(Double(60 * (order * 6 + index + 1)))
                context.insert(log)
                log.entry = entry
            }
        }
    }

    /// Runs a short real workout through the engine, ends it and shows the prompt the
    /// controller would show after the summary.
    private static func installRoutinePrompt(
        for screen: DemoScreen,
        controller: WorkoutController,
        exercises: [String: Exercise],
        bar: Double,
        context: ModelContext
    ) throws {
        let engine: WorkoutEngine
        if screen == .updateRoutine {
            guard let push = TodayPlanResolver.sortedRoutines(try context.fetch(FetchDescriptor<Routine>())).first else { return }
            engine = try WorkoutEngine.start(routine: push, in: context, defaultRestSeconds: 90)
            try engine.logCurrentSet()
            if let dumbbell = exercises["Dumbbell Bench Press"] {
                try engine.swapCurrentExercise(to: dumbbell)
                try engine.logCurrentSet()
                try engine.logCurrentSet()
            }
            if let facePull = exercises["Face Pull"] {
                try engine.addExercise(facePull)
                try engine.logCurrentSet()
            }
            engine.select(entryAt: 2)
            try engine.addSet()
        } else {
            engine = try WorkoutEngine.startEmpty(in: context, defaultRestSeconds: 90)
            for name in ["Bench Press", "Face Pull"] {
                guard let exercise = exercises[name] else { continue }
                try engine.addExercise(exercise)
                engine.setCurrentWeight(bar)
                try engine.logCurrentSet()
            }
        }
        try engine.finish()
        let session = engine.session
        let kind: RoutinePrompt.Kind
        if let proposal = RoutineUpdate.proposal(for: session) {
            kind = .update(proposal)
        } else {
            kind = .saveAsRoutine(suggestedName: RoutineUpdate.suggestedRoutineName(for: session))
        }
        controller.installDemoPhase(.routinePrompt(RoutinePrompt(sessionID: session.id, kind: kind)))
    }
}
#endif
