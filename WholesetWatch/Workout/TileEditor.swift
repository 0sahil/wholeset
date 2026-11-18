// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation
import WatchKit
import WholesetKit

/// The selected weight or reps tile and its Crown edit.
///
/// While a tile is selected the Crown changes an in-memory ``CrownEdit``, not the store:
/// a detent only updates this object, so a fast turn costs one small re-render per detent
/// and no SwiftData write. The edit is written to the current set and saved when the Crown
/// pauses (``saveDelay`` after the last detent), when the tile is released (tap, the
/// ``idleRelease`` timeout, the menu, leaving the page) and before a set is logged. A crash
/// mid-edit can lose only the edit since the last pause; logged sets are saved by the engine
/// the moment they are logged.
///
/// The Crown profile (speed and detents per step) and the weight scale are taken when a tile
/// is selected and kept until it is released, so settings arriving from iCloud mid-edit
/// never change a turn in progress.
@Observable
final class TileEditor {
    /// The selected tile, if any.
    private(set) var selection: ValueTile?
    /// The edit of the selected tile.
    private(set) var edit: CrownEdit?
    /// How the Crown edits the selected tile.
    private(set) var profile: CrownProfile?

    @ObservationIgnored private let controller: WorkoutController
    /// The set the edit belongs to; an edit is never written to any other set.
    @ObservationIgnored private var setID: UUID?
    /// The weight scale the edit's steps are in.
    @ObservationIgnored private var scale: WeightScale?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var releaseTask: Task<Void, Never>?

    /// Quiet time after the last detent before the edit is saved.
    static let saveDelay: Duration = .milliseconds(500)
    /// Time without input after which a selected tile is released.
    static let idleRelease: Duration = .seconds(4)
    /// The highest rep count the Crown reaches.
    static let maxReps = 100
    /// Detents in a Crown window: the reps range, so weight and reps feel alike.
    static let crownSpan = maxReps

    init(controller: WorkoutController) {
        self.controller = controller
    }

    // MARK: Selection

    /// Selects `tile`, or releases it if it is already selected.
    func toggle(_ tile: ValueTile) {
        if selection == tile {
            release()
        } else {
            select(tile)
        }
    }

    /// Selects `tile`, saving any edit of the other tile first.
    func select(_ tile: ValueTile) {
        save()
        let profile = tile == .weight ? controller.weightCrown : controller.repsCrown
        let scale = controller.scale
        guard let engine = controller.engine, let set = engine.currentSet,
              let edit = makeEdit(for: tile, profile: profile, scale: scale) else {
            clear()
            return
        }
        selection = tile
        self.edit = edit
        self.profile = profile
        self.scale = scale
        setID = set.id
        controller.tileEditingChanged(isEditing: true)
        restartReleaseTimer()
    }

    /// Saves the edit and deselects the tile.
    func release() {
        save()
        clear()
    }

    private func clear() {
        saveTask?.cancel()
        releaseTask?.cancel()
        let wasEditing = selection != nil
        selection = nil
        edit = nil
        profile = nil
        scale = nil
        setID = nil
        if wasEditing {
            controller.tileEditingChanged(isEditing: false)
        }
    }

    // MARK: Crown

    /// The Crown reported detent `position` for the selected tile.
    func crownMoved(to position: Int) {
        guard var edit else { return }
        let changed = edit.crownMoved(to: position)
        // Part of a step still moves the position, which the Crown binding reads back.
        guard edit != self.edit else { return }
        self.edit = edit
        guard changed else { return }
        if profile?.usesSystemHaptics == false {
            Haptics.play(.click)
        }
        scheduleSave()
        restartReleaseTimer()
    }

    /// The Crown stopped turning: give the next turn room both ways.
    func crownIdle() {
        guard var edit else { return }
        edit.recentre()
        guard edit != self.edit else { return }
        self.edit = edit
    }

    // MARK: VoiceOver

    /// VoiceOver's adjustable action on `tile`: one step up or down, saved at once.
    func adjust(_ tile: ValueTile, by delta: Int) {
        if selection == tile, var edit {
            guard edit.step(by: delta) else { return }
            self.edit = edit
            save()
            restartReleaseTimer()
            return
        }
        let scale = controller.scale
        guard var oneOff = makeEdit(for: tile, profile: CrownProfile(rate: .low), scale: scale),
              oneOff.step(by: delta) else { return }
        write(oneOff.value, to: tile, scale: scale)
        controller.commitEdits()
    }

    // MARK: Saving

    /// Writes the edit to the current set and saves, if it changed anything.
    func save() {
        saveTask?.cancel()
        guard var edit, let selection, edit.hasUnsavedChange else { return }
        guard let set = controller.engine?.currentSet, set.id == setID else {
            // The set changed under the edit (it should not); drop the edit rather than
            // write it to the wrong set.
            clear()
            return
        }
        write(edit.value, to: selection, scale: scale ?? controller.scale)
        controller.commitEdits()
        edit.markSaved()
        self.edit = edit
    }

    private func write(_ value: Int, to tile: ValueTile, scale: WeightScale) {
        switch tile {
        case .weight: controller.setWeight(scale.kilograms(forSteps: value))
        case .reps: controller.setReps(value)
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private func restartReleaseTimer() {
        releaseTask?.cancel()
        releaseTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleRelease)
            guard !Task.isCancelled else { return }
            self?.release()
        }
    }

    // MARK: Reading

    /// An edit of `tile` on the current set, starting from what the set shows.
    private func makeEdit(for tile: ValueTile, profile: CrownProfile, scale: WeightScale) -> CrownEdit? {
        guard let engine = controller.engine, let entry = engine.currentEntry, let set = engine.currentSet(of: entry) else {
            return nil
        }
        let values = engine.values(for: set)
        switch tile {
        case .weight:
            let start = values.weightKg ?? entry.exercise?.equipment.startingWeightKilograms(in: scale.unit) ?? 0
            return CrownEdit(
                value: scale.steps(forKilograms: start),
                isStored: values.weightKg != nil,
                bounds: 0...scale.maximumSteps,
                span: Self.crownSpan,
                detentsPerStep: profile.detentsPerStep
            )
        case .reps:
            return CrownEdit(
                value: values.reps ?? entry.repLow ?? 0,
                isStored: values.reps != nil,
                bounds: 0...Self.maxReps,
                span: Self.crownSpan,
                detentsPerStep: profile.detentsPerStep
            )
        }
    }

    /// The edit of `tile` when it is selected and should be shown in place of the stored value.
    func shownEdit(for tile: ValueTile) -> CrownEdit? {
        guard selection == tile, let edit, edit.showsValue else { return nil }
        return edit
    }
}
