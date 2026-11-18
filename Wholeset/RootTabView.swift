// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The iPhone app's top-level sections.
enum AppTab: Hashable {
    case plan
    case history
    case exercises
    case settings
}

/// The tab bar holding the four sections. Each tab owns its own navigation stack.
struct RootTabView: View {
    @State private var selection: AppTab = .plan

    var body: some View {
        TabView(selection: $selection) {
            Tab("Plan", systemImage: "calendar", value: AppTab.plan) {
                TabPlaceholderView(
                    title: "Plan",
                    systemImage: "calendar",
                    emptyTitle: "No Routines Yet",
                    message: "Your routines and weekly plan will appear here."
                )
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                TabPlaceholderView(
                    title: "History",
                    systemImage: "clock.arrow.circlepath",
                    emptyTitle: "No Workouts Yet",
                    message: "Finished workouts will appear here."
                )
            }
            Tab("Exercises", systemImage: "dumbbell", value: AppTab.exercises) {
                TabPlaceholderView(
                    title: "Exercises",
                    systemImage: "dumbbell",
                    emptyTitle: "No Exercises Yet",
                    message: "The exercise library will appear here."
                )
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                TabPlaceholderView(
                    title: "Settings",
                    systemImage: "gearshape",
                    emptyTitle: "Nothing to Set Yet",
                    message: "Units, rest times and sync status will appear here."
                )
            }
        }
    }
}

#Preview {
    RootTabView()
}
