// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation
import os
import SwiftData
import WatchKit
import WholesetKit

/// The two horizontal pages of a running workout.
enum WorkoutPage: Hashable {
    case exercise
    case stats
}

/// Sheets shown over the workout pages.
enum WorkoutSheet: String, Identifiable {
    case menu
    case endConfirm

    var id: String { rawValue }
}

/// What an exercise list in the menu is for.
enum ExercisePickPurpose: Hashable {
    /// Add the picked exercise at the end of the workout.
    case add
    /// Replace the current exercise with the picked one.
    case swap
}

/// Screens pushed inside the ••• menu.
enum MenuDestination: Hashable {
    /// The current exercise's alternatives, then "Other…".
    case swap
    /// Recent exercises, then the library by muscle group.
    case exercises(ExercisePickPurpose)
    /// The library exercises of one muscle group.
    case muscleGroup(MuscleGroup, ExercisePickPurpose)
    /// Every exercise of the workout with its progress; `editing` starts in Edit mode.
    case allExercises(editing: Bool)
}

/// What to offer once the summary is closed.
struct RoutinePrompt: Equatable {
    enum Kind: Equatable {
        /// Update the session's routine with what changed.
        case update(RoutineUpdateProposal)
        /// Make a routine out of a workout that had none.
        case saveAsRoutine(suggestedName: String)
    }

    let sessionID: UUID
    let kind: Kind
}

/// The two editable values on the exercise page.
enum ValueTile: Hashable {
    case weight
    case reps
}

/// The 3-2-1 before a workout starts.
struct CountdownInfo: Equatable {
    let routineName: String
    let endsAt: Date
    /// DEBUG demos freeze the countdown so it can be captured.
    let isFrozen: Bool
}

/// Whether the finished workout reached Apple Health.
enum HealthSaveStatus: Equatable {
    case saving
    case saved
    case notSaved
}

/// What the summary screen shows.
struct WorkoutSummaryInfo: Equatable {
    let sessionID: UUID
    let routineName: String
    let duration: TimeInterval
    let workingSets: Int
    let volumeKg: Double
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var activeKilocalories: Double?
    var health: HealthSaveStatus
    /// Offered after the summary's Done, computed when the workout ended.
    var followUp: RoutinePrompt?
}

/// How the Health side looks on the "Workout restored" screen.
enum RestoredHealthStatus: Equatable {
    case reconnecting
    case recording
    case notRecording
}

/// Coordinates a workout on the Watch: the engine (sets, saved at once), the Health
/// session, the rest timer and its single alert, and the scratch state that lets a
/// relaunch resume exactly where the user was.
///
/// Main-actor isolated, like the `ModelContext` it uses.
@Observable
final class WorkoutController {
    /// The app-level screen.
    enum Phase: Equatable {
        case home
        case preparing(routineName: String)
        case countdown(CountdownInfo)
        case active
        case restored
        case summary(WorkoutSummaryInfo)
        /// "Update <routine>?" or "Save as routine?" after the summary.
        case routinePrompt(RoutinePrompt)
    }

    private(set) var phase: Phase = .home
    private(set) var engine: WorkoutEngine?
    private(set) var clock: WorkoutClock?
    private(set) var rest: RestTimer?
    private(set) var unit: WeightUnit = .kg
    /// How the Crown edits the weight tile (from the synced settings).
    private(set) var weightCrown: CrownProfile = .weight(.normal)
    /// How the Crown edits the reps tile (from the synced settings).
    private(set) var repsCrown: CrownProfile = .reps(.normal)
    /// Unit and per-equipment steps for the progression chip (from the synced settings).
    private(set) var progression = ProgressionSettings()
    private(set) var recoveryGraceExpired = false
    /// The visible workout page.
    var page: WorkoutPage = .exercise
    /// The sheet over the workout pages, if any.
    var sheet: WorkoutSheet?
    /// The screens pushed inside the ••• menu.
    var menuPath: [MenuDestination] = []
    /// A save failure to show the user.
    var errorMessage: String?
    /// A tile to select when the exercise page appears (DEBUG demos).
    var initialTileSelection: ValueTile?

    let health: any WorkoutSessionManaging
    let alerts: RestAlertScheduler

    @ObservationIgnored let context: ModelContext
    @ObservationIgnored private let stateStore: ActiveWorkoutStateStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var pendingStart: PendingStart?
    @ObservationIgnored private var restTask: Task<Void, Never>?
    @ObservationIgnored private var isSceneActive = true
    @ObservationIgnored private var defaultRestSeconds = RestTimer.fallbackSeconds
    /// Whether a weight or reps tile is being edited; settings are not reloaded meanwhile.
    @ObservationIgnored private var isEditingTile = false
    @ObservationIgnored private var settingsReloadPending = false

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.wholeset.watchkitapp", category: "Workout")

    /// Creates the controller and, unless `bootstrap` is `false`, restores a workout left
    /// running by a crash or reboot. Seeding is the `StoreCoordinator`'s job.
    init(
        context: ModelContext,
        health: any WorkoutSessionManaging,
        alerts: RestAlertScheduler,
        stateStore: ActiveWorkoutStateStore = ActiveWorkoutStateStore(),
        now: @escaping () -> Date = Date.init,
        bootstrap: Bool = true
    ) {
        self.context = context
        self.health = health
        self.alerts = alerts
        self.stateStore = stateStore
        self.now = now
        loadSettings()
        if bootstrap {
            self.bootstrap()
        }
    }

    /// The display scale for weights.
    var scale: WeightScale { WeightScale(unit: unit) }

    /// Whether the workout clock (and the Health session) is paused.
    var isPaused: Bool { clock?.isPaused ?? false }

    /// Whether a workout is starting, running or waiting to be restored.
    var isWorkoutRunning: Bool {
        switch phase {
        case .home, .summary, .routinePrompt: engine != nil
        case .preparing, .countdown, .active, .restored: true
        }
    }

    /// What a start waiting for permissions or the countdown will create.
    private enum PendingStart {
        case routine(Routine)
        case empty

        func isSame(as other: PendingStart?) -> Bool {
            switch (self, other) {
            case let (.routine(lhs), .routine(rhs)?): lhs === rhs
            case (.empty, .empty?): true
            default: false
            }
        }
    }

    // MARK: - Launch

    private func bootstrap() {
        do {
            if let session = try WorkoutRecovery.resolveInProgressSession(in: context) {
                restore(session)
            }
        } catch {
            logger.error("Could not look for an unfinished workout: \(error, privacy: .public)")
        }
        Task {
            await alerts.refreshAuthorization()
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.recoveryGraceExpired = true
        }
    }

    private func loadSettings() {
        do {
            let settings = try AppSettings.current(in: context)
            if unit != settings.unit { unit = settings.unit }
            let weight = CrownProfile.weight(settings.weightCrownSensitivity)
            if weightCrown != weight { weightCrown = weight }
            let reps = CrownProfile.reps(settings.repsCrownSensitivity)
            if repsCrown != reps { repsCrown = reps }
            defaultRestSeconds = settings.defaultRestSeconds
            let progression = ProgressionSettings(settings)
            if self.progression != progression { self.progression = progression }
            if let engine, engine.progressionSettings != progression { engine.progressionSettings = progression }
        } catch {
            logger.error("Could not read settings: \(error, privacy: .public)")
        }
    }

    /// Reads the settings again, for example after changes arrived from iCloud. While a
    /// tile is being edited the reload waits until it is released, so units and Crown
    /// speed never change under a turn.
    func refreshSettings() {
        guard !isEditingTile else {
            settingsReloadPending = true
            return
        }
        settingsReloadPending = false
        loadSettings()
    }

    /// Called by the tile editor when a tile is selected or released.
    func tileEditingChanged(isEditing: Bool) {
        isEditingTile = isEditing
        if !isEditing, settingsReloadPending {
            refreshSettings()
        }
    }

    private func restore(_ session: Session) {
        let stored = stateStore.load(sessionID: session.id)
        engine = WorkoutEngine(
            resuming: session,
            in: context,
            defaultRestSeconds: defaultRestSeconds,
            progressionSettings: progression,
            currentEntryID: stored?.currentEntryID,
            now: now
        )
        clock = stored?.clock ?? WorkoutClock(startedAt: session.startedAt)
        rest = stored?.rest
        page = .exercise
        sheet = nil
        phase = .restored
        logger.info("Restored an unfinished workout")
    }

    /// The Health status for the "Workout restored" screen. The system asks the app to
    /// recover a running Health workout right after launch; if it hasn't within a few
    /// seconds, there is none (for example after a reboot).
    var restoredHealthStatus: RestoredHealthStatus {
        switch health.recoveryStatus {
        case .recovered: .recording
        case .recovering: .reconnecting
        case .failed: .notRecording
        case .notAttempted: recoveryGraceExpired ? .notRecording : .reconnecting
        }
    }

    /// Called after the system asked the app to recover a running Health workout.
    ///
    /// If a session is being restored, the Health workout simply carries on with it. If
    /// none is (the user had already ended or discarded it when the app stopped), the
    /// Health workout is finished and linked to its ended session, or discarded if that
    /// session no longer exists.
    func healthRecoveryFinished() {
        guard health.recoveryStatus == .recovered, engine == nil else { return }
        switch phase {
        case .home, .summary, .routinePrompt: break
        case .preparing, .countdown, .active, .restored: return
        }
        let ended = health.recoveredSessionID.flatMap(session(withID:)).flatMap { $0.endedAt == nil ? nil : $0 }
        Task {
            if let ended, let endedAt = ended.endedAt {
                let result = await health.end(at: endedAt)
                if let result {
                    ended.apply(result)
                    saveQuietly()
                }
                // "End and save" may have been tapped before recovery finished.
                if case .summary(var info) = phase, info.sessionID == ended.id {
                    info.averageHeartRate = result?.averageHeartRate ?? info.averageHeartRate
                    info.maxHeartRate = result?.maxHeartRate ?? info.maxHeartRate
                    info.activeKilocalories = result?.activeKilocalories ?? info.activeKilocalories
                    if result?.workoutID != nil { info.health = .saved }
                    phase = .summary(info)
                }
            } else {
                await health.discard()
            }
        }
    }

    private func session(withID id: UUID) -> Session? {
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    // MARK: - Starting

    /// Asks for permissions (first time only), prepares the Health session, then counts down.
    func start(_ routine: Routine) {
        begin(.routine(routine), name: routine.name)
    }

    /// Starts a workout without a routine; exercises are added as it goes.
    func startEmpty() {
        begin(.empty, name: WorkoutEngine.emptyWorkoutName)
    }

    private func begin(_ start: PendingStart, name: String) {
        guard phase == .home, engine == nil else { return }
        loadSettings()
        pendingStart = start
        phase = .preparing(routineName: name)
        Task {
            await health.requestAuthorization()
            await alerts.requestAuthorization()
            guard case .preparing = phase, start.isSame(as: pendingStart) else { return }
            await health.prepare()
            guard case .preparing = phase, start.isSame(as: pendingStart) else {
                await health.discard()
                return
            }
            phase = .countdown(CountdownInfo(routineName: name, endsAt: now().addingTimeInterval(3), isFrozen: false))
        }
    }

    /// Abandons a start that is waiting for permissions or the countdown.
    func cancelStart() {
        switch phase {
        case .preparing, .countdown:
            pendingStart = nil
            phase = .home
            Task {
                await health.discard()
            }
        default:
            return
        }
    }

    /// Ends the countdown (on time or when tapped) and starts the workout.
    func countdownFinished() {
        guard case .countdown(let info) = phase, !info.isFrozen, let start = pendingStart else { return }
        pendingStart = nil
        do {
            let engine: WorkoutEngine
            switch start {
            case .routine(let routine):
                engine = try WorkoutEngine.start(
                    routine: routine,
                    in: context,
                    defaultRestSeconds: defaultRestSeconds,
                    progressionSettings: progression,
                    now: now
                )
            case .empty:
                engine = try WorkoutEngine.startEmpty(
                    in: context,
                    defaultRestSeconds: defaultRestSeconds,
                    progressionSettings: progression,
                    now: now
                )
            }
            let session = engine.session
            self.engine = engine
            clock = WorkoutClock(startedAt: session.startedAt)
            rest = nil
            page = .exercise
            sheet = nil
            persistState()
            phase = .active
            Haptics.play(.start)
            let metadata = [
                HealthKitMetadataKey.routineName: session.name,
                HealthKitMetadataKey.sessionID: session.id.uuidString,
            ]
            let startDate = session.startedAt
            Task {
                await health.start(at: startDate, metadata: metadata)
            }
        } catch {
            report(error)
            phase = .home
            Task {
                await health.discard()
            }
        }
    }

    // MARK: - Logging

    /// Selects the exercise at `index`.
    func selectEntry(at index: Int) {
        engine?.select(entryAt: index)
        persistState()
    }

    /// Sets the current set's weight (not saved until ``commitEdits()`` or logging).
    func setWeight(_ kilograms: Double?) {
        engine?.setCurrentWeight(kilograms)
    }

    /// Sets the current set's reps (not saved until ``commitEdits()`` or logging).
    func setReps(_ reps: Int?) {
        engine?.setCurrentReps(reps)
    }

    /// Saves edited values.
    func commitEdits() {
        perform { try $0.saveEdits() }
    }

    /// Logs the current set, saves it and starts the rest.
    func logSet() {
        guard let engine else { return }
        do {
            guard let logged = try engine.logCurrentSet() else { return }
            Haptics.play(.success)
            if let duration = logged.restDuration, duration > 0 {
                rest = RestTimer.start(duration: duration, now: now())
            } else {
                rest = nil
            }
            restChanged()
        } catch {
            report(error)
        }
    }

    /// Adds a set to the current exercise.
    func addSet() {
        perform { try $0.addSet() }
    }

    /// Removes the last set not yet logged from the current exercise.
    func removeSet() {
        perform { try $0.removeLastUnloggedSet() }
    }

    /// Toggles the warm-up flag of the current set.
    func toggleWarmup() {
        perform { try $0.toggleWarmupOnCurrentSet() }
    }

    /// Applies the progression chip's weight and reps to the remaining working sets.
    func applyProgressionHint() {
        perform { try $0.applyProgressionHint() }
    }

    // MARK: - Changing the workout

    /// Opens the ••• menu, optionally straight at `path`.
    func openMenu(at path: [MenuDestination] = []) {
        menuPath = path
        sheet = .menu
    }

    /// Replaces the current exercise (logged sets stay with the old one) and closes the menu.
    func swapCurrentExercise(to exercise: Exercise) {
        perform { try $0.swapCurrentExercise(to: exercise) }
        sheet = nil
    }

    /// Adds `exercise` at the end, shows it, and closes the menu.
    func addExercise(_ exercise: Exercise) {
        perform { try $0.addExercise(exercise) }
        page = .exercise
        sheet = nil
    }

    /// Skips or resumes `entry`. Skipping the exercise on screen also ends the rest.
    func setSkipped(_ isSkipped: Bool, for entry: SessionExercise) {
        guard let engine else { return }
        let wasCurrent = entry === engine.currentEntry
        perform { try $0.setSkipped(isSkipped, for: entry) }
        if isSkipped, wasCurrent, rest != nil {
            rest = nil
            restChanged()
        }
    }

    /// Moves the exercise at `index` one place up (`-1`) or down (`1`).
    func moveEntry(at index: Int, by offset: Int) {
        guard let engine, engine.entries.indices.contains(index),
              engine.entries.indices.contains(index + offset) else { return }
        // `onMove` offsets: moving down means inserting after the next element.
        let destination = offset > 0 ? index + offset + 1 : index + offset
        perform { try $0.moveEntries(fromOffsets: IndexSet(integer: index), toOffset: destination) }
    }

    /// Distinct exercises from the latest finished workouts, newest first.
    func recentExercises() -> [Exercise] {
        do {
            return try RecentExercises.recent(limit: 20, in: context)
        } catch {
            logger.error("Could not read recent exercises: \(error, privacy: .public)")
            return []
        }
    }

    /// The active library exercises of `group`, by name.
    func exercises(in group: MuscleGroup) -> [Exercise] {
        ExerciseCatalog.filtered(allExercises(), by: ExerciseCatalog.Filter(group: group))
    }

    /// The muscle groups that have at least one active exercise.
    func muscleGroups() -> [MuscleGroup] {
        let groups = Set(allExercises().filter { !$0.isArchived }.map { MuscleGroup($0.primaryMuscle) })
        return MuscleGroup.allCases.filter(groups.contains)
    }

    private func allExercises() -> [Exercise] {
        do {
            return try context.fetch(FetchDescriptor<Exercise>())
        } catch {
            logger.error("Could not read exercises: \(error, privacy: .public)")
            return []
        }
    }

    private func perform(_ action: (WorkoutEngine) throws -> Void) {
        guard let engine else { return }
        do {
            try action(engine)
            persistState()
        } catch {
            report(error)
        }
    }

    // MARK: - Rest

    /// Adds 30 seconds to the rest.
    func extendRest() {
        rest?.extend(now: now())
        restChanged()
    }

    /// Ends the rest now, without an alert.
    func skipRest() {
        rest = nil
        restChanged()
    }

    /// Re-arms the in-app end-of-rest task and the notification after any rest change.
    private func restChanged() {
        restTask?.cancel()
        restTask = nil
        if let timer = rest {
            let delay = timer.remaining(at: now())
            restTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.restDidEnd(timer)
            }
        }
        alerts.sync(restEnd: rest?.endDate, body: restAlertBody, now: now())
        persistState()
    }

    private func restDidEnd(_ timer: RestTimer) {
        guard rest == timer else { return }
        guard timer.isFinished(at: now()) else {
            restChanged()
            return
        }
        rest = nil
        restTask = nil
        // Exactly one alert: in the app when it is active, otherwise the pending
        // notification, which is left in place to fire. Without notification permission
        // the haptic is the only alert left, so it always plays.
        if isSceneActive || !alerts.isAuthorized {
            Haptics.play(.notification)
        }
        persistState()
    }

    private var restAlertBody: String {
        guard let engine, let entry = engine.currentEntry else { return "" }
        let name = entry.exercise?.name ?? ""
        if let number = engine.currentSetNumber {
            return String(localized: "\(name) · set \(number) of \(entry.sets?.count ?? 0)")
        }
        if let next = engine.nextUnfinishedEntry(after: entry) {
            return String(localized: "Next: \(next.exercise?.name ?? "")")
        }
        return name
    }

    /// Tracks whether the app is frontmost and active.
    func sceneDidChange(isActive: Bool) {
        isSceneActive = isActive
        // A rest that ended while the screen was off normally alerted through the
        // notification. Its trigger can fire up to a second after the rest's end; if the
        // app turns active in that gap, the request is cancelled below, so alert here.
        if isActive, alerts.isAuthorized,
           let restEnd = alerts.scheduledRestEnd, restEnd <= now(),
           let fireDate = alerts.pendingFireDate, fireDate > now() {
            Haptics.play(.notification)
        }
        alerts.setAppActive(isActive)
        if isActive, let rest, rest.isFinished(at: now()) {
            self.rest = nil
            restTask?.cancel()
            restTask = nil
            persistState()
        }
        if phase == .active {
            alerts.sync(restEnd: rest?.endDate, body: restAlertBody, now: now())
        }
    }

    // MARK: - Pause, end, discard

    /// Pauses or resumes the clock and the Health session.
    func togglePause() {
        guard var clock else { return }
        if clock.isPaused {
            clock.resume(at: now())
            health.resume()
        } else {
            clock.pause(at: now())
            health.pause()
        }
        self.clock = clock
        persistState()
    }

    /// Continues a workout restored after a relaunch.
    func continueRestored() {
        guard phase == .restored else { return }
        if let rest, rest.isFinished(at: now()) {
            self.rest = nil
        }
        phase = .active
        restChanged()
    }

    /// Ends the workout: saves the session, shows the summary, then saves the Health
    /// workout in the background and fills in its numbers.
    func endWorkout() {
        guard let engine, let clock else { return }
        let endDate = now()
        do {
            try engine.finish()
        } catch {
            report(error)
            return
        }
        clearActiveWorkout()
        Haptics.play(.stop)

        let totals = engine.totals
        let session = engine.session
        // Computed now: the engine is gone after End, and the session no longer changes.
        let followUp = routinePrompt(for: session)
        let recording = [.preparing, .running, .paused].contains(health.state)
        phase = .summary(WorkoutSummaryInfo(
            sessionID: session.id,
            routineName: session.name,
            duration: clock.elapsed(at: endDate),
            workingSets: totals.completedWorkingSets,
            volumeKg: totals.volumeKg,
            averageHeartRate: nil,
            maxHeartRate: nil,
            activeKilocalories: recording ? health.activeKilocalories : nil,
            health: recording ? .saving : .notSaved,
            followUp: followUp
        ))

        Task {
            let result = await health.end(at: endDate)
            if let result {
                session.apply(result)
                saveQuietly()
            }
            guard case .summary(var info) = phase, info.sessionID == session.id else { return }
            info.averageHeartRate = result?.averageHeartRate
            info.maxHeartRate = result?.maxHeartRate
            info.activeKilocalories = result?.activeKilocalories ?? info.activeKilocalories
            info.health = result?.workoutID == nil ? .notSaved : .saved
            phase = .summary(info)
        }
    }

    /// Deletes the workout and its sets, and throws the Health workout away.
    func discardWorkout() {
        guard let engine else { return }
        // Delete the session first: if the app stops before the Health side is thrown
        // away, the recovered Health workout finds no session and is discarded then.
        do {
            try engine.discard()
        } catch {
            report(error)
            return
        }
        clearActiveWorkout()
        phase = .home
        Task {
            await health.discard()
        }
    }

    /// Leaves the summary: for the routine prompt if there is one, else for the home screen.
    func closeSummary() {
        guard case .summary(let info) = phase else { return }
        phase = info.followUp.map(Phase.routinePrompt) ?? .home
    }

    /// The prompt to show after the summary of `session`, if any.
    private func routinePrompt(for session: Session) -> RoutinePrompt? {
        if let proposal = RoutineUpdate.proposal(for: session) {
            return RoutinePrompt(sessionID: session.id, kind: .update(proposal))
        }
        if RoutineUpdate.canSaveAsRoutine(session) {
            let name = RoutineUpdate.suggestedRoutineName(for: session)
            return RoutinePrompt(sessionID: session.id, kind: .saveAsRoutine(suggestedName: name))
        }
        return nil
    }

    /// Accepts the routine prompt: updates the routine, or saves the workout as a routine.
    /// The session is fetched again by `id`; nothing happens if it is gone.
    func acceptRoutinePrompt() {
        guard case .routinePrompt(let prompt) = phase else { return }
        if let session = session(withID: prompt.sessionID) {
            do {
                switch prompt.kind {
                case .update:
                    RoutineUpdate.apply(to: session, in: context, now: now())
                case .saveAsRoutine(let name):
                    try RoutineUpdate.saveAsRoutine(session, named: name, in: context, now: now())
                }
                try context.save()
            } catch {
                context.rollback()
                report(error)
            }
        }
        phase = .home
    }

    /// Declines the routine prompt; nothing changes.
    func declineRoutinePrompt() {
        guard case .routinePrompt = phase else { return }
        phase = .home
    }

    private func clearActiveWorkout() {
        restTask?.cancel()
        restTask = nil
        rest = nil
        alerts.sync(restEnd: nil, body: "", now: now())
        stateStore.clear()
        engine = nil
        clock = nil
        sheet = nil
        menuPath = []
        page = .exercise
    }

    // MARK: - Persistence

    private func persistState() {
        guard let engine, let clock else { return }
        stateStore.save(ActiveWorkoutState(
            sessionID: engine.session.id,
            clock: clock,
            rest: rest,
            currentEntryID: engine.currentEntry?.id
        ))
    }

    private func saveQuietly() {
        do {
            try context.save()
        } catch {
            logger.error("Could not save Health results: \(error, privacy: .public)")
        }
    }

    private func report(_ error: any Error) {
        logger.error("Workout save failed: \(error, privacy: .public)")
        errorMessage = String(localized: "Couldn't save. Try again.")
    }

    #if DEBUG
    /// Puts the controller straight into a running workout (DEBUG demos only).
    func installDemoWorkout(engine: WorkoutEngine, clock: WorkoutClock, rest: RestTimer?, phase: Phase) {
        self.engine = engine
        self.clock = clock
        self.rest = rest
        self.phase = phase
    }

    /// Shows an arbitrary phase (DEBUG demos only).
    func installDemoPhase(_ phase: Phase) {
        self.phase = phase
    }
    #endif
}
