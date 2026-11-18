// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// An exercise an imported name can become: one in the store, or a built-in library entry
/// the store does not hold yet (it is added, with its library key, when used).
public struct ExerciseCandidate: Sendable, Hashable, Identifiable {
    /// Which exercise the candidate is.
    public enum Reference: Sendable, Hashable {
        /// An exercise in the store, by `id`.
        case stored(UUID)
        /// A library entry not in the store, by ``ExerciseLibrary/Entry/key``.
        case library(String)
    }

    public let reference: Reference
    public let name: String
    public let equipment: Equipment
    public let aliases: [String]
    public let isArchived: Bool
    /// The library entry it is, if any.
    public let libraryKey: String?

    public var id: Reference { reference }

    /// Creates a candidate.
    public init(reference: Reference, name: String, equipment: Equipment, aliases: [String] = [], isArchived: Bool = false, libraryKey: String? = nil) {
        self.reference = reference
        self.name = name
        self.equipment = equipment
        self.aliases = aliases
        self.isArchived = isArchived
        self.libraryKey = libraryKey
    }

    /// The candidate for a stored exercise.
    public init(_ exercise: Exercise) {
        self.init(
            reference: .stored(exercise.id),
            name: exercise.name,
            equipment: exercise.equipment,
            aliases: exercise.aliases,
            isArchived: exercise.isArchived,
            libraryKey: exercise.libraryKey
        )
    }

    /// The candidate for a library entry the store does not hold.
    public init(_ entry: ExerciseLibrary.Entry) {
        self.init(reference: .library(entry.key), name: entry.name, equipment: entry.equipment, aliases: entry.aliases, libraryKey: entry.key)
    }

    /// Every stored exercise, plus the library entries no stored exercise is (by key).
    public static func all(exercises: [Exercise], library: ExerciseLibrary) -> [ExerciseCandidate] {
        let storedKeys = Set(exercises.compactMap(\.libraryKey))
        return exercises.map(ExerciseCandidate.init) + library.entries.filter { !storedKeys.contains($0.key) }.map(ExerciseCandidate.init)
    }
}

/// What an imported exercise name will become.
public enum ExerciseMatch: Sendable, Hashable {
    /// How a confident match was found.
    public enum Method: String, Sendable, Hashable {
        /// The same name (ignoring case, diacritics, spacing and punctuation).
        case exactName
        /// One of the exercise's aliases.
        case alias
        /// A name other apps use for a built-in exercise (``ImportAliasTable``).
        case knownName
        /// The name without its "(Equipment)" or equipment word, with the same equipment.
        case nameAndEquipment
    }

    /// Why a match needs a look.
    public enum CheckReason: Sendable, Hashable {
        /// Most words of the names agree.
        case similarName
        /// The name matches but the file names other equipment (`nil` when it names no
        /// equipment Wholeset knows, such as "Single Arm").
        case differentEquipment(Equipment?)
    }

    /// A confident match.
    case matched(ExerciseCandidate, Method)
    /// A likely match the user should confirm.
    case check(ExerciseCandidate, CheckReason)
    /// No match: a custom exercise is created with this name and equipment.
    case newCustom(name: String, equipment: Equipment)

    /// The exercise matched, if any.
    public var candidate: ExerciseCandidate? {
        switch self {
        case .matched(let candidate, _), .check(let candidate, _): candidate
        case .newCustom: nil
        }
    }

    /// Whether the user should look at it (a likely match, or a new custom exercise).
    public var needsLook: Bool {
        if case .matched = self { return false }
        return true
    }
}

/// Finds the Wholeset exercise for each name in an import.
///
/// For each name, in order:
/// 1. **Exact name** of an exercise (``looseKey(_:)``: ``ExerciseName/normalized(_:)`` with
///    hyphens, dots and apostrophes ignored).
/// 2. One of an exercise's **aliases** (what earlier imports remembered, and the library's).
/// 3. The **built-in table** of other apps' names (``ImportAliasTable``).
/// 4. **Name and equipment**: "Hip Thrust (Machine)" or "Barbell Front Squat" without the
///    equipment matches "Hip Thrust" / "Front Squat"; the same equipment is a match, other
///    equipment a ``ExerciseMatch/CheckReason/differentEquipment(_:)`` check. With the
///    equipment word moved to the front ("Bench Press (Dumbbell)" → "Dumbbell Bench Press")
///    it is a match.
/// 5. **Similar name**: words are compared with plurals, "DB"/"BB" and "Pull Up"/"Pullup"
///    folded. Equipment words never count, and modifiers ("one-arm", "seated", "close grip")
///    do not count on their own: the names must share at least two words, one of them naming
///    the movement (a one-word movement must equal the other's only one), with a Dice overlap
///    of 0.6 or more over the movement words. The closest such name is a
///    ``ExerciseMatch/CheckReason/similarName`` check.
/// 6. Otherwise a **new custom exercise**, its equipment guessed from the name.
///
/// When several exercises fit, active ones win over archived ones, then stored exercises over
/// library entries not yet in the store. Archived exercises still match; the result says so
/// through ``ExerciseCandidate/isArchived``. Names in other languages are not translated.
public struct ExerciseMatcher: Sendable {
    private let byName: [String: [ExerciseCandidate]]
    private let byAlias: [String: [ExerciseCandidate]]
    private let byLibraryKey: [String: [ExerciseCandidate]]
    private let knownNames: [String: String]
    private let tokenized: [(candidate: ExerciseCandidate, tokens: [Set<String>])]

    /// Creates a matcher over `candidates`.
    ///
    /// - Parameter knownNames: Other apps' names → library keys.
    public init(candidates: [ExerciseCandidate], knownNames: [String: String] = ImportAliasTable.builtIn) {
        var byName: [String: [ExerciseCandidate]] = [:]
        var byAlias: [String: [ExerciseCandidate]] = [:]
        var byLibraryKey: [String: [ExerciseCandidate]] = [:]
        var tokenized: [(ExerciseCandidate, [Set<String>])] = []
        for candidate in candidates {
            byName[Self.looseKey(candidate.name), default: []].append(candidate)
            for alias in candidate.aliases {
                byAlias[Self.looseKey(alias), default: []].append(candidate)
            }
            if let key = candidate.libraryKey { byLibraryKey[key, default: []].append(candidate) }
            tokenized.append((candidate, ([candidate.name] + candidate.aliases).map(Self.tokens)))
        }
        self.byName = byName
        self.byAlias = byAlias
        self.byLibraryKey = byLibraryKey
        self.knownNames = Dictionary(knownNames.map { (Self.looseKey($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
        self.tokenized = tokenized
    }

    /// Matches every name; the result keeps `names`' order.
    public func match(_ names: [String]) -> [(name: String, match: ExerciseMatch)] {
        names.map { ($0, match($0)) }
    }

    /// What `importedName` becomes.
    public func match(_ importedName: String) -> ExerciseMatch {
        let name = importedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = Self.looseKey(name)
        if let best = Self.best(byName[key]) { return .matched(best, .exactName) }
        if let best = Self.best(byAlias[key]) { return .matched(best, .alias) }
        if let best = known(key) { return .matched(best, .knownName) }
        if let match = equipmentMatch(name) { return match }
        if let similar = similar(to: name) { return .check(similar, .similarName) }
        return .newCustom(name: name, equipment: Self.guessedEquipment(for: name))
    }

    // MARK: Steps

    private func known(_ key: String) -> ExerciseCandidate? {
        knownNames[key].flatMap { Self.best(byLibraryKey[$0]) }
    }

    /// Exercises named `key` by name, alias or the built-in table.
    private func named(_ key: String) -> [ExerciseCandidate] {
        (byName[key] ?? []) + (byAlias[key] ?? []) + (knownNames[key].flatMap { byLibraryKey[$0] } ?? [])
    }

    private func equipmentMatch(_ name: String) -> ExerciseMatch? {
        if let (base, qualifier) = Self.parenthetical(name) {
            let hint = Self.equipment(forWords: Self.looseKey(qualifier))
            if hint != nil, let best = Self.best(named(Self.looseKey(qualifier + " " + base))) {
                return .matched(best, .nameAndEquipment)
            }
            let found = named(Self.looseKey(base))
            guard !found.isEmpty else { return nil }
            if let hint, let same = Self.best(found.filter { $0.equipment == hint }) {
                return .matched(same, .nameAndEquipment)
            }
            guard let best = Self.best(found) else { return nil }
            return .check(best, .differentEquipment(hint))
        }
        let words = Self.looseKey(name).split(separator: " ").map(String.init)
        guard words.count > 1 else { return nil }
        for (word, rest) in [(words[0], words.dropFirst()), (words[words.count - 1], words.dropLast())] {
            guard let hint = Self.equipment(forWords: word) else { continue }
            let found = named(rest.joined(separator: " "))
            if let same = Self.best(found.filter { $0.equipment == hint }) { return .matched(same, .nameAndEquipment) }
            if let best = Self.best(found) { return .check(best, .differentEquipment(hint)) }
        }
        return nil
    }

    private func similar(to name: String) -> ExerciseCandidate? {
        let wanted = Self.tokens(name)
        let wantedMovement = wanted.subtracting(Self.equipmentTokens)
        let wantedCore = wantedMovement.subtracting(Self.modifierTokens)
        guard wanted.count >= 2, !wantedCore.isEmpty else { return nil }
        var best: (candidate: ExerciseCandidate, core: Double, full: Double)?
        for (candidate, tokenSets) in tokenized {
            for tokens in tokenSets {
                // Equipment and modifier words alone never make names similar: "Landmine Press
                // (Barbell)" is not "Bench Press (Barbell)", "One-Arm Spider Curl" not "One-Arm Row".
                let movement = tokens.subtracting(Self.equipmentTokens)
                let core = movement.subtracting(Self.modifierTokens)
                let sharedCore = wantedCore.intersection(core).count
                let sharedMovement = wantedMovement.intersection(movement).count
                guard sharedCore > 0,
                      sharedMovement >= 2 || (sharedMovement == 1 && movement.count == 1 && wantedMovement.count == 1) else { continue }
                let coreScore = 2 * Double(sharedCore) / Double(wantedCore.count + core.count)
                let fullScore = 2 * Double(wanted.intersection(tokens).count) / Double(wanted.count + tokens.count)
                guard coreScore >= 0.6, fullScore >= 0.5 else { continue }
                if let current = best {
                    if coreScore != current.core {
                        if coreScore < current.core { continue }
                    } else if fullScore != current.full {
                        if fullScore < current.full { continue }
                    } else if !Self.isPreferred(candidate, over: current.candidate) {
                        continue
                    }
                }
                best = (candidate, coreScore, fullScore)
            }
        }
        return best?.candidate
    }

    // MARK: Helpers

    /// The preferred of several candidates: active before archived, stored before library,
    /// then by name.
    private static func best(_ candidates: [ExerciseCandidate]?) -> ExerciseCandidate? {
        candidates?.min { isPreferred($0, over: $1) }
    }

    private static func isPreferred(_ lhs: ExerciseCandidate, over rhs: ExerciseCandidate) -> Bool {
        if lhs.isArchived != rhs.isArchived { return !lhs.isArchived }
        let lhsStored = if case .stored = lhs.reference { true } else { false }
        let rhsStored = if case .stored = rhs.reference { true } else { false }
        if lhsStored != rhsStored { return lhsStored }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        return lhs.reference.sortKey < rhs.reference.sortKey
    }

    /// ``ExerciseName/normalized(_:)`` with hyphens, underscores, slashes, dots, commas and
    /// apostrophes ignored: "Pull-Up" and "pull up" are the same key.
    public static func looseKey(_ name: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in ExerciseName.normalized(name).unicodeScalars {
            switch scalar {
            case "-", "_", "/", "\u{2013}", "\u{2014}", ",", ".": scalars.append(" ")
            case "'", "\u{2019}": continue
            default: scalars.append(scalar)
            }
        }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }

    /// A name's trailing parenthetical: "Hip Thrust (Machine)" → ("Hip Thrust", "Machine");
    /// `nil` without one.
    public static func parenthetical(_ name: String) -> (base: String, qualifier: String)? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix(")"), let open = trimmed.lastIndex(of: "(") else { return nil }
        let base = trimmed[..<open].trimmingCharacters(in: .whitespaces)
        let qualifier = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)].trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty, !qualifier.isEmpty else { return nil }
        return (base, qualifier)
    }

    /// The equipment a word or two names ("barbell", "smith machine", "ez bar", "db" …).
    static func equipment(forWords words: String) -> Equipment? {
        switch looseKey(words) {
        case "barbell", "bb", "ez bar", "ezbar", "ez", "trap bar", "hex bar", "olympic bar": .barbell
        case "dumbbell", "dumbbells", "db": .dumbbell
        case "machine", "smith machine", "smith", "lever", "leverage", "plate loaded", "machine plates", "assisted": .machine
        case "cable", "cables", "rope", "pulley": .cable
        case "bodyweight", "body weight", "bw": .bodyweight
        case "kettlebell", "kb", "band", "bands", "resistance band", "plate", "weighted", "sandbag", "landmine": .other
        default: nil
        }
    }

    /// The equipment a new custom exercise gets: from its "(Equipment)", else from an
    /// equipment word in its name, else ``Equipment/other``.
    public static func guessedEquipment(for name: String) -> Equipment {
        if let (_, qualifier) = parenthetical(name), let equipment = equipment(forWords: qualifier) {
            return equipment
        }
        let words = looseKey(name).split(separator: " ").map(String.init)
        for pair in zip(words, words.dropFirst()) {
            if let equipment = equipment(forWords: "\(pair.0) \(pair.1)") { return equipment }
        }
        for word in words {
            if let equipment = equipment(forWords: word) { return equipment }
        }
        return .other
    }

    private static let stopWords: Set<String> = ["with", "the", "a", "an", "on", "of", "and", "to", "in", "over", "using"]
    /// Tokens naming equipment rather than the movement.
    private static let equipmentTokens: Set<String> = [
        "barbell", "dumbbell", "machine", "cable", "bodyweight", "smith", "ez", "kettlebell", "band", "rope",
        "lever", "plate", "weighted", "assisted", "landmine",
    ]
    /// Tokens that vary a movement (grip, stance, side) without naming it.
    private static let modifierTokens: Set<String> = [
        "one", "arm", "single", "two", "double", "alternating", "unilateral", "bilateral", "seated", "standing",
        "lying", "kneeling", "grip", "close", "wide", "narrow", "neutral", "underhand", "overhand", "thick", "bar",
        "behind", "head", "neck", "high", "low", "mid", "off", "block", "chain", "strict", "partial", "paused",
        "pause", "tempo", "isolateral", "iso", "heavy", "light", "flat",
    ]
    private static let synonyms: [String: String] = [
        "db": "dumbbell", "bb": "barbell", "tricep": "triceps", "bicep": "biceps",
        "flyes": "fly", "flye": "fly", "flies": "fly", "pressdown": "pushdown",
    ]
    private static let joinsWithNext: Set<String> = ["push", "pull", "chin", "sit", "step"]

    /// The comparable words of a name: lower-cased, plurals and common spellings folded.
    static func tokens(_ name: String) -> Set<String> {
        var words = looseKey(name)
            .split(whereSeparator: { $0 == " " || $0 == "(" || $0 == ")" })
            .map(String.init)
        var merged: [String] = []
        var index = 0
        while index < words.count {
            if joinsWithNext.contains(words[index]), index + 1 < words.count, ["up", "ups", "down"].contains(words[index + 1]) {
                merged.append(words[index] + words[index + 1])
                index += 2
            } else {
                merged.append(words[index])
                index += 1
            }
        }
        words = merged
        var tokens: Set<String> = []
        for word in words where !stopWords.contains(word) {
            var token = synonyms[word] ?? word
            if token.count > 3, token.hasSuffix("s"), !token.hasSuffix("ss") { token.removeLast() }
            tokens.insert(token)
        }
        return tokens
    }
}

private extension ExerciseCandidate.Reference {
    var sortKey: String {
        switch self {
        case .stored(let id): "0" + id.uuidString
        case .library(let key): "1" + key
        }
    }
}
