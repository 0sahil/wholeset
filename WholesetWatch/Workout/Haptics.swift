// SPDX-License-Identifier: GPL-3.0-or-later

import WatchKit

/// The Watch's haptic patterns used by the workout flow.
enum Haptics {
    /// Plays `type`. During a workout session this also works while the screen is off.
    static func play(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }
}
