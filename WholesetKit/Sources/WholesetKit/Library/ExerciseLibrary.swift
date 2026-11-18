// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The built-in exercise library: about 150 common gym exercises.
///
/// Curated from free-exercise-db (https://github.com/yuhonas/free-exercise-db, released
/// into the public domain under the Unlicense) by `Scripts/curate-exercise-library.py`,
/// which keeps a stable key (the upstream `id`), a display name, the equipment, the
/// primary muscle and a few aliases per entry, and maps upstream equipment and muscles
/// onto ``Equipment`` and ``Muscle`` (see the script for the table).
///
/// The library is read-only data. ``LibrarySeeder`` turns it into `Exercise` rows.
public struct ExerciseLibrary: Sendable, Equatable {
    /// One built-in exercise.
    public struct Entry: Sendable, Equatable, Identifiable {
        /// Stable identifier, never shown and never changed once shipped.
        public let key: String
        /// Display name, unique in the library ignoring case.
        public let name: String
        public let equipment: Equipment
        public let muscle: Muscle
        /// Other names for this exercise, used to match imported workouts.
        public let aliases: [String]

        public var id: String { key }

        /// Creates an entry.
        public init(key: String, name: String, equipment: Equipment, muscle: Muscle, aliases: [String] = []) {
            self.key = key
            self.name = name
            self.equipment = equipment
            self.muscle = muscle
            self.aliases = aliases
        }
    }

    /// Where the data comes from, for credits.
    public let source: String
    /// The data's licence.
    public let license: String
    /// Every entry, sorted by name.
    public let entries: [Entry]

    /// Creates a library from entries (tests and previews).
    public init(source: String = "", license: String = "", entries: [Entry]) {
        self.source = source
        self.license = license
        self.entries = entries
    }

    /// The entry with `key`, if any.
    public func entry(forKey key: String) -> Entry? {
        entries.first { $0.key == key }
    }

    /// The entry named `name`, ignoring case and surrounding whitespace.
    public func entry(named name: String) -> Entry? {
        let wanted = ExerciseName.normalized(name)
        return entries.first { ExerciseName.normalized($0.name) == wanted }
    }

    /// Errors reading the bundled library.
    public enum LoadError: Error, Equatable {
        case missingResource
        /// An entry uses an equipment or muscle value this version does not know.
        case unknownValue(key: String, value: String)
    }

    /// The library bundled with the app.
    ///
    /// Loaded once and cached. Throws only if the bundle is broken, which the tests guard against.
    public static func bundled() throws -> ExerciseLibrary {
        try bundledResult.get()
    }

    private static let bundledResult: Result<ExerciseLibrary, any Error> = Result {
        guard let url = Bundle.module.url(forResource: "exercises", withExtension: "json") else {
            throw LoadError.missingResource
        }
        return try decode(Data(contentsOf: url))
    }

    /// Decodes library JSON: `{"source", "license", "exercises": [{"key", "name",
    /// "equipment", "muscle", "aliases"}]}` with WholesetKit raw values.
    public static func decode(_ data: Data) throws -> ExerciseLibrary {
        struct File: Decodable {
            struct Item: Decodable {
                let key: String
                let name: String
                let equipment: String
                let muscle: String
                let aliases: [String]?
            }
            let source: String
            let license: String
            let exercises: [Item]
        }
        let file = try JSONDecoder().decode(File.self, from: data)
        let entries = try file.exercises.map { item in
            guard let equipment = Equipment(rawValue: item.equipment) else {
                throw LoadError.unknownValue(key: item.key, value: item.equipment)
            }
            guard let muscle = Muscle(rawValue: item.muscle) else {
                throw LoadError.unknownValue(key: item.key, value: item.muscle)
            }
            return Entry(key: item.key, name: item.name, equipment: equipment, muscle: muscle, aliases: item.aliases ?? [])
        }
        return ExerciseLibrary(
            source: file.source,
            license: file.license,
            entries: entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        )
    }
}

/// How exercise names are compared.
public enum ExerciseName {
    /// Lower-cased, diacritics folded, surrounding whitespace removed and inner runs of
    /// whitespace collapsed: "  Bench  press " and "bench press" are the same name.
    public static func normalized(_ name: String) -> String {
        name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
