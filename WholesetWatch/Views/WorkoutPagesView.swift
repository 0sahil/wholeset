// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import WholesetKit

/// The running workout: Now Playing, the exercise page and the Stats page side by side
/// (swipe horizontally; it opens on the exercise page), the elapsed clock in the top bar of
/// all three, plus the ••• menu and the End confirmation as sheets.
///
/// The Digital Crown belongs to the page on screen. The `TabView` keeps the pages next to
/// the visible one alive, so each page takes the Crown only while it is showing and lets go
/// when it is swiped away: the exercise page (edit a tile or move between exercises), Stats
/// (scroll), and on Now Playing none of the app's views, so the system view sets the volume.
///
/// Likewise only one control at a time is the Double Tap primary action: "Log set" or the
/// done page's "Next", and only while the exercise page is showing with no sheet up.
struct WorkoutPagesView: View {
    @Bindable var controller: WorkoutController
    /// Counts sheets that finished closing, so the exercise page can take the Crown back.
    @State private var sheetDismissals = 0

    var body: some View {
        NavigationStack {
            TabView(selection: $controller.page) {
                NowPlayingPage()
                    .tag(WorkoutPage.nowPlaying)
                ExerciseTab(controller: controller, sheetDismissals: sheetDismissals)
                    .tag(WorkoutPage.exercise)
                StatsView(controller: controller, sheetDismissals: sheetDismissals)
                    .tag(WorkoutPage.stats)
            }
            .tabViewStyle(.page)
            .containerBackground(.black, for: .tabView)
            // On the TabView rather than on each page, so the clock stays put while swiping.
            // On Now Playing the page title sits here too, leaving the system view the
            // whole content area.
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let clock = controller.clock {
                        if controller.page == .nowPlaying {
                            NowPlayingTopBar(clock: clock, rest: controller.isPaused ? nil : controller.rest)
                        } else {
                            WorkoutClockLabel(clock: clock)
                        }
                    }
                }
            }
        }
        .containerBackground(.black, for: .navigation)
        .sheet(item: $controller.sheet, onDismiss: { sheetDismissals += 1 }) { sheet in
            switch sheet {
            case .menu:
                WorkoutMenuView(controller: controller)
            case .endConfirm:
                EndConfirmView(controller: controller)
            }
        }
    }
}

/// Which view on the exercise page gets the Digital Crown.
enum CrownTarget: Hashable {
    /// The page itself: edits the selected tile, or moves between exercises.
    case page
    /// The scrolling done page: the Crown scrolls it.
    case doneTable
}

/// When the exercise page's Crown target takes focus: each time it appears, and each time
/// this value changes while ``isEligible``.
struct CrownClaim: Equatable {
    /// The app is active, the exercise page is the one showing and no sheet is up.
    var isEligible: Bool
    /// Counts sheets that finished closing: a sheet takes focus and does not give it back.
    var sheetDismissals: Int
}

/// What a Crown target needs to take focus.
struct CrownFocus {
    let binding: FocusState<CrownTarget?>.Binding
    /// The exercise page's focus scope, in which the target prefers default focus.
    let scope: Namespace.ID
    let claim: CrownClaim
    /// Whether the exercise page is the page on screen. When it is not, its Crown view
    /// cannot be focused at all, so it never keeps the Crown from Now Playing or Stats.
    let isPageShowing: Bool
}

extension View {
    /// Makes this view the Crown's `target`. It takes focus from its own `task`, so only
    /// once it is in the hierarchy (an assignment made earlier is dropped), and it is the
    /// scope's default focus whenever the system picks one.
    func claimsCrown(_ target: CrownTarget, with focus: CrownFocus) -> some View {
        self
            .focused(focus.binding, equals: target)
            .prefersDefaultFocus(in: focus.scope)
            .task(id: focus.claim) {
                guard focus.claim.isEligible else { return }
                focus.binding.wrappedValue = target
            }
    }
}

/// The identity of the page's Crown view. A new identity gives a fresh system Crown
/// rotation, starting from the binding's value, so nothing turned in one context is reported
/// into the next.
struct CrownContextID: Hashable {
    /// The tile editor's Crown context: changes on every selection and release.
    let context: Int
    /// Exercise navigation's range, so adding or removing an exercise starts afresh too;
    /// `nil` while a tile is selected, whose range moves between turns by design.
    let navigationRange: ClosedRange<Int>?
}

/// The exercise page's own Crown: edits the selected tile, or moves between exercises.
/// Applied to the set page and the static done page only. The scrolling done page has no
/// such ancestor, so nothing competes with its ScrollView for the Crown.
///
/// The Crown lives on an invisible layer behind the page, identified by ``context``, so a
/// new Crown context replaces only that layer (which takes focus back from its own `task`),
/// never the page's content or the VoiceOver cursor.
struct PageCrown: ViewModifier {
    let binding: Binding<Int>
    let range: ClosedRange<Int>
    let profile: CrownProfile
    let onIdle: () -> Void
    let focus: CrownFocus
    let context: CrownContextID
    /// Hides the system's Crown indicator: it shows the Crown window, not the edited value.
    let hidesIndicator: Bool

    func body(content: Content) -> some View {
        content
            .background {
                Color.clear
                    .focusable(focus.isPageShowing)
                    .claimsCrown(.page, with: focus)
                    .focusEffectDisabled()
                    .digitalCrownRotation(
                        detent: binding,
                        from: range.lowerBound,
                        through: range.upperBound,
                        by: 1,
                        sensitivity: DigitalCrownRotationalSensitivity(profile.rate),
                        isContinuous: false,
                        // With several detents per step the tile editor plays one click per step instead.
                        isHapticFeedbackEnabled: profile.usesSystemHaptics,
                        onIdle: onIdle
                    )
                    .scrollIndicators(hidesIndicator ? .hidden : .automatic)
                    .accessibilityHidden(true)
                    .id(context)
            }
    }
}

extension DigitalCrownRotationalSensitivity {
    /// The system sensitivity for a WholesetKit Crown rate.
    init(_ rate: CrownRate) {
        switch rate {
        case .low: self = .low
        case .medium: self = .medium
        case .high: self = .high
        }
    }
}

/// The exercise page: rest countdown while resting, otherwise the current set (or the
/// exercise's "done" state). With a tile selected the Crown edits that value, with none it
/// moves between exercises, except on a done page too tall for the screen, where it
/// scrolls that page instead.
private struct ExerciseTab: View {
    let controller: WorkoutController
    /// Counts sheets that finished closing.
    let sheetDismissals: Int

    @State private var editor: TileEditor
    @FocusState private var crownFocus: CrownTarget?
    @Namespace private var crownScope
    @Environment(\.scenePhase) private var scenePhase

    init(controller: WorkoutController, sheetDismissals: Int) {
        self.controller = controller
        self.sheetDismissals = sheetDismissals
        _editor = State(initialValue: TileEditor(controller: controller))
    }

    var body: some View {
        Group {
            if let rest = controller.rest {
                RestView(rest: rest, extend: controller.extendRest, skip: controller.skipRest)
            } else if let engine = controller.engine, let entry = engine.currentEntry {
                crownHost(engine: engine, entry: entry)
            } else {
                EmptyWorkoutPage(controller: controller, openMenu: openMenu)
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .focusScope(crownScope)
        .onAppear {
            // Settings changed on iPhone apply from the next time this page appears at the latest.
            controller.refreshSettings()
            applyInitialSelection()
        }
        .onDisappear(perform: editor.release)
        .onChange(of: controller.page) { _, page in
            editor.release()
            // Swiped away: give the Crown up (to the Now Playing volume or the Stats scroll).
            // The claim takes it back when the exercise page shows again.
            if page != .exercise { crownFocus = nil }
        }
        .onChange(of: scenePhase) { _, phase in
            // Wrist down or app switch: save and let go of the tile.
            if phase != .active { editor.release() }
        }
    }

    private var crownFocusContext: CrownFocus {
        CrownFocus(
            binding: $crownFocus,
            scope: crownScope,
            claim: CrownClaim(
                isEligible: isInteractive,
                sheetDismissals: sheetDismissals
            ),
            isPageShowing: controller.page == .exercise
        )
    }

    /// The app is active, the exercise page is on screen and no sheet is up: the page may
    /// take the Crown, and its main button is the Double Tap primary action.
    private var isInteractive: Bool {
        scenePhase == .active && controller.page == .exercise && controller.sheet == nil
    }

    @ViewBuilder
    private func crownHost(engine: WorkoutEngine, entry: SessionExercise) -> some View {
        let focus = crownFocusContext
        let pageCrown = pageCrown(engine: engine, focus: focus)
        Group {
            if entry.isSkipped {
                ExerciseSkippedPage(controller: controller, engine: engine, entry: entry, openMenu: openMenu)
                    .modifier(pageCrown)
            } else if let set = engine.currentSet(of: entry) {
                ExercisePage(
                    controller: controller,
                    engine: engine,
                    entry: entry,
                    set: set,
                    selection: editor.selection,
                    weightEdit: editor.shownEdit(for: .weight),
                    repsEdit: editor.shownEdit(for: .reps),
                    toggle: toggle,
                    adjust: editor.adjust,
                    openMenu: openMenu,
                    isPrimaryAction: isInteractive,
                    applyHint: {
                        // Save any Crown edit first, so the hint is applied over it.
                        editor.release()
                        controller.applyProgressionHint()
                    },
                    log: {
                        // Save the edit first: the set is logged with what is on screen.
                        editor.release()
                        controller.logSet()
                    }
                )
                .modifier(pageCrown)
            } else {
                ExerciseDonePage(
                    controller: controller,
                    engine: engine,
                    entry: entry,
                    crownFocus: focus,
                    pageCrown: pageCrown,
                    isPrimaryAction: isInteractive,
                    openMenu: openMenu
                )
            }
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.5, perform: openMenu)
    }

    // MARK: Crown

    /// With a tile selected the Crown's detent is the edit's position (its value, at one
    /// detent per step), in a range that only moves while the Crown is idle (see `CrownEdit`).
    /// Speed and detents per step come from the synced Crown sensitivity, taken when the tile
    /// was selected. With no tile selected the Crown picks the exercise. Every switch between
    /// these gives the Crown a fresh identity (see `TileEditor`).
    private func pageCrown(engine: WorkoutEngine, focus: CrownFocus) -> PageCrown {
        let editor = editor
        if let edit = editor.edit, let profile = editor.profile {
            return PageCrown(
                binding: Binding(
                    get: { editor.edit?.position ?? edit.position },
                    set: { editor.crownMoved(to: $0) }
                ),
                range: edit.crownRange,
                profile: profile,
                onIdle: editor.crownIdle,
                focus: focus,
                context: CrownContextID(context: editor.crownContext, navigationRange: nil),
                hidesIndicator: true
            )
        }
        // Never an empty range; extra detents past the last exercise are clamped by the engine.
        let range = 0...max(1, engine.entries.count - 1)
        return PageCrown(
            binding: Binding(
                get: { engine.currentIndex },
                set: { newValue in
                    let current = engine.currentIndex
                    guard editor.admitsNavigation(to: newValue, from: current), newValue != current else { return }
                    controller.selectEntry(at: newValue)
                }
            ),
            range: range,
            profile: .exerciseNavigation,
            onIdle: editor.crownIdle,
            focus: focus,
            context: CrownContextID(context: editor.crownContext, navigationRange: range),
            hidesIndicator: false
        )
    }

    // MARK: Selection

    private func toggle(_ tile: ValueTile) {
        editor.toggle(tile)
        crownFocus = .page
    }

    private func openMenu() {
        editor.release()
        controller.openMenu()
    }

    private func applyInitialSelection() {
        if let initial = controller.initialTileSelection {
            editor.select(initial)
            controller.initialTileSelection = nil
        }
    }
}
