// SPDX-License-Identifier: GPL-3.0-or-later

@testable import WholesetKit

extension CrownEdit {
    /// Turns the Crown to `target` the way a real turn reports it: one detent first, then
    /// straight on to `target` (a fast turn can skip detents after it has started).
    ///
    /// - Returns: Whether ``value`` changed.
    @discardableResult
    mutating func turn(to target: Int) -> Bool {
        guard target != position else { return crownMoved(to: target) }
        let first = crownMoved(to: position + (target > position ? 1 : -1))
        let rest = crownMoved(to: target)
        return first || rest
    }
}
