// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import WholesetKit

/// The running workout: the exercise page and the Stats page side by side (swipe
/// horizontally), plus the ••• menu and the End confirmation as sheets.
struct WorkoutPagesView: View {
    @Bindable var controller: WorkoutController

    var body: some View {
        TabView(selection: $controller.page) {
            ExerciseTab(controller: controller)
                .tag(WorkoutPage.exercise)
            StatsView(controller: controller)
                .tag(WorkoutPage.stats)
        }
        .tabViewStyle(.page)
        .containerBackground(.black, for: .tabView)
        .sheet(item: $controller.sheet) { sheet in
            switch sheet {
            case .menu:
                WorkoutMenuView(controller: controller)
            case .endConfirm:
                EndConfirmView(controller: controller)
            }
        }
    }
}

/// The exercise page: rest countdown while resting, otherwise the current set (or the
/// exercise's "done" state). Owns the Digital Crown: with a tile selected it edits that
/// value, with none it moves between exercises.
private struct ExerciseTab: View {
    let controller: WorkoutController

    @State private var selection: ValueTile?
    @State private var interactions = 0
    @FocusState private var crownFocused: Bool

    /// Seconds of no input after which a selected tile is released.
    private static let idleRelease: Duration = .seconds(4)
    private static let maxReps = 100

    var body: some View {
        Group {
            if let rest = controller.rest {
                RestView(
                    rest: rest,
                    clock: controller.clock,
                    extend: controller.extendRest,
                    skip: controller.skipRest
                )
            } else if let engine = controller.engine, let entry = engine.currentEntry {
                crownHost(engine: engine, entry: entry)
            } else {
                Text("This workout has no exercises.")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: applyInitialSelection)
        .onDisappear(perform: release)
        .onChange(of: controller.rest != nil) { _, resting in
            if !resting { crownFocused = true }
        }
        .onChange(of: controller.sheet == nil) { _, closed in
            // A sheet takes focus; give the Crown back to the page when it closes.
            if closed { crownFocused = true }
        }
    }

    @ViewBuilder
    private func crownHost(engine: WorkoutEngine, entry: SessionExercise) -> some View {
        let range = crownRange(engine: engine)
        Group {
            if let set = engine.currentSet(of: entry) {
                ExercisePage(
                    controller: controller,
                    engine: engine,
                    entry: entry,
                    set: set,
                    selection: selection,
                    toggle: toggle,
                    adjust: { tile, delta in adjust(tile, by: delta, engine: engine, entry: entry) },
                    openMenu: openMenu,
                    log: {
                        release()
                        controller.logSet()
                    }
                )
            } else {
                ExerciseDonePage(controller: controller, engine: engine, entry: entry, openMenu: openMenu)
            }
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.5, perform: openMenu)
        .focusable()
        .focused($crownFocused)
        .focusEffectDisabled()
        .digitalCrownRotation(
            detent: crownBinding(engine: engine, entry: entry),
            from: range.lowerBound,
            through: range.upperBound,
            by: 1,
            sensitivity: crownSensitivity,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear { crownFocused = true }
        .task(id: interactions) {
            guard selection != nil else { return }
            try? await Task.sleep(for: Self.idleRelease)
            guard !Task.isCancelled else { return }
            release()
        }
    }

    // MARK: Crown

    private var crownSensitivity: DigitalCrownRotationalSensitivity {
        switch selection {
        case .weight: .high
        case .reps: .medium
        case nil: .low
        }
    }

    private func crownRange(engine: WorkoutEngine) -> ClosedRange<Int> {
        switch selection {
        case .weight: 0...controller.scale.maximumSteps
        case .reps: 0...Self.maxReps
        // Never an empty range; extra detents past the last exercise are clamped by the engine.
        case nil: 0...max(1, engine.entries.count - 1)
        }
    }

    private func crownBinding(engine: WorkoutEngine, entry: SessionExercise) -> Binding<Int> {
        Binding(
            get: { crownValue(engine: engine, entry: entry) },
            set: { newValue in
                guard newValue != crownValue(engine: engine, entry: entry) else { return }
                switch selection {
                case .weight:
                    controller.setWeight(controller.scale.kilograms(forSteps: newValue))
                    interactions += 1
                case .reps:
                    controller.setReps(min(max(newValue, 0), Self.maxReps))
                    interactions += 1
                case nil:
                    controller.selectEntry(at: newValue)
                }
            }
        )
    }

    private func crownValue(engine: WorkoutEngine, entry: SessionExercise) -> Int {
        let values = engine.currentSet.map(engine.values(for:)) ?? SetValues()
        switch selection {
        case .weight:
            return controller.scale.steps(forKilograms: values.weightKg ?? startingWeight(entry) ?? 0)
        case .reps:
            return values.reps ?? entry.repLow ?? 0
        case nil:
            return engine.currentIndex
        }
    }

    private func startingWeight(_ entry: SessionExercise) -> Double? {
        entry.exercise?.equipment.startingWeightKilograms(in: controller.unit)
    }

    // MARK: Selection

    private func toggle(_ tile: ValueTile) {
        if selection == tile {
            release()
        } else {
            if selection != nil { controller.commitEdits() }
            selection = tile
            crownFocused = true
            interactions += 1
        }
    }

    private func release() {
        guard selection != nil else { return }
        selection = nil
        controller.commitEdits()
    }

    private func openMenu() {
        release()
        controller.sheet = .menu
    }

    private func applyInitialSelection() {
        if let initial = controller.initialTileSelection {
            selection = initial
            controller.initialTileSelection = nil
        }
    }

    /// VoiceOver's adjustable action: one step up or down.
    private func adjust(_ tile: ValueTile, by delta: Int, engine: WorkoutEngine, entry: SessionExercise) {
        let values = engine.currentSet.map(engine.values(for:)) ?? SetValues()
        switch tile {
        case .weight:
            let steps = controller.scale.steps(forKilograms: values.weightKg ?? startingWeight(entry) ?? 0)
            controller.setWeight(controller.scale.kilograms(forSteps: steps + delta))
        case .reps:
            controller.setReps(min(max((values.reps ?? entry.repLow ?? 0) + delta, 0), Self.maxReps))
        }
        controller.commitEdits()
    }
}
