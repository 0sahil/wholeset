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
/// The Crown's detent binding is ``position``. With one detent per step (the default, and
/// every Normal setting) the position *is* ``value``: what the Crown reports is what the
/// screen shows, so the two can never disagree. With more detents per step (see
/// ``CrownProfile``) the value moves one step for every ``detentsPerStep`` detents turned
/// in the same direction, and the Crown range keeps the same number of detents, so the
/// value moves proportionally slower.
///
/// The Crown range is a ``CrownWindow`` around ``anchor``, and the anchor only moves when
/// the Crown is idle (``recentre()``) or after a VoiceOver step, never during a turn. A
/// turn can therefore never see its range change under it; a single turn reaches at most
/// half a window from where it started, and the next turn continues from there.
public struct CrownEdit: Sendable, Equatable {
    /// The window of values the Crown can reach around the anchor; its bounds are every
    /// value the edit can take.
    public let window: CrownWindow
    /// Crown detents per value step (1 or more).
    public let detentsPerStep: Int
    /// The value on screen.
    public private(set) var value: Int
    /// The Crown's detent position: ``value`` × ``detentsPerStep`` plus any part of a step
    /// turned so far.
    public private(set) var position: Int
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
    ///   - span: Detents in the Crown window (see ``CrownWindow``). The window covers
    ///     `span / detentsPerStep` values, so its width in detents stays the same.
    ///   - detentsPerStep: Crown detents per value step; values below 1 are treated as 1.
    public init(value: Int, isStored: Bool, bounds: ClosedRange<Int>, span: Int, detentsPerStep: Int = 1) {
        let detentsPerStep = max(1, detentsPerStep)
        let window = CrownWindow(bounds: bounds, span: max(1, span / detentsPerStep))
        let start = window.clamp(value)
        self.window = window
        self.detentsPerStep = detentsPerStep
        self.value = start
        self.position = start * detentsPerStep
        self.savedValue = isStored ? start : nil
        self.anchor = start
    }

    /// The range of detent positions to give the Crown now.
    public var crownRange: ClosedRange<Int> {
        let values = window.range(around: anchor)
        return (values.lowerBound * detentsPerStep)...(values.upperBound * detentsPerStep)
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
    /// The value follows only whole steps: it moves up once the position reaches the next
    /// step's first detent, and down once it reaches the previous step's, so turning back
    /// and forth within a step never changes it.
    ///
    /// - Returns: Whether ``value`` changed.
    @discardableResult
    public mutating func crownMoved(to position: Int) -> Bool {
        let range = crownRange
        let clamped = min(max(position, range.lowerBound), range.upperBound)
        self.position = clamped
        let detents = detentsPerStep
        var next = value
        if clamped >= (value + 1) * detents {
            next = Self.floorDivide(clamped, by: detents)
        } else if clamped <= (value - 1) * detents {
            next = -Self.floorDivide(-clamped, by: detents)
        }
        next = window.clamp(next)
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
        position = next * detentsPerStep
        hasMoved = true
        if !window.range(around: anchor).contains(next) {
            anchor = next
        }
        return true
    }

    /// Centres the Crown window on ``value`` and drops any part of a step turned so far,
    /// so the next turn has room both ways. Call only while the Crown is idle: it changes
    /// ``crownRange`` and ``position`` but never ``value``.
    public mutating func recentre() {
        anchor = value
        position = value * detentsPerStep
    }

    /// Records that ``value`` has been written to the store.
    public mutating func markSaved() {
        savedValue = value
    }

    /// `dividend / divisor` rounded towards negative infinity (`divisor` > 0).
    private static func floorDivide(_ dividend: Int, by divisor: Int) -> Int {
        dividend >= 0 ? dividend / divisor : -((-dividend + divisor - 1) / divisor)
    }
}

/// The speed of the Digital Crown's rotation, independent of any UI framework. The Watch
/// maps it one to one onto SwiftUI's `DigitalCrownRotationalSensitivity`.
public enum CrownRate: Int, Sendable, Comparable {
    case low
    case medium
    case high

    public static func < (lhs: CrownRate, rhs: CrownRate) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// How the Crown edits one tile: the system rotation rate plus how many detents make one
/// value step.
///
/// The system offers only three rates, and the device-tested Normal weight setting already
/// uses the lowest, so Slow weight turns two detents into one step instead. Because the
/// Crown window keeps the same number of detents (see ``CrownEdit``), that halves how far a
/// turn moves the weight, while every step stays an exact multiple of the scale's step, so
/// kilogram round trips are unaffected. With more than one detent per step the system's
/// per-detent haptic would tick twice per step, so the app plays one click per applied
/// step instead (``usesSystemHaptics``).
///
/// | Setting | Weight                  | Reps                    |
/// |---------|-------------------------|-------------------------|
/// | Slow    | low, 2 detents per step | low                     |
/// | Normal  | low (device-tested)     | medium (device-tested)  |
/// | Fast    | medium                  | high                    |
public struct CrownProfile: Sendable, Equatable {
    /// The system rotation rate.
    public let rate: CrownRate
    /// Crown detents per value step.
    public let detentsPerStep: Int

    /// Creates a profile. `detentsPerStep` below 1 is treated as 1.
    public init(rate: CrownRate, detentsPerStep: Int = 1) {
        self.rate = rate
        self.detentsPerStep = max(1, detentsPerStep)
    }

    /// Whether the system plays the haptic for each detent. When `false`, the app plays one
    /// haptic per value step it applies.
    public var usesSystemHaptics: Bool { detentsPerStep == 1 }

    /// The profile for the weight tile.
    public static func weight(_ sensitivity: CrownSensitivity) -> CrownProfile {
        switch sensitivity {
        case .slow: CrownProfile(rate: .low, detentsPerStep: 2)
        case .normal: CrownProfile(rate: .low)
        case .fast: CrownProfile(rate: .medium)
        }
    }

    /// The profile for the reps tile.
    public static func reps(_ sensitivity: CrownSensitivity) -> CrownProfile {
        switch sensitivity {
        case .slow: CrownProfile(rate: .low)
        case .normal: CrownProfile(rate: .medium)
        case .fast: CrownProfile(rate: .high)
        }
    }

    /// Moving between exercises with no tile selected; not user-adjustable.
    public static let exerciseNavigation = CrownProfile(rate: .low)

    /// Whether a full turn moves the value fewer steps than with `other`: a lower rate at
    /// no fewer detents per step, or the same rate with more detents per step.
    public func isSlower(than other: CrownProfile) -> Bool {
        if rate == other.rate { return detentsPerStep > other.detentsPerStep }
        return rate < other.rate && detentsPerStep >= other.detentsPerStep
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
