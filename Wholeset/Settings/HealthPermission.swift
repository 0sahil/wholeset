// SPDX-License-Identifier: GPL-3.0-or-later

import HealthKit
import Observation
import os
import WholesetKit

/// Apple Health permission as far as iOS reveals it.
///
/// iOS tells an app only whether it may *save* a type; whether it may read one is never
/// revealed. The status therefore reflects saving workouts, which the Watch needs to put
/// workouts in Fitness. The request asks for the same types the Watch uses.
@Observable
final class HealthPermission {
    /// What iOS reports for saving workouts.
    enum Status: Equatable {
        /// Health is not available on this device.
        case unavailable
        /// The user has not been asked yet.
        case notDetermined
        /// Saving workouts is allowed.
        case allowed
        /// Saving workouts was turned off.
        case denied
    }

    private(set) var status: Status = .notDetermined

    @ObservationIgnored private let store = HKHealthStore()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.wholeset", category: "Health")

    init() {
        refresh()
    }

    /// Reads the status again (for example when the app returns to the foreground).
    func refresh() {
        guard HKHealthStore.isHealthDataAvailable() else {
            status = .unavailable
            return
        }
        switch store.authorizationStatus(for: HKObjectType.workoutType()) {
        case .sharingAuthorized: status = .allowed
        case .sharingDenied: status = .denied
        case .notDetermined: status = .notDetermined
        @unknown default: status = .notDetermined
        }
    }

    /// Shows the system Health permission sheet (only if the user has not answered yet).
    func request() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await store.requestAuthorization(toShare: HealthAccess.shareTypes, read: HealthAccess.readTypes)
        } catch {
            logger.error("Health authorization failed: \(error, privacy: .public)")
        }
        refresh()
    }
}
