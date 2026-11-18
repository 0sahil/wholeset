// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A fixed-size span of Crown detents around an anchor value.
///
/// Editing a value with a wide range (a weight has about a thousand steps) through a Crown
/// range of the same width makes the Crown feel very different from one with a short range.
/// Giving the Crown a window of fixed size keeps the feel identical for every value.
public struct CrownWindow: Sendable, Equatable {
    /// Every value the edited quantity can take.
    public let bounds: ClosedRange<Int>
    /// The number of detents in the window (its upper bound minus its lower bound).
    public let span: Int

    /// Creates a window description. A `span` below 1 is treated as 1.
    public init(bounds: ClosedRange<Int>, span: Int) {
        self.bounds = bounds
        self.span = max(1, span)
    }

    /// The Crown range centred on `anchor` (clamped into ``bounds``), shifted to stay inside
    /// ``bounds``. Returns ``bounds`` itself when it is no wider than ``span``.
    public func range(around anchor: Int) -> ClosedRange<Int> {
        guard bounds.upperBound - bounds.lowerBound > span else { return bounds }
        let anchor = clamp(anchor)
        let lower = min(max(anchor - span / 2, bounds.lowerBound), bounds.upperBound - span)
        return lower...(lower + span)
    }

    /// `value` limited to ``bounds``.
    public func clamp(_ value: Int) -> Int {
        min(max(value, bounds.lowerBound), bounds.upperBound)
    }
}

/// A Digital Crown edit of one whole-number value (weight steps or reps), held in memory
/// and written to the store only when ``hasUnsavedChange`` says so.
///
/// The Crown's detent binding *is* ``value``: what the Crown reports is what the screen
/// shows, so the two can never disagree. The Crown range is a ``CrownWindow`` around
/// ``anchor``, and the anchor only moves when the Crown is idle (``recentre()``) or after a
/// VoiceOver step, never during a turn. A turn can therefore never see its range change
/// under it; a single turn reaches at most half a window from where it started, and the
/// next turn continues from there.
public struct CrownEdit: Sendable, Equatable {
    /// The window of Crown detents; its bounds are every value the edit can take.
    public let window: CrownWindow
    /// The value on screen.
    public private(set) var value: Int
    /// The value last written to the store; `nil` when the store has none (for example a
    /// set with no weight yet).
    public private(set) var savedValue: Int?
    /// The centre of the current Crown window.
    public private(set) var anchor: Int
    /// Whether the user has changed the value since the edit began.
    public private(set) var hasMoved = false

    /// Starts an edit.
    ///
    /// - Parameters:
    ///   - value: Where the Crown starts: the stored value, or a starting point when there is none.
    ///   - isStored: Whether `value` is what the store holds. When `false`, the edit writes
    ///     nothing unless the user moves the value.
    ///   - bounds: Every value the edit can take; `value` is clamped into it.
    ///   - span: Detents in the Crown window (see ``CrownWindow``).
    public init(value: Int, isStored: Bool, bounds: ClosedRange<Int>, span: Int) {
        let window = CrownWindow(bounds: bounds, span: span)
        let start = window.clamp(value)
        self.window = window
        self.value = start
        self.savedValue = isStored ? start : nil
        self.anchor = start
    }

    /// The range to give the Crown now.
    public var crownRange: ClosedRange<Int> {
        window.range(around: anchor)
    }

    /// Whether ``value`` differs from what the store holds and should be written.
    public var hasUnsavedChange: Bool {
        hasMoved && value != savedValue
    }

    /// Whether the screen should show ``value``. `false` while the store has no value and
    /// the user has not moved it, so an untouched empty field keeps its placeholder.
    public var showsValue: Bool {
        savedValue != nil || hasMoved
    }

    /// The Crown reported detent `position`. Positions outside ``crownRange`` are clamped.
    ///
    /// - Returns: Whether ``value`` changed.
    @discardableResult
    public mutating func crownMoved(to position: Int) -> Bool {
        let range = crownRange
        let next = min(max(position, range.lowerBound), range.upperBound)
        guard next != value else { return false }
        value = next
        hasMoved = true
        return true
    }

    /// Moves the value by `delta` steps within the bounds (VoiceOver's adjustable action).
    /// The window follows when the value leaves it, so the Crown carries on from there.
    ///
    /// - Returns: Whether ``value`` changed.
    @discardableResult
    public mutating func step(by delta: Int) -> Bool {
        let (sum, overflow) = value.addingReportingOverflow(delta)
        let next = overflow ? (delta > 0 ? window.bounds.upperBound : window.bounds.lowerBound) : window.clamp(sum)
        guard next != value else { return false }
        value = next
        hasMoved = true
        if !crownRange.contains(next) {
            anchor = next
        }
        return true
    }

    /// Centres the Crown window on ``value``, so the next turn has room both ways. Call
    /// only while the Crown is idle: it changes ``crownRange`` but never ``value``.
    public mutating func recentre() {
        anchor = value
    }

    /// Records that ``value`` has been written to the store.
    public mutating func markSaved() {
        savedValue = value
    }
}

/// Keeps a number's rendered width constant while its value changes.
public enum StableNumberWidth {
    /// The characters to append, invisibly, to `value` so it has the same characters as
    /// `template`, counting every digit as interchangeable.
    ///
    /// With tabular (monospaced) digits `value + filler` is then exactly as wide as
    /// `template`, so a text that shrinks to fit uses the same font size for every value.
    /// A character of `value` with no counterpart in `template` (such as a "–" placeholder)
    /// takes the place of one digit.
    ///
    /// - Parameters:
    ///   - value: The text on screen, for example "60.5".
    ///   - template: The widest text the value can become, for example "888.8".
    /// - Returns: The template's characters left over, for example "8"; empty when `value`
    ///   is already as wide as `template`.
    public static func filler(for value: String, toMatch template: String) -> String {
        var remaining = Array(template)
        var unmatched = 0
        for character in value {
            let index = remaining.firstIndex { candidate in
                candidate == character || (candidate.isWholeNumber && character.isWholeNumber)
            }
            if let index {
                remaining.remove(at: index)
            } else {
                unmatched += 1
            }
        }
        for _ in 0..<unmatched {
            guard let index = remaining.firstIndex(where: \.isWholeNumber) else { break }
            remaining.remove(at: index)
        }
        return String(remaining)
    }
}
