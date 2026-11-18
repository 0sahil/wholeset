// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import WholesetKit

/// The ••• menu: set changes for the current exercise, the exercise list, and End.
struct WorkoutMenuView: View {
    let controller: WorkoutController

    var body: some View {
        NavigationStack {
            if let engine = controller.engine {
                List {
                    Button {
                        controller.addSet()
                        controller.sheet = nil
                    } label: {
                        Label("Add set", systemImage: "plus")
                    }
                    Button {
                        controller.removeSet()
                        controller.sheet = nil
                    } label: {
                        Label("Remove set", systemImage: "minus")
                    }
                    .disabled(!engine.canRemoveSet)
                    Button {
                        controller.toggleWarmup()
                        controller.sheet = nil
                    } label: {
                        Label(
                            engine.currentSet?.isWarmup == true ? "Mark as working set" : "Mark as warm-up",
                            systemImage: "flame"
                        )
                    }
                    .disabled(engine.currentSet == nil)
                    NavigationLink {
                        AllExercisesView(controller: controller, engine: engine)
                    } label: {
                        Label("All exercises", systemImage: "list.bullet")
                    }
                    Button(role: .destructive) {
                        controller.sheet = .endConfirm
                    } label: {
                        Label("End workout", systemImage: "xmark.circle")
                    }
                }
                .navigationTitle(engine.currentEntry?.exercise?.name ?? "")
            }
        }
    }
}

/// Every exercise with its progress; tap one to go to it.
private struct AllExercisesView: View {
    let controller: WorkoutController
    let engine: WorkoutEngine

    var body: some View {
        List(Array(engine.entries.enumerated()), id: \.element.id) { index, entry in
            let progress = engine.progress(of: entry)
            let isCurrent = index == engine.currentIndex
            Button {
                controller.selectEntry(at: index)
                controller.sheet = nil
            } label: {
                HStack {
                    Text(entry.exercise?.name ?? "")
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Text("\(progress.completed)/\(progress.total)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(progress.isDone ? Theme.accent : .secondary)
                }
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.tile)
                    .strokeBorder(isCurrent ? Color.white : .clear, lineWidth: 2)
            )
            .accessibilityValue(
                inflectedString("\(progress.completed) of ^[\(progress.total) set](inflect: true) logged")
            )
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
        }
        .navigationTitle(engine.session.name)
    }
}
