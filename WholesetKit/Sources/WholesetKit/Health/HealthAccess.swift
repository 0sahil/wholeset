// SPDX-License-Identifier: GPL-3.0-or-later

import HealthKit

/// The Apple Health data types Wholeset uses, shared by the Watch (which records workouts)
/// and the iPhone (which can ask for the same permission up front).
public enum HealthAccess {
    /// Written by the Watch's workout builder: the workout, its active energy and heart rate.
    public static var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate)]
    }

    /// Read during a workout for the live display and the summary.
    public static var readTypes: Set<HKObjectType> {
        [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
    }
}
