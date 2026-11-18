// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import Foundation
import SwiftData
import WholesetKit

/// Screens the DEBUG demo harness can open straight into, for screenshots.
///
/// Launch with `-WholesetDemo <state>`, optionally `-WholesetDemoUnit lb`. The app then
/// uses an in-memory store with the library, the starter routines, a weekly plan and a
/// pretend iCloud status. Nothing of this is compiled into Release builds.
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
    /// An exercise's details with its Watch settings changed from the defaults.
    case exerciseSettings = "exercise-settings"
    /// An exercise's details with the Default Rest wheels open on an exercise's own rest.
    case restPicker = "rest-picker"
    /// Settings → Progression Steps with a step no preset fits, and the sheet to type one.
    case customStep = "custom-step"
}

/// A control the demo harness shows open, beyond what navigation alone can reach.
enum DemoReveal: Equatable {
    /// The exercise detail's Default Rest wheels.
    case restPicker
    /// The custom step sheet for this equipment's default step.
    case customStep(Equipment)
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
        let sync = SyncMonitor(mode: .cloudKit) { .available }
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
        case .exerciseDetail:
            navigation.tab = .exercises
            navigation.exercisePath = ids.bench.map { [$0] } ?? []
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
            navigation.exercisePath = ids.bench.map { [$0] } ?? []
            if let id = ids.bench, let bench = try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })).first {
                ExerciseEditing.setProgressionStep(kilograms: unit.kilograms(fromValue: unit == .kg ? 1.25 : 2.5), on: bench)
                ExerciseEditing.setDefaultRest(150, on: bench)
            }
        case .restPicker:
            navigation.tab = .exercises
            navigation.exercisePath = ids.bench.map { [$0] } ?? []
            navigation.demoReveal = .restPicker
            if let id = ids.bench, let bench = try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })).first {
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
        }
        context.saveLogged()
        return AppModel(
            container: container,
            store: store,
            navigation: navigation,
            defaults: defaults,
            showsOnboarding: onboarding != nil,
            onboardingStep: onboarding ?? .welcome
        )
    }

    private struct DemoIDs {
        var push: UUID?
        var bench: UUID?
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
}
#endif
