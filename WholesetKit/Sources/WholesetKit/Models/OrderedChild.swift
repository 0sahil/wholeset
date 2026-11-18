// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A child model kept in a user-defined order.
///
/// CloudKit cannot mirror ordered relationships, so children carry an explicit
/// `order` and parents expose `sorted…` accessors built on ``sortedByOrder()``.
protocol OrderedChild {
    var order: Int { get }
    var createdAt: Date { get }
    var id: UUID { get }
}

extension Sequence where Element: OrderedChild {
    /// Sorts by `order`, then `createdAt`, then `id`, so ties (for example two
    /// devices appending a child at the same index) still sort the same way everywhere.
    func sortedByOrder() -> [Element] {
        sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
