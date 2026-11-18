// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import UserNotifications
import WatchKit
import WholesetKit

/// Owns the app-wide objects, so they exist before SwiftUI builds a scene: the system
/// may ask the app to recover a running workout (``handleActiveWorkoutRecovery()``)
/// right at launch.
final class AppDelegate: NSObject, WKApplicationDelegate {
    /// The opened store, or `nil` if it could not be opened at all.
    let container: ModelContainer?
    /// The workout coordinator, or `nil` without a store.
    let controller: WorkoutController?

    private let notificationPresenter: NotificationPresenter

    override init() {
        let launch = Self.makeLaunch()
        container = launch.container
        controller = launch.controller
        let alerts = launch.controller?.alerts
        notificationPresenter = NotificationPresenter { alerts?.isAppActive ?? false }
        super.init()
        // Set before launch finishes, so a notification delivered at launch is routed here.
        UNUserNotificationCenter.current().delegate = notificationPresenter
    }

    func handleActiveWorkoutRecovery() {
        guard let controller else { return }
        Task {
            await controller.health.recoverActiveSession()
            controller.healthRecoveryFinished()
        }
    }

    private static func makeLaunch() -> (container: ModelContainer?, controller: WorkoutController?) {
        #if DEBUG
        if let demo = DemoHarness.requestedScreen() {
            return DemoHarness.makeLaunch(for: demo)
        }
        #endif
        let store = WholesetStore.loadAppContainer(cloudKit: WholesetStore.cloudKitEnabledByDefault)
        guard let container = store.container else { return (nil, nil) }
        let controller = WorkoutController(
            context: container.mainContext,
            health: HealthKitWorkoutManager(),
            alerts: RestAlertScheduler()
        )
        return (container, controller)
    }
}
