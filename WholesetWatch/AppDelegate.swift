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
    /// Library seed, sync dedupe and the starter-routine decision, or `nil` without a store.
    let store: StoreCoordinator?

    private let notificationPresenter: NotificationPresenter

    override init() {
        let launch = Self.makeLaunch()
        container = launch.container
        controller = launch.controller
        store = launch.store
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

    private static func makeLaunch() -> (container: ModelContainer?, controller: WorkoutController?, store: StoreCoordinator?) {
        #if DEBUG
        if let demo = DemoHarness.requestedScreen() {
            return DemoHarness.makeLaunch(for: demo)
        }
        #endif
        let opened = WholesetStore.loadAppContainer(cloudKit: WholesetStore.cloudKitEnabledByDefault)
        guard let container = opened.container, let mode = opened.mode else { return (nil, nil, nil) }
        // The Watch creates the starter routines itself, once it has seen what iCloud holds.
        let store = StoreCoordinator(container: container, sync: SyncMonitor(mode: mode), policy: .automatic)
        store.start()
        let controller = WorkoutController(
            context: container.mainContext,
            health: HealthKitWorkoutManager(),
            alerts: RestAlertScheduler()
        )
        connect(store, to: controller)
        return (container, controller, store)
    }

    /// Settings arriving from iCloud reach the workout; merges wait until no workout runs.
    static func connect(_ store: StoreCoordinator, to controller: WorkoutController) {
        store.onMaintenance = { [weak controller] in
            controller?.refreshSettings()
        }
        store.defersMaintenance = { [weak controller] in
            controller?.isWorkoutRunning ?? false
        }
    }
}
