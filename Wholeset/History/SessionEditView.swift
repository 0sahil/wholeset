// SPDX-License-Identifier: GPL-3.0-or-later

import Observation
import SwiftData
import SwiftUI
import WholesetKit

/// The session editor's state: a draft copy, so Cancel throws every change away.
@Observable
final class SessionEditorModel {
    var draft: SessionDraft

    init(draft: SessionDraft) {
        self.draft = draft
    }
}

/// Fixes a finished workout in a sheet: each logged set's weight, reps and warm-up flag,
/// deleting and adding sets, the notes, or deleting the whole workout. Nothing is written
/// until Done, which saves once.
///
/// The warm-up flag is changed from a menu on each set's label ("Set 2 ⌃⌄"), also offered
/// in the set's context menu.
struct SessionEditView: View {
    @State private var model: SessionEditorModel
    @State private var confirmsDeletion = false
    @State private var confirmsDiscard = false
    @State private var saveFailed = false
    @FocusState private var focus: SetField?
    private let asksToDeleteOnAppear: Bool
    private let onDelete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// How long the sheet takes to slide up; a dialog presented earlier is dropped.
    private static let presentationDelay: Duration = .milliseconds(600)

    /// - Parameters:
    ///   - draft: The workout to edit.
    ///   - confirmsDeletionInitially: Shows the delete confirmation once the sheet is up (demo harness).
    ///   - onDelete: Called when the user confirms deleting the workout, just before the
    ///     sheet closes. The presenter deletes it once the sheet is gone.
    init(draft: SessionDraft, confirmsDeletionInitially: Bool = false, onDelete: @escaping () -> Void) {
        _model = State(initialValue: SessionEditorModel(draft: draft))
        self.asksToDeleteOnAppear = confirmsDeletionInitially
        self.onDelete = onDelete
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                ForEach(model.draft.entries) { entry in
                    Section {
                        ForEach(entry.sets) { set in
                            SetEditorRow(model: model, entryID: entry.id, setID: set.id, focus: $focus)
                        }
                        .onDelete { model.draft.deleteSets(atOffsets: $0, inEntry: entry.id) }
                        Button("Add Set", systemImage: "plus") {
                            if let id = model.draft.addSet(toEntry: entry.id) {
                                focus = .reps(id)
                            }
                        }
                    } header: {
                        Text(HistoryFormat.exerciseName(entry.exerciseName))
                    } footer: {
                        if entry.sets.isEmpty {
                            Text("With no sets left, \(HistoryFormat.exerciseName(entry.exerciseName)) is removed from this workout when you tap Done.")
                        }
                    }
                }
                Section("Notes") {
                    TextField("Add a note", text: $model.draft.notes, axis: .vertical)
                        .lineLimit(2...8)
                        .focused($focus, equals: .notes)
                }
                Section {
                    Button("Delete Workout", role: .destructive) { confirmsDeletion = true }
                } footer: {
                    Text("Records are worked out again after you save.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) {
                        if model.draft.hasChanges {
                            confirmsDiscard = true
                        } else {
                            dismiss()
                        }
                    }
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm, action: save)
                        .disabled(!model.draft.canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Hide Keyboard", systemImage: "keyboard.chevron.compact.down") { focus = nil }
                }
            }
            .confirmationDialog("Discard your changes?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .confirmationDialog("Delete this workout?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
                Button("Delete Workout", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Its sets and notes are deleted from Wholeset on all your devices. The workout in Apple Fitness stays; delete it in the Fitness app if you want it gone too.")
            }
            .alert("Couldn't Save", isPresented: $saveFailed) {
                Button("OK", role: .cancel) { dismiss() }
            } message: {
                Text("This workout may have been deleted on another device.")
            }
        }
        .interactiveDismissDisabled(model.draft.hasChanges)
        .task {
            guard asksToDeleteOnAppear else { return }
            try? await Task.sleep(for: Self.presentationDelay)
            guard !Task.isCancelled else { return }
            confirmsDeletion = true
        }
    }

    private func save() {
        do {
            if try model.draft.apply(in: modelContext) {
                modelContext.saveLogged()
            }
            dismiss()
        } catch {
            modelContext.rollback()
            saveFailed = true
        }
    }
}

/// Which text field has focus.
enum SetField: Hashable {
    case weight(UUID)
    case reps(UUID)
    case notes
}

/// One set in the editor: delete button, label with the warm-up menu, weight and reps fields,
/// and what is wrong with them.
private struct SetEditorRow: View {
    let model: SessionEditorModel
    let entryID: UUID
    let setID: UUID
    var focus: FocusState<SetField?>.Binding

    @ScaledMetric(relativeTo: .body) private var weightWidth: CGFloat = 72
    @ScaledMetric(relativeTo: .body) private var repsWidth: CGFloat = 48

    var body: some View {
        let set = model.draft.set(id: setID)
        let weightProblem = model.draft.weightProblem(forSet: setID)
        let repsProblem = model.draft.repsProblem(forSet: setID)
        VStack(alignment: .leading, spacing: 4) {
            SideBySideOrStacked(spacing: 10, rowSpacing: 8) {
                HStack(spacing: 10) {
                    Button {
                        model.draft.deleteSet(id: setID)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, .red)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(String(localized: "Delete \(label)"))

                    // A row label, not a button look: plain text with a small neutral chevron.
                    Menu {
                        warmupToggle(isWarmup: set?.isWarmup ?? false)
                    } label: {
                        HStack(spacing: 4) {
                            Text(label)
                                .foregroundStyle(set?.isWarmup == true ? .secondary : .primary)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .imageScale(.small)
                        }
                        .fixedSize()
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .accessibilityLabel(label)
                    .accessibilityHint("Changes whether this is a warm-up")
                }

                HStack(spacing: 8) {
                    field(
                        text: Binding(
                            get: { model.draft.set(id: setID)?.weightText ?? "" },
                            set: { model.draft.setWeightText($0, forSet: setID) }
                        ),
                        prompt: "—",
                        keyboard: .decimalPad,
                        width: weightWidth,
                        isInvalid: weightProblem != nil,
                        focusValue: .weight(setID),
                        accessibilityLabel: String(localized: "\(label) weight in \(unitName)")
                    )
                    Text(verbatim: "\(unit.symbol) ×")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityHidden(true)
                    field(
                        text: Binding(
                            get: { model.draft.set(id: setID)?.repsText ?? "" },
                            set: { model.draft.setRepsText($0, forSet: setID) }
                        ),
                        prompt: "0",
                        keyboard: .numberPad,
                        width: repsWidth,
                        isInvalid: repsProblem != nil,
                        focusValue: .reps(setID),
                        accessibilityLabel: String(localized: "\(label) reps")
                    )
                }
            }
            if let message = message(weight: weightProblem, reps: repsProblem) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .contextMenu {
            warmupToggle(isWarmup: set?.isWarmup ?? false)
            Button("Delete Set", systemImage: "trash", role: .destructive) {
                model.draft.deleteSet(id: setID)
            }
        }
    }

    /// "Warm-up" or "Set 2".
    private var label: String {
        guard let entry = model.draft.entries.first(where: { $0.id == entryID }),
              let number = entry.number(ofSet: setID) else { return String(localized: "Warm-up") }
        return String(localized: "Set \(number)")
    }

    /// The unit the draft reads typed weights in.
    private var unit: WeightUnit { model.draft.unit }

    private var unitName: String {
        unit == .kg ? String(localized: "kilograms") : String(localized: "pounds")
    }

    private func warmupToggle(isWarmup: Bool) -> some View {
        Toggle("Warm-up", systemImage: "flame", isOn: Binding(
            get: { isWarmup },
            set: { model.draft.setWarmup($0, forSet: setID) }
        ))
    }

    private func field(
        text: Binding<String>,
        prompt: String,
        keyboard: UIKeyboardType,
        width: CGFloat,
        isInvalid: Bool,
        focusValue: SetField,
        accessibilityLabel: String
    ) -> some View {
        TextField(accessibilityLabel, text: text, prompt: Text(verbatim: prompt))
            .keyboardType(keyboard)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .focused(focus, equals: focusValue)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minWidth: width)
            .fixedSize(horizontal: true, vertical: false)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if isInvalid {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.red, lineWidth: 1.5)
                }
            }
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(isInvalid ? String(localized: "Not valid") : "")
    }

    private func message(weight: SetInput.WeightProblem?, reps: SetInput.RepsProblem?) -> String? {
        let maximum = SetInput.maximumWeight(in: unit).formatted(.number.precision(.fractionLength(0...2)))
        switch (weight, reps) {
        case (.notANumber?, _): return String(localized: "Enter the weight as a number, or leave it empty.")
        case (.negative?, _): return String(localized: "The weight can't be below 0.")
        case (.tooHeavy?, _): return String(localized: "Enter a weight of at most \(maximum) \(unit.symbol).")
        case (nil, .empty?): return String(localized: "Enter the reps.")
        case (nil, .notANumber?): return String(localized: "Enter the reps as a whole number.")
        case (nil, .outOfRange?): return String(localized: "Enter reps from 1 to 999.")
        case (nil, nil): return nil
        }
    }
}

/// Two views on one line, the first at the leading and the second at the trailing edge, when
/// both fit at their ideal widths; otherwise the second goes on its own line below the first.
/// Neither view is ever squeezed narrower than its ideal width, so short labels such as
/// "kg ×" never wrap one letter per line, whatever the text size.
private struct SideBySideOrStacked: Layout {
    /// The least space between the two views on one line.
    var spacing: CGFloat
    /// The space between the lines when stacked.
    var rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let naturalWidth = sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(sizes.count - 1, 0))
        let proposedWidth = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        if fitsOnOneLine(naturalWidth, proposal: proposal) {
            return CGSize(width: proposedWidth ?? naturalWidth, height: sizes.map(\.height).max() ?? 0)
        }
        let height = sizes.map(\.height).reduce(0, +) + rowSpacing * CGFloat(max(sizes.count - 1, 0))
        return CGSize(width: proposedWidth ?? (sizes.map(\.width).max() ?? 0), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let naturalWidth = sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(sizes.count - 1, 0))
        if fitsOnOneLine(naturalWidth, proposal: ProposedViewSize(width: bounds.width, height: bounds.height)) {
            // Leading view at the leading edge, the rest packed against the trailing edge.
            var x = bounds.maxX
            for (subview, size) in zip(subviews, sizes).dropFirst().reversed() {
                x -= size.width
                subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(size))
                x -= spacing
            }
            if let first = subviews.first, let size = sizes.first {
                first.place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(size))
            }
            return
        }
        var y = bounds.minY
        for (subview, size) in zip(subviews, sizes) {
            let width = min(size.width, bounds.width)
            subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: width, height: size.height))
            y += size.height + rowSpacing
        }
    }

    private func fitsOnOneLine(_ naturalWidth: CGFloat, proposal: ProposedViewSize) -> Bool {
        guard let width = proposal.width else { return true }
        return naturalWidth <= width
    }
}
