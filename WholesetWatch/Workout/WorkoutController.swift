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
    private(set) var recoveryGraceExpired = false
    /// The visible workout page.
    var page: WorkoutPage = .exercise
    /// The sheet over the workout pages, if any.
    var sheet: WorkoutSheet?
    /// A save failure to show the user.
    var errorMessage: String?
    /// A tile to select when the exercise page appears (DEBUG demos).
    var initialTileSelection: ValueTile?

    let health: any WorkoutSessionManaging
    let alerts: RestAlertScheduler

    @ObservationIgnored let context: ModelContext
    @ObservationIgnored private let stateStore: ActiveWorkoutStateStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var pendingRoutine: Routine?
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
        case .home, .summary: engine != nil
        case .preparing, .countdown, .active, .restored: true
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
        case .home, .summary: break
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
        guard phase == .home, engine == nil else { return }
        loadSettings()
        pendingRoutine = routine
        let name = routine.name
        phase = .preparing(routineName: name)
        Task {
            await health.requestAuthorization()
            await alerts.requestAuthorization()
            guard case .preparing = phase, pendingRoutine === routine else { return }
            await health.prepare()
            guard case .preparing = phase, pendingRoutine === routine else {
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
            pendingRoutine = nil
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
        guard case .countdown(let info) = phase, !info.isFrozen, let routine = pendingRoutine else { return }
        pendingRoutine = nil
        do {
            let engine = try WorkoutEngine.start(
                routine: routine,
                in: context,
                defaultRestSeconds: defaultRestSeconds,
                now: now
            )
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
            health: recording ? .saving : .notSaved
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

    /// Leaves the summary for the home screen.
    func closeSummary() {
        guard case .summary = phase else { return }
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
