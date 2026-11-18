// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

extension SchemaV3 {
    /// App-wide preferences. There is meant to be exactly one row; use
    /// ``SchemaV3/AppSettings/current(in:)`` rather than inserting directly.
    ///
    /// Code that changes a user-facing setting must also set `updatedAt` (the
    /// `SettingsEditing` functions do): duplicate rows created by sync are merged using
    /// it, and a row whose `updatedAt` still equals its `createdAt` counts as never edited.
    /// ``starterRoutinesDecidedAt`` is bookkeeping, not a setting: writing it leaves
    /// `updatedAt` alone, so it can never make a fresh row override real choices.
    @Model
    public final class AppSettings {
        public var id: UUID = UUID()
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now

        /// Raw storage for ``unit``.
        public var unitRaw: String = WeightUnit.kg.rawValue
        /// Rest after a set when neither the routine nor the exercise sets one.
        public var defaultRestSeconds: Int = 90
        /// Raw storage for ``weightCrownSensitivity``.
        public var weightCrownSensitivityRaw: String = CrownSensitivity.normal.rawValue
        /// Raw storage for ``repsCrownSensitivity``.
        public var repsCrownSensitivityRaw: String = CrownSensitivity.normal.rawValue
        /// When this iCloud account first settled whether it has starter routines: the
        /// moment they were seeded, or when the first routine of the user's own appeared.
        /// `nil` while undecided. Rows merged by sync keep the earliest date.
        public var starterRoutinesDecidedAt: Date?
        /// Raw storage for ``progressionSteps``: `equipment=kilograms` pairs separated by
        /// `;`, for example `barbell=2.5;dumbbell=2`. Empty means every built-in default.
        public var progressionStepsRaw: String = ""

        /// Creates a settings row, marked as never edited. Prefer ``current(in:)``.
        public init(unit: WeightUnit = .kg, defaultRestSeconds: Int = 90) {
            self.unitRaw = unit.rawValue
            self.defaultRestSeconds = defaultRestSeconds
            self.updatedAt = self.createdAt
        }
    }
}

extension AppSettings {
    /// The display and input unit for weights. Unknown stored values read as ``WeightUnit/kg``.
    public var unit: WeightUnit {
        get { WeightUnit(persisted: unitRaw) }
        set { unitRaw = newValue.rawValue }
    }

    /// How fast the Watch's Crown changes the weight tile. Unknown values read as normal.
    public var weightCrownSensitivity: CrownSensitivity {
        get { CrownSensitivity(persisted: weightCrownSensitivityRaw) }
        set { weightCrownSensitivityRaw = newValue.rawValue }
    }

    /// How fast the Watch's Crown changes the reps tile. Unknown values read as normal.
    public var repsCrownSensitivity: CrownSensitivity {
        get { CrownSensitivity(persisted: repsCrownSensitivityRaw) }
        set { repsCrownSensitivityRaw = newValue.rawValue }
    }

    /// The user's own progression step per equipment type, in kilograms. Equipment without
    /// an entry uses the built-in default (see ``ProgressionStep``).
    ///
    /// Reading ignores malformed entries, unknown equipment, bodyweight and steps that are
    /// not positive. Writing stores the valid entries in a fixed order.
    public var progressionSteps: [Equipment: Double] {
        get { ProgressionStepList.decode(progressionStepsRaw) }
        set { progressionStepsRaw = ProgressionStepList.encode(newValue) }
    }
}

/// Encodes per-equipment progression steps as `equipment=kilograms;…` text and back.
enum ProgressionStepList {
    static func decode(_ text: String) -> [Equipment: Double] {
        var steps: [Equipment: Double] = [:]
        for pair in text.split(separator: ";") {
            let parts = pair.split(separator: "=", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let equipment = Equipment(rawValue: parts[0].trimmingCharacters(in: .whitespaces)),
                  let value = Double(parts[1].trimmingCharacters(in: .whitespaces)),
                  ProgressionStep.isValid(value, for: equipment) else { continue }
            steps[equipment] = value
        }
        return steps
    }

    static func encode(_ steps: [Equipment: Double]) -> String {
        Equipment.allCases.compactMap { equipment in
            guard let value = steps[equipment], ProgressionStep.isValid(value, for: equipment) else { return nil }
            // `description` is the shortest text that reads back as exactly this Double.
            return "\(equipment.rawValue)=\(value.description)"
        }
        .joined(separator: ";")
    }
}
