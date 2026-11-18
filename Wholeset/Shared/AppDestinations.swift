// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftData
import SwiftUI
import WholesetKit

extension View {
    /// Registers the screens of ``AppDestination`` on the enclosing navigation stack.
    func appDestinations() -> some View {
        navigationDestination(for: AppDestination.self) { destination in
            AppDestinationView(destination: destination)
        }
    }
}

/// The screen for one ``AppDestination``.
private struct AppDestinationView: View {
    let destination: AppDestination

    var body: some View {
        switch destination {
        case .session(let id):
            SessionDetailView(sessionID: id)
        case .exercise(let id):
            ExerciseLoader(id: id) { ExerciseDetailView(exercise: $0) }
        case .exerciseSettings(let id):
            ExerciseLoader(id: id) { ExerciseSettingsView(exercise: $0) }
        case .repsByWeight(let id):
            ExerciseLoader(id: id) { RepsByWeightView(exercise: $0) }
        }
    }
}

/// Looks up an exercise by `id` and shows `content` for it, live: renaming or a sync
/// merge updates the screen.
private struct ExerciseLoader<Content: View>: View {
    @Query private var matches: [Exercise]
    private let content: (Exercise) -> Content

    init(id: UUID, @ViewBuilder content: @escaping (Exercise) -> Content) {
        _matches = Query(filter: #Predicate<Exercise> { $0.id == id })
        self.content = content
    }

    var body: some View {
        if let exercise = matches.first {
            content(exercise)
        } else {
            ContentUnavailableView("Exercise Not Found", systemImage: "questionmark")
        }
    }
}
