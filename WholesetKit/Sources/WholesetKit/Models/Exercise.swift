// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

extension SchemaV3 {
    /// A movement that can be logged: a built-in library entry or a custom exercise.
    @Model
    public final class Exercise {
        public var id: UUID = UUID()
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now

        public var name: String = ""
        /// Raw storage for ``equipment``.
        public var equipmentRaw: String = Equipment.barbell.rawValue
        /// Raw storage for ``primaryMuscle``.
        public var primaryMuscleRaw: String = Muscle.other.rawValue
        public var isCustom: Bool = false
        public var isArchived: Bool = false
        /// Weight increment for progression hints; `nil` uses the equipment default.
        public var progressionStepKg: Double?
        /// Rest after a set; `nil` uses the app default.
        public var defaultRestSeconds: Int?
        /// Raw storage for ``aliases``: one alias per line.
        public var aliasesText: String = ""
        /// The built-in library entry this exercise is (``ExerciseLibrary/Entry/key``);
        /// `nil` for exercises the user created. Several rows with the same key are sync
        /// duplicates and are merged by ``StoreMaintenance``.
        public var libraryKey: String?

        /// Exercises offered when swapping this one out mid-workout.
        ///
        /// Directed: listing B as an alternative of A does not make A an
        /// alternative of B. The inverse is ``alternativeOf``.
        @Relationship(deleteRule: .nullify, inverse: \Exercise.alternativeOf)
        public var alternatives: [Exercise]? = []

        /// Exercises that list this one as an alternative (inverse of ``alternatives``).
        public var alternativeOf: [Exercise]? = []

        /// Routine slots that use this exercise.
        @Relationship(deleteRule: .nullify, inverse: \RoutineItem.exercise)
        public var routineItems: [RoutineItem]? = []

        /// Session entries that logged this exercise.
        @Relationship(deleteRule: .nullify, inverse: \SessionExercise.exercise)
        public var sessionEntries: [SessionExercise]? = []

        /// Creates an exercise. Relationships are set after insertion into a context.
        public init(
            name: String = "",
            equipment: Equipment = .barbell,
            primaryMuscle: Muscle = .other,
            isCustom: Bool = false
        ) {
            self.name = name
            self.equipmentRaw = equipment.rawValue
            self.primaryMuscleRaw = primaryMuscle.rawValue
            self.isCustom = isCustom
        }
    }
}

extension Exercise {
    /// The equipment type. Unknown stored values read as ``Equipment/other``.
    public var equipment: Equipment {
        get { Equipment(persisted: equipmentRaw) }
        set { equipmentRaw = newValue.rawValue }
    }

    /// The primary muscle group. Unknown stored values read as ``Muscle/other``.
    public var primaryMuscle: Muscle {
        get { Muscle(persisted: primaryMuscleRaw) }
        set { primaryMuscleRaw = newValue.rawValue }
    }

    /// Other names this exercise is known by, used to match imported names.
    ///
    /// Stored as newline-separated text in ``aliasesText``. Writing trims each
    /// alias, turns embedded line breaks into spaces, and drops empty and
    /// case-insensitive duplicate entries.
    public var aliases: [String] {
        get { AliasList.decode(aliasesText) }
        set { aliasesText = AliasList.encode(newValue) }
    }
}

/// Encodes an alias list as newline-separated text and back.
enum AliasList {
    static let separator: Character = "\n"

    static func encode(_ aliases: [String]) -> String {
        var seen: Set<String> = []
        var cleaned: [String] = []
        for alias in aliases {
            let flattened = alias
                .split(whereSeparator: \.isNewline)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            guard !flattened.isEmpty, seen.insert(flattened.lowercased()).inserted else { continue }
            cleaned.append(flattened)
        }
        return cleaned.joined(separator: String(separator))
    }

    static func decode(_ text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
