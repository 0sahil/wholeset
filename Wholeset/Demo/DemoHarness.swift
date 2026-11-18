// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import Foundation
import SwiftData
import WholesetKit

/// Screens the DEBUG demo harness can open straight into, for screenshots.
///
/// Launch with `-WholesetDemo <state>`, optionally `-WholesetDemoUnit lb`. The app then
/// uses an in-memory store with the library, the starter routines, a weekly plan, over a year
/// of workout history (one of them imported) and a pretend iCloud status. The `import-…`
/// states run the import flow on invented export files (``DemoImportFiles``). Nothing of this
/// is compiled into Release builds.
enum DemoState: String, CaseIterable {
    case welcome
    case units
    case health
    case plan
    case planEmpty = "plan-empty"
    case routineEditor = "routine-editor"
    case exercisePicker = "exercise-picker"
    case exercises
    case exerciseDetail = "exercise-detail"
    case settings
    /// Settings → Progression Steps, with one step changed from its default.
    case progressionSteps = "progression-steps"
    /// An exercise's settings with its Watch settings changed from the defaults.
    case exerciseSettings = "exercise-settings"
    /// An exercise's settings with the Default Rest wheels open on an exercise's own rest.
    case restPicker = "rest-picker"
    /// Settings → Progression Steps with a step no preset fits, and the sheet to type one.
    case customStep = "custom-step"
    /// The History tab.
    case history
    /// The History tab with no finished workout (one still running on the Watch is hidden).
    case historyEmpty = "history-empty"
    /// The History tab searching for an exercise name.
    case historySearch = "history-search"
    /// The latest workout: warm-up, PRs, rest times, a swapped-in and a skipped exercise.
    case sessionDetail = "session-detail"
    /// The latest workout's editor.
    case sessionEdit = "session-edit"
    /// The latest workout's editor asking to confirm deleting it.
    case sessionDeleteConfirm = "session-delete-confirm"
    /// Bench Press's chart (estimated 1RM), records and log.
    case exerciseHistory = "exercise-history"
    /// Bench Press's chart showing volume.
    case exerciseHistoryVolume = "exercise-history-volume"
    /// Bench Press's most reps at each weight.
    case repsByWeight = "reps-by-weight"
    /// An exercise that was never done.
    case exerciseHistoryEmpty = "exercise-history-empty"
    /// Import: choose a file, and the apps it reads.
    case importStart = "import-start"
    /// Import: how to export from Hevy.
    case importHow = "import-how"
    /// Import: a Hevy export read, its unit taken from the header.
    case importDetected = "import-detected"
    /// Import: an old Strong export, asking for the unit.
    case importUnit = "import-unit"
    /// Import: numeric dates that could be day-first or month-first.
    case importDateOrder = "import-date-order"
    /// Import: another app's CSV, matching its columns.
    case importColumns = "import-columns"
    /// Import: the names to check (a likely match, other equipment, a custom exercise).
    case importMatch = "import-match"
    /// Import: every name with what it becomes.
    case importMatchAll = "import-match-all"
    /// Import: workouts being saved.
    case importProgress = "import-progress"
    /// Import: done, with workouts skipped, rows not read and routine suggestions.
    case importDone = "import-done"
    /// Import: the rows that were not read.
    case importRowsNotRead = "import-rows-not-read"
    /// History right after an import.
    case historyImported = "history-imported"
}

/// A control the demo harness shows open, beyond what navigation alone can reach.
enum DemoReveal: Equatable {
    /// The exercise settings' Default Rest wheels.
    case restPicker
    /// The custom step sheet for this equipment's default step.
    case customStep(Equipment)
    /// The session editor.
    case sessionEdit
    /// The session editor with its delete confirmation.
    case sessionDeleteConfirmation
    /// The exercise detail showing this chart.
    case exerciseMetric(ProgressMetric)
}

enum DemoHarness {
    private static let stateArgument = "-WholesetDemo"
    private static let unitArgument = "-WholesetDemoUnit"

    /// The state requested on the command line, if any.
    static func requestedState(arguments: [String] = ProcessInfo.processInfo.arguments) -> DemoState? {
        value(after: stateArgument, in: arguments).flatMap(DemoState.init(rawValue:))
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// Builds an in-memory app showing `state`.
    static func makeModel(for state: DemoState) -> AppModel? {
        guard let container = try? WholesetStore.makeContainer(inMemory: true) else { return nil }
        let context = container.mainContext
        // Pretend iCloud is on and an upload just finished, so Settings shows a real status.
        // A download has finished too: without one the library would wait for the 30 s
        // patience timer, leaving the demo with only the starter routines' exercises.
        let sync = SyncMonitor(mode: .cloudKit) { .available }
        sync.record(SyncEvent(id: UUID(), kind: .import, startDate: .now.addingTimeInterval(-135), endDate: .now.addingTimeInterval(-130), succeeded: true))
        sync.record(SyncEvent(id: UUID(), kind: .export, startDate: .now.addingTimeInterval(-125), endDate: .now.addingTimeInterval(-120), succeeded: true))
        let store = StoreCoordinator(container: container, sync: sync, policy: .manual)
        store.start()

        let unit = value(after: unitArgument, in: ProcessInfo.processInfo.arguments).flatMap(WeightUnit.init(rawValue:)) ?? .kg
        if let settings = try? AppSettings.current(in: context) {
            SettingsEditing.setUnit(unit, on: settings)
        }

        var ids = DemoIDs()
        if state != .planEmpty {
            do {
                ids = try addSampleData(in: context)
                if state == .historyEmpty {
                    try addRunningWorkout(in: context)
                } else {
                    ids.history = try DemoHistory(unit: unit).add(in: context)
                }
            } catch {
                assertionFailure("Demo setup failed: \(error)")
            }
        }
        context.saveLogged()

        let suite = "wholeset.demo"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)

        let navigation = AppNavigation()
        var onboarding: OnboardingStep?
        switch state {
        case .welcome: onboarding = .welcome
        case .units: onboarding = .units
        case .health: onboarding = .health
        case .plan, .planEmpty: break
        case .routineEditor:
            navigation.planSheet = ids.push.map { .editRoutine($0) }
        case .exercisePicker:
            navigation.planSheet = ids.push.map { .editRoutine($0, showsPicker: true) }
        case .exercises:
            navigation.tab = .exercises
        case .exerciseDetail, .exerciseHistory:
            navigation.tab = .exercises
            navigation.exercisePath = ids.bench.map { [.exercise($0)] } ?? []
        case .exerciseHistoryVolume:
            navigation.tab = .exercises
            navigation.exercisePath = ids.bench.map { [.exercise($0)] } ?? []
            navigation.demoReveal = .exerciseMetric(.volume)
        case .repsByWeight:
            navigation.tab = .exercises
            navigation.exercisePath = ids.bench.map { [.exercise($0), .repsByWeight($0)] } ?? []
        case .exerciseHistoryEmpty:
            navigation.tab = .exercises
            navigation.exercisePath = ids.history.neverDone.map { [.exercise($0)] } ?? []
        case .settings:
            navigation.tab = .settings
        case .progressionSteps:
            navigation.tab = .settings
            navigation.settingsPath = [.progressionSteps]
            if let settings = try? AppSettings.current(in: context) {
                SettingsEditing.setProgressionStep(kilograms: unit.kilograms(fromValue: unit == .kg ? 1 : 2.5), for: .dumbbell, on: settings)
            }
        case .exerciseSettings:
            navigation.tab = .exercises
            navigation.exercisePath = ids.bench.map { [.exercise($0), .exerciseSettings($0)] } ?? []
            if let bench = exercise(ids.bench, in: context) {
                ExerciseEditing.setProgressionStep(kilograms: unit.kilograms(fromValue: unit == .kg ? 1.25 : 2.5), on: bench)
                ExerciseEditing.setDefaultRest(150, on: bench)
            }
        case .restPicker:
            navigation.tab = .exercises
            navigation.exercisePath = ids.bench.map { [.exercise($0), .exerciseSettings($0)] } ?? []
            navigation.demoReveal = .restPicker
            if let bench = exercise(ids.bench, in: context) {
                ExerciseEditing.setDefaultRest(105, on: bench)
            }
        case .customStep:
            navigation.tab = .settings
            navigation.settingsPath = [.progressionSteps]
            navigation.demoReveal = .customStep(.dumbbell)
            if let settings = try? AppSettings.current(in: context) {
                // Neither 3.75 kg nor 7.5 lb is a preset, so the picker lists it on its own.
                SettingsEditing.setProgressionStep(kilograms: unit.kilograms(fromValue: unit == .kg ? 3.75 : 7.5), for: .dumbbell, on: settings)
            }
        case .history, .historyEmpty:
            navigation.tab = .history
        case .historySearch:
            navigation.tab = .history
            navigation.historySearch = "Squat"
        case .sessionDetail:
            navigation.tab = .history
            navigation.historyPath = ids.history.latestPush.map { [.session($0)] } ?? []
        case .sessionEdit:
            navigation.tab = .history
            navigation.historyPath = ids.history.latestPush.map { [.session($0)] } ?? []
            navigation.demoReveal = .sessionEdit
        case .sessionDeleteConfirm:
            navigation.tab = .history
            navigation.historyPath = ids.history.latestPush.map { [.session($0)] } ?? []
            navigation.demoReveal = .sessionDeleteConfirmation
        case .importStart, .importHow, .importDetected, .importUnit, .importDateOrder, .importColumns,
             .importMatch, .importMatchAll, .importProgress, .importDone, .importRowsNotRead:
            navigation.tab = .settings
        case .historyImported:
            navigation.tab = .history
        }
        context.saveLogged()
        let model = AppModel(
            container: container,
            store: store,
            navigation: navigation,
            defaults: defaults,
            showsOnboarding: onboarding != nil,
            onboardingStep: onboarding ?? .welcome
        )
        if state.rawValue.hasPrefix("import-") || state == .historyImported {
            let flow = ImportFlowModel(container: container, history: model.history, unit: unit)
            navigation.importFlow = flow
            Task {
                await DemoImportDriver.drive(flow, to: state, container: container, navigation: navigation)
            }
        }
        return model
    }

    private struct DemoIDs {
        var push: UUID?
        var bench: UUID?
        var history = DemoHistory.IDs()
    }

    private static func exercise(_ id: UUID?, in context: ModelContext) -> Exercise? {
        guard let id else { return nil }
        return try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })).first
    }

    /// Starter routines, one routine of the user's own, a weekly plan and some alternatives.
    private static func addSampleData(in context: ModelContext) throws -> DemoIDs {
        try StarterRoutines.seed(in: context)
        let exercises = Dictionary(try context.fetch(FetchDescriptor<Exercise>()).map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let routines = Dictionary(try context.fetch(FetchDescriptor<Routine>()).map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

        var travel = RoutineDraft(name: "Upper (Travel)")
        travel.addExercises(["Dumbbell Bench Press", "Dumbbell Row", "Dumbbell Shoulder Press", "Hammer Curl"].compactMap { name in
            exercises[name].map { (id: $0.id, name: $0.name) }
        })
        try travel.apply(in: context)

        if let push = routines["Push"] {
            RoutineEditing.setNotes("Pause for a second at the chest on bench.", on: push)
        }
        if let bench = exercises["Bench Press"] {
            RoutineEditing.setAlternatives(
                ["Dumbbell Bench Press", "Machine Chest Press"].compactMap { exercises[$0] },
                for: bench
            )
        }
        // Monday Push, Tuesday Pull, Wednesday rest, Thursday Legs, Friday Push, Saturday Pull, Sunday rest.
        let plan: [(Int, String?)] = [(2, "Push"), (3, "Pull"), (4, nil), (5, "Legs"), (6, "Push"), (7, "Pull"), (1, nil)]
        for (weekday, name) in plan {
            try WeekPlan.set(name.flatMap { routines[$0] }, on: weekday, in: context)
        }
        return DemoIDs(push: routines["Push"]?.id, bench: exercises["Bench Press"]?.id)
    }

    /// A workout still running on the Watch: it must never show in History.
    private static func addRunningWorkout(in context: ModelContext) throws {
        let session = Session(name: "Push", startedAt: .now.addingTimeInterval(-1_200))
        context.insert(session)
        if let bench = try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == "Bench Press" })).first {
            let entry = SessionExercise(order: 0, repLow: 6, repHigh: 10)
            context.insert(entry)
            entry.session = session
            entry.exercise = bench
            let set = SetLog(order: 0, weightKg: 60, reps: 10)
            set.completedAt = .now.addingTimeInterval(-900)
            context.insert(set)
            set.entry = entry
        }
    }
}

/// About fourteen months of Push / Legs / Pull workouts every six days, getting stronger
/// over time, with one imported workout, so every history screen shows real values.
private struct DemoHistory {
    struct IDs {
        /// The newest workout: Push with a warm-up, PRs, a swap and a skip.
        var latestPush: UUID?
        /// A library exercise with no history.
        var neverDone: UUID?
    }

    /// How an exercise progresses over the demo history.
    private struct Plan {
        let baseKg: Double?
        let gainKg: Double
        let stepKg: Double
    }

    private static let plans: [String: Plan] = [
        "Bench Press": Plan(baseKg: 50, gainKg: 15, stepKg: 2.5),
        "Overhead Press": Plan(baseKg: 30, gainKg: 10, stepKg: 2.5),
        "Incline Dumbbell Press": Plan(baseKg: 18, gainKg: 8, stepKg: 2),
        "Lateral Raise": Plan(baseKg: 8, gainKg: 4, stepKg: 1),
        "Triceps Pushdown": Plan(baseKg: 20, gainKg: 12.5, stepKg: 2.5),
        "Pull-up": Plan(baseKg: nil, gainKg: 0, stepKg: 0),
        "Barbell Row": Plan(baseKg: 45, gainKg: 15, stepKg: 2.5),
        "Lat Pulldown": Plan(baseKg: 40, gainKg: 15, stepKg: 5),
        "Face Pull": Plan(baseKg: 15, gainKg: 7.5, stepKg: 2.5),
        "Dumbbell Curl": Plan(baseKg: 10, gainKg: 4, stepKg: 2),
        "Squat": Plan(baseKg: 70, gainKg: 30, stepKg: 2.5),
        "Romanian Deadlift": Plan(baseKg: 60, gainKg: 25, stepKg: 2.5),
        "Leg Press": Plan(baseKg: 100, gainKg: 60, stepKg: 5),
        "Leg Curl": Plan(baseKg: 30, gainKg: 15, stepKg: 5),
        "Standing Calf Raise": Plan(baseKg: 40, gainKg: 20, stepKg: 5),
        "Dumbbell Shoulder Press": Plan(baseKg: 16, gainKg: 6, stepKg: 2),
        "Hammer Curl": Plan(baseKg: 12, gainKg: 4, stepKg: 2),
    ]

    let unit: WeightUnit
    private let sessionCount = 72
    private let calendar = Calendar.current

    func add(in context: ModelContext) throws -> IDs {
        let routines = Dictionary(try context.fetch(FetchDescriptor<Routine>()).map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let exercises = Dictionary(try context.fetch(FetchDescriptor<Exercise>()).map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var ids = IDs()
        let rotation = ["Push", "Legs", "Pull"]
        for age in 0..<sessionCount {
            guard let routine = routines[rotation[age % rotation.count]] else { continue }
            let start = startDate(daysAgo: 1 + 6 * age)
            let progress = Double(sessionCount - 1 - age) / Double(sessionCount - 1)
            if age == 65 {
                addImported(routine: routine, start: start, progress: progress, in: context)
                continue
            }
            let session = addSession(routine: routine, start: start, age: age, progress: progress, exercises: exercises, in: context)
            if age == 0 { ids.latestPush = session.id }
        }
        ids.neverDone = exercises["Arnold Press"]?.id
        return ids
    }

    private func startDate(daysAgo: Int) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: .now)) ?? .now
        return calendar.date(bySettingHour: 18, minute: 4, second: 0, of: day) ?? day
    }

    /// A weight in kilograms on the display unit's plates: whole 2.5 kg or 5 lb steps.
    private func plated(_ kilograms: Double) -> Double {
        switch unit {
        case .kg: kilograms
        case .lb: WeightUnit.lb.kilograms(fromValue: (WeightUnit.lb.value(fromKilograms: kilograms) / 5).rounded() * 5)
        }
    }

    private func weight(for name: String, progress: Double, age: Int) -> Double? {
        guard let plan = Self.plans[name], let base = plan.baseKg else { return nil }
        var steps = (progress * plan.gainKg / plan.stepKg).rounded(.down)
        // Every seventh workout of a routine is a lighter week.
        if (age / 3) % 7 == 3 { steps = max(0, steps - 2) }
        return plated(base + steps * plan.stepKg)
    }

    @discardableResult
    private func addSession(
        routine: Routine,
        start: Date,
        age: Int,
        progress: Double,
        exercises: [String: Exercise],
        in context: ModelContext
    ) -> Session {
        let session = Session(name: routine.name, startedAt: start, source: .watch)
        context.insert(session)
        session.routine = routine
        session.avgHR = Double(118 + age % 15)
        session.maxHR = Double(150 + age % 17)
        session.activeKcal = Double(320 + (age * 37) % 140)

        var clock = start.addingTimeInterval(240)
        var order = 0
        func addEntry(_ exercise: Exercise, item: RoutineItem?, repLow: Int, repHigh: Int) -> SessionExercise {
            let entry = SessionExercise(order: order, repLow: repLow, repHigh: repHigh)
            context.insert(entry)
            entry.session = session
            entry.exercise = exercise
            entry.routineItemID = item?.id
            order += 1
            return entry
        }
        func logSet(_ entry: SessionExercise, order: Int, weightKg: Double?, reps: Int, warmup: Bool = false, rest: Int) {
            let set = SetLog(order: order, weightKg: weightKg, reps: reps, isWarmup: warmup)
            clock = clock.addingTimeInterval(Double(rest))
            set.completedAt = clock
            context.insert(set)
            set.entry = entry
        }

        for (index, item) in routine.sortedItems.enumerated() {
            guard let exercise = item.exercise else { continue }
            let entry = addEntry(exercise, item: item, repLow: item.repLow, repHigh: item.repHigh)
            let rest = item.restSeconds ?? 90
            let weight = weight(for: exercise.name, progress: progress, age: age)
            let topReps = exercise.equipment == .bodyweight
                ? 5 + Int((progress * 5).rounded(.down))
                : item.repHigh - (age / 3) % 3
            var setOrder = 0
            if index == 0, let weight {
                logSet(entry, order: setOrder, weightKg: plated((weight * 0.6 / 2.5).rounded() * 2.5), reps: 10, warmup: true, rest: 0)
                setOrder += 1
            }
            let isLatestPush = age == 0
            if isLatestPush, index == 4 {
                // Skipped today: its sets stay planned.
                entry.isSkipped = true
                for planned in 0..<item.targetSets {
                    let set = SetLog(order: planned, weightKg: weight, reps: item.repLow)
                    context.insert(set)
                    set.entry = entry
                }
                continue
            }
            for number in 0..<item.targetSets {
                if isLatestPush, index == 1, number == 1, let replacement = exercises["Dumbbell Shoulder Press"] {
                    // Swapped after one set: the rest are done with dumbbells.
                    let swapped = addEntry(replacement, item: item, repLow: item.repLow, repHigh: item.repHigh)
                    let dumbbells = self.weight(for: replacement.name, progress: progress, age: age)
                    for later in number..<item.targetSets {
                        logSet(swapped, order: later - number, weightKg: dumbbells, reps: item.repHigh - later, rest: rest + 20)
                    }
                    break
                }
                let reps = max(item.repLow, topReps - number)
                let gap = number == 0 && setOrder == 0 ? 180 : rest + ((age * 7 + number * 13) % 31) - 20
                logSet(entry, order: setOrder, weightKg: weight, reps: reps, rest: gap)
                setOrder += 1
            }
            clock = clock.addingTimeInterval(120)
        }
        if age == 3, let hammer = exercises["Hammer Curl"] {
            // Added during that workout.
            let entry = addEntry(hammer, item: nil, repLow: 8, repHigh: 12)
            for number in 0..<2 {
                logSet(entry, order: number, weightKg: weight(for: hammer.name, progress: progress, age: age), reps: 12 - number, rest: 75)
            }
        }
        session.endedAt = clock.addingTimeInterval(180)
        if age == 0 {
            session.notes = "Paused every bench rep. Shoulder felt tight on overhead press, so I finished with dumbbells."
            session.avgHR = 128
            session.maxHR = 161
            session.activeKcal = 412
        }
        return session
    }

    /// A workout imported from another app: same timestamp on every set, no heart rate.
    private func addImported(routine: Routine, start: Date, progress: Double, in context: ModelContext) {
        let session = Session(name: "\(routine.name) Day", startedAt: start, source: .importHevy)
        session.endedAt = start.addingTimeInterval(50 * 60)
        session.externalKey = "\(start.timeIntervalSince1970)|\(routine.name) Day"
        context.insert(session)
        for (order, item) in routine.sortedItems.enumerated() {
            guard let exercise = item.exercise else { continue }
            let entry = SessionExercise(order: order)
            context.insert(entry)
            entry.session = session
            entry.exercise = exercise
            let weight = weight(for: exercise.name, progress: progress, age: 65)
            for number in 0..<item.targetSets {
                let set = SetLog(order: number, weightKg: weight, reps: max(item.repLow, item.repHigh - number))
                set.completedAt = start
                context.insert(set)
                set.entry = entry
            }
        }
    }
}
#endif
