// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import os
import UserNotifications

/// Makes sure the end of a rest produces exactly one alert.
///
/// - While the app is frontmost and active, nothing is scheduled; the controller plays
///   the `.notification` haptic itself when the rest ends.
/// - While it is not (wrist down, screen off, another app), one local notification is
///   pending for the rest's end date, and the controller stays silent.
///
/// ``sync(restEnd:body:now:)`` is called after every change that matters (rest started,
/// +30 s, skip, workout ended, app active or not) and replaces or removes the pending
/// request accordingly. ``NotificationPresenter`` covers the remaining race, a
/// notification firing just as the app becomes active, by suppressing it then.
@MainActor
final class RestAlertScheduler {
    static let requestIdentifier = "wholeset.rest-end"

    /// Whether notifications may be shown. Without permission, the controller plays the
    /// haptic even when the app is not active, as the only alert left.
    private(set) var isAuthorized = false
    /// Whether the app is frontmost and active.
    private(set) var isAppActive = true
    /// `false` in DEBUG demos, so they never schedule or prompt.
    private let isEnabled: Bool

    private var scheduled: (end: Date, body: String, fireDate: Date)?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.wholeset.watchkitapp", category: "RestAlert")

    /// When the scheduled notification will actually fire. Can be up to a second after
    /// the rest's end, because a notification trigger needs a positive interval.
    var pendingFireDate: Date? { scheduled?.fireDate }

    /// The rest end the scheduled notification is for.
    var scheduledRestEnd: Date? { scheduled?.end }

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
        if isEnabled {
            // A request left by a previous run (crash or force quit mid-rest) belongs to a
            // rest this run knows nothing about; the restored rest is rescheduled if needed.
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.requestIdentifier])
        }
    }

    /// Asks for permission to alert. Shows the system prompt only the first time.
    func requestAuthorization() async {
        guard isEnabled else { return }
        do {
            isAuthorized = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            logger.error("Notification authorization failed: \(error, privacy: .public)")
            isAuthorized = false
        }
    }

    /// Reads the current permission without prompting.
    func refreshAuthorization() async {
        guard isEnabled else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// Records whether the app is active. Call before ``sync(restEnd:body:now:)``.
    func setAppActive(_ active: Bool) {
        isAppActive = active
        if active, isEnabled {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.requestIdentifier])
        }
    }

    /// Makes the pending notification match the current rest.
    ///
    /// - Parameters:
    ///   - restEnd: When the running rest ends, or `nil` if none is running.
    ///   - body: The notification text, e.g. "Bench Press · set 2 of 3".
    ///   - now: The current time.
    func sync(restEnd: Date?, body: String, now: Date) {
        guard isEnabled else { return }
        let wanted = restEnd.flatMap { end in (!isAppActive && end > now) ? end : nil }
        if wanted == nil, scheduled == nil { return }
        if let scheduled, scheduled.end == wanted, scheduled.body == body { return }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestIdentifier])
        guard let wanted else {
            scheduled = nil
            return
        }
        let interval = max(1, wanted.timeIntervalSince(now))
        scheduled = (wanted, body, now.addingTimeInterval(interval))

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Rest over")
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: Self.requestIdentifier, content: content, trigger: trigger)
        let logger = logger
        center.add(request) { error in
            if let error {
                logger.error("Could not schedule rest alert: \(error, privacy: .public)")
            }
        }
    }
}

/// Decides how a notification is shown while the app is in the foreground.
///
/// A rest notification is only pending while the app is inactive (for example dimmed
/// with the wrist down on an always-on Watch), so it is shown then. If it fires just as
/// the app turns active, it is suppressed because the in-app haptic covers it.
nonisolated final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let isAppActive: @MainActor @Sendable () -> Bool

    init(isAppActive: @escaping @MainActor @Sendable () -> Bool) {
        self.isAppActive = isAppActive
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await isAppActive() ? [] : [.banner, .list, .sound]
    }
}
