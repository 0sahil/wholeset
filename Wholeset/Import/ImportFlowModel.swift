// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation
import os
import SwiftData
import WholesetKit

/// The state of one run of the import flow: the file, how it is read, what each exercise
/// name becomes, the write and its summary. Reading, parsing and writing run off the main
/// actor; the screens only show this state and call its actions.
@Observable
final class ImportFlowModel: Identifiable {
    /// Screens pushed over the first screen.
    enum Step: Hashable {
        case howTo(ImportFormat)
        case columns
        case detected
        case match
        case rowsNotRead
    }

    /// What the flow is busy with.
    enum Activity: Equatable {
        case idle
        case reading
        case parsing
        case writing(ImportWriteProgress)
    }

    /// Why a file cannot be imported, shown with a way back.
    nonisolated enum Problem: Error, Equatable, Identifiable {
        case couldNotOpen
        case tooLarge
        case notText
        case empty
        case noWorkouts(rowsNotRead: Int)
        case unreadableDates(sample: String)
        case writeFailed

        var id: String { String(describing: self) }
    }

    /// One distinct exercise name in the file and what it will become.
    struct MatchRow: Identifiable, Equatable {
        /// What the user chose instead of the matcher's result.
        enum Choice: Equatable {
            case exercise(ExerciseCandidate)
            case newCustom(name: String, equipment: Equipment)
        }

        let importedName: String
        let setCount: Int
        let found: ExerciseMatch
        var choice: Choice?

        var id: String { importedName }

        /// Whether the row is in the Check list: a likely match or a new custom exercise the
        /// user has not decided on.
        var needsLook: Bool { choice == nil && found.needsLook }

        /// What the import does with the name.
        var resolution: ExerciseResolution {
            switch choice {
            case .exercise(let candidate)?: .exercise(candidate.reference, remember: true)
            case let .newCustom(name, equipment)?: .newCustom(name: name, equipment: equipment)
            case nil: ExerciseResolution(found)
            }
        }
    }

    /// A routine suggestion with its switch.
    struct SuggestionChoice: Identifiable, Equatable {
        let suggestion: RoutineSuggestion
        var isOn: Bool
        var id: String { suggestion.id }
    }

    /// The most a file may weigh; real exports with 20,000 sets are around 2 MB.
    nonisolated static let maximumFileSize = 50 * 1_024 * 1_024

    let id = UUID()
    /// Screens pushed over the first one.
    var path: [Step] = []
    /// Whether the file picker is showing.
    var isPickingFile = false
    private(set) var activity: Activity = .idle
    var problem: Problem?
    /// The picked file's name.
    private(set) var fileName: String?
    private(set) var file: ImportFile?
    /// Columns of a generic file.
    var mapping: GenericMapping?
    /// The unit for files that do not say.
    var chosenUnit: WeightUnit
    /// The order of ambiguous numeric dates, once chosen.
    private(set) var dateOrder: DateOrder?
    /// A date from the file, when its order has to be chosen.
    private(set) var dateOrderSample: String?
    private(set) var result: ImportParseResult?
    private(set) var plan: ImportPlan?
    var matches: [MatchRow] = []
    /// Which list the match screen shows.
    var showsAllMatches = false
    /// Candidates for rematching (existing exercises and library entries).
    private(set) var candidates: [ExerciseCandidate] = []
    private(set) var summary: ImportSummary?
    private(set) var report: ImportWriteReport?
    var suggestions: [SuggestionChoice] = []

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let history: HistoryModel?
    @ObservationIgnored private let library: ExerciseLibrary
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private var work: Task<Void, Never>?
    /// Bumped by every new file and every parse; results of older ones are dropped, so a
    /// slow parse can never replace what a newer choice (unit, date order, file) produced.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.wholeset", category: "Import")

    /// Creates a flow.
    ///
    /// - Parameters:
    ///   - unit: The user's unit, used for files that do not name one.
    ///   - history: Paused while writing, so the index is rebuilt once.
    init(container: ModelContainer, history: HistoryModel?, unit: WeightUnit, library: ExerciseLibrary? = nil, timeZone: TimeZone = .current) {
        self.container = container
        self.history = history
        self.chosenUnit = unit
        self.library = library ?? (try? ExerciseLibrary.bundled()) ?? ExerciseLibrary(entries: [])
        self.timeZone = timeZone
    }

    // MARK: Derived

    /// The recognised app, once a file is read.
    var format: ImportFormat? { file?.layout.format }

    /// Whether the user picks the weight unit (the file does not say).
    var choosesUnit: Bool {
        guard let file else { return false }
        return file.weightUnitSource(options).isChosen
    }

    /// Rows of the Check list.
    var rowsToCheck: [MatchRow] { matches.filter(\.needsLook) }

    /// Whether the write is running.
    var isWriting: Bool {
        if case .writing = activity { return true }
        return false
    }

    private var options: ImportOptions {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return ImportOptions(weightUnit: chosenUnit, dateOrder: dateOrder, timeZone: timeZone, calendar: calendar, mapping: mapping)
    }

    // MARK: Reading

    /// Reads a file the user picked or opened in Wholeset.
    func open(_ url: URL) {
        work?.cancel()
        reset()
        activity = .reading
        fileName = url.lastPathComponent
        let current = generation
        work = Task {
            let loaded = await Self.readFile(at: url)
            guard current == generation else { return }
            switch loaded {
            case .success(let data):
                await load(data)
            case .failure(let problem):
                activity = .idle
                self.problem = problem
            }
        }
    }

    /// Reads bytes already in memory (demo states).
    func load(_ data: Data, fileName: String) async {
        reset()
        self.fileName = fileName
        await load(data)
    }

    private func load(_ data: Data) async {
        activity = .reading
        let current = generation
        do {
            let file = try await ImportFile.load(data)
            guard current == generation else { return }
            self.file = file
            if file.layout == .generic {
                mapping = GenericMapping.suggested(header: file.table.header, sampleRows: file.table.rows.prefix(50))
                activity = .idle
                path = [.columns]
            } else {
                await parse(showing: true)
            }
        } catch {
            guard current == generation else { return }
            activity = .idle
            problem = switch error {
            case .empty: .empty
            case .notText: .notText
            }
        }
    }

    /// Reads the rows again with the current unit, date order and columns.
    func parse(showing: Bool = false) async {
        guard let file else { return }
        generation += 1
        let current = generation
        activity = .parsing
        let outcome = await file.parseInBackground(options)
        guard current == generation else { return }
        activity = .idle
        switch outcome {
        case .parsed(let parsed):
            guard parsed.workoutCount > 0 else {
                result = nil
                problem = .noWorkouts(rowsNotRead: parsed.skippedRows.count)
                return
            }
            result = parsed
        case .needsDateOrder(let sample):
            // Shown with the sample and a picker on the preview, starting from the
            // region's order; nothing is imported until the user continues.
            dateOrderSample = sample
            dateOrder = DateOrder.local == .yearMonthDay ? .dayMonthYear : DateOrder.local
            await parse(showing: showing)
            return
        case .unreadableDates(let sample):
            result = nil
            problem = .unreadableDates(sample: sample)
            return
        case .needsColumnMapping:
            result = nil
            path = [.columns]
            return
        }
        if showing, path.last != .detected { path.append(.detected) }
    }

    /// Changes the unit for files without one and reads again.
    func setUnit(_ unit: WeightUnit) {
        guard unit != chosenUnit else { return }
        chosenUnit = unit
        work = Task { await parse() }
    }

    /// Changes the date order and reads again.
    func setDateOrder(_ order: DateOrder) {
        guard order != dateOrder else { return }
        dateOrder = order
        work = Task { await parse() }
    }

    /// Reads a generic file with its columns, then shows the preview.
    func previewColumns() {
        guard mapping?.isComplete == true else { return }
        dateOrder = nil
        dateOrderSample = nil
        work = Task { await parse(showing: true) }
    }

    // MARK: Matching

    /// Matches the file's exercise names against the store and shows them.
    func reviewExercises() {
        guard let result else { return }
        let context = ModelContext(container)
        do {
            let exercises = try context.fetch(FetchDescriptor<Exercise>())
            candidates = ExerciseCandidate.all(exercises: exercises, library: library)
            plan = ImportPlan(workouts: result.allWorkouts, existingKeys: try ImportWriter.existingKeys(in: context))
        } catch {
            logger.error("Reading exercises for matching failed: \(error, privacy: .public)")
            candidates = []
            plan = ImportPlan(workouts: result.allWorkouts, existingKeys: [])
        }
        let matcher = ExerciseMatcher(candidates: candidates)
        // Coming back to this screen keeps what the user already chose.
        let chosen = Dictionary(matches.map { ($0.importedName, $0.choice) }, uniquingKeysWith: { first, _ in first })
        matches = result.exerciseNames.map { name, sets in
            MatchRow(importedName: name, setCount: sets, found: matcher.match(name), choice: chosen[name] ?? nil)
        }
        path.append(.match)
    }

    /// Uses `candidate` for the row named `name`.
    func choose(_ candidate: ExerciseCandidate, for name: String) {
        guard let index = matches.firstIndex(where: { $0.importedName == name }) else { return }
        matches[index].choice = .exercise(candidate)
    }

    /// Makes the row named `name` a new custom exercise.
    func chooseCustom(name: String, equipment: Equipment, for importedName: String) {
        guard let index = matches.firstIndex(where: { $0.importedName == importedName }) else { return }
        matches[index].choice = .newCustom(name: name, equipment: equipment)
    }

    /// Goes back to what the matcher found for the row named `name`.
    func resetChoice(for name: String) {
        guard let index = matches.firstIndex(where: { $0.importedName == name }) else { return }
        matches[index].choice = nil
    }

    // MARK: Writing

    /// Writes the planned workouts off the main actor, in batches with progress.
    func startImport() {
        guard let result, let plan, !isWriting else { return }
        let request = ImportWriteRequest(
            workouts: plan.toInsert,
            source: result.format.source,
            resolutions: Dictionary(matches.map { ($0.importedName, $0.resolution) }, uniquingKeysWith: { first, _ in first }),
            library: library
        )
        activity = .writing(ImportWriteProgress(saved: 0, total: plan.insertCount))
        history?.pauseReloads()
        let container = container
        work = Task {
            defer { history?.resumeReloads() }
            do {
                // The task already keeps the model alive until the write ends.
                let report = try await ImportWriter.write(request, to: container) { progress in
                    Task { @MainActor in self.show(progress) }
                }
                finish(with: report, result: result, plan: plan)
            } catch {
                logger.error("Import failed: \(error, privacy: .public)")
                activity = .idle
                problem = .writeFailed
            }
        }
    }

    /// Stops the import after the batch being written; saved batches stay.
    func stopImport() {
        work?.cancel()
    }

    private func show(_ progress: ImportWriteProgress) {
        guard case .writing(let current) = activity, progress.saved >= current.saved else { return }
        activity = .writing(progress)
    }

    private func finish(with report: ImportWriteReport, result: ImportParseResult, plan: ImportPlan) {
        self.report = report
        summary = ImportSummary(result: result, plan: plan, report: report)
        let routineNames = (try? ModelContext(container).fetch(FetchDescriptor<Routine>()).map(\.name)) ?? []
        suggestions = RoutineSuggestion.suggestions(from: result.allWorkouts, existingRoutineNames: routineNames)
            .enumerated()
            .map { SuggestionChoice(suggestion: $0.element, isOn: $0.offset < RoutineSuggestion.enabledByDefault) }
        activity = .idle
        path = []
    }

    /// Creates the switched-on routines in `context` and saves.
    func createRoutines(in context: ModelContext) {
        let resolutions = Dictionary(matches.map { ($0.importedName, $0.resolution) }, uniquingKeysWith: { first, _ in first })
        do {
            for choice in suggestions where choice.isOn {
                try choice.suggestion.create(in: context, resolutions: resolutions, library: library)
            }
            try context.save()
        } catch {
            logger.error("Creating routines failed: \(error, privacy: .public)")
            context.rollback()
        }
    }

    #if DEBUG
    /// Waits for the current read, parse or write (demo states).
    func waitForWork() async {
        await work?.value
    }

    /// Shows the write as if it had got this far (demo states).
    func showProgressForDemo(saved: Int, total: Int) {
        activity = .writing(ImportWriteProgress(saved: saved, total: total))
    }
    #endif

    // MARK: Helpers

    private func reset() {
        generation += 1
        problem = nil
        file = nil
        mapping = nil
        dateOrder = nil
        dateOrderSample = nil
        result = nil
        plan = nil
        matches = []
        summary = nil
        report = nil
        suggestions = []
        path = []
    }

    /// Reads a picked or opened file: security-scoped access, a size limit, and the copy
    /// iOS leaves in the app's Inbox removed afterwards.
    @concurrent
    private static func readFile(at url: URL) async -> Result<Data, Problem> {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= maximumFileSize else { return .failure(.tooLarge) }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            removeInboxCopy(url)
            return .success(data)
        } catch {
            return .failure(.couldNotOpen)
        }
    }

    /// Deletes a file iOS copied into `Documents/Inbox` when it was opened in Wholeset.
    private nonisolated static func removeInboxCopy(_ url: URL) {
        // Resolved, so /private/var and /var spellings of the same folder compare equal.
        let inbox = URL.documentsDirectory.appending(path: "Inbox", directoryHint: .isDirectory).resolvingSymlinksInPath().path()
        guard url.resolvingSymlinksInPath().path().hasPrefix(inbox) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
