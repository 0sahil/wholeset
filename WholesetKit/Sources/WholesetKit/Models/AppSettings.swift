// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

extension SchemaV2 {
    /// App-wide preferences. There is meant to be exactly one row; use
    /// ``SchemaV2/AppSettings/current(in:)`` rather than inserting directly.
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
}
