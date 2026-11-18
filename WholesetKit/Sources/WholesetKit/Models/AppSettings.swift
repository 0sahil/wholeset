// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftData

extension SchemaV1 {
    /// App-wide preferences. There is meant to be exactly one row; use
    /// ``SchemaV1/AppSettings/current(in:)`` rather than inserting directly.
    ///
    /// Code that changes a setting must also set `updatedAt`: duplicate rows created
    /// by sync are merged using it, and a row whose `updatedAt` still equals its
    /// `createdAt` counts as never edited.
    @Model
    public final class AppSettings {
        public var id: UUID = UUID()
        public var createdAt: Date = Date.now
        public var updatedAt: Date = Date.now

        /// Raw storage for ``unit``.
        public var unitRaw: String = WeightUnit.kg.rawValue
        /// Rest after a set when neither the routine nor the exercise sets one.
        public var defaultRestSeconds: Int = 90

        /// Creates a settings row, marked as never edited. Prefer ``current(in:)``.
        public init(unit: WeightUnit = .kg, defaultRestSeconds: Int = 90) {
            self.unitRaw = unit.rawValue
            self.defaultRestSeconds = defaultRestSeconds
            self.updatedAt = self.createdAt
        }
    }
}

extension SchemaV1.AppSettings {
    /// The display and input unit for weights. Unknown stored values read as ``WeightUnit/kg``.
    public var unit: WeightUnit {
        get { WeightUnit(persisted: unitRaw) }
        set { unitRaw = newValue.rawValue }
    }
}
