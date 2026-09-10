import SwiftUI
import WisentDesignSystem

extension CopiesView {
    // MARK: - Table

    /// One row per copy, with the checkout it duplicates beside it: the pass
    /// established that pair, and an operator deciding what to delete reads
    /// both halves.
    var table: some View {
        WisentTableFrame {
            Table(model.copies, selection: $selection) {
                TableColumn("COPY") { record in
                    Text(record.path)
                        .font(WisentTypeScale.identifier())
                        .foregroundStyle(
                            model.isKept(record) ? WisentDesign.muted : WisentDesign.ink
                        )
                        .strikethrough(model.isKept(record))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .help(record.path)
                        .frame(height: WisentAppLayout.tableRowHeight, alignment: .leading)
                }
                TableColumn("OF") { record in
                    Text(record.ownerLabel)
                        .font(WisentTypeScale.body())
                        .foregroundStyle(WisentDesign.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                TableColumn("SIZE") { record in
                    Text(record.sizeLabel)
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(WisentDesign.muted)
                        .lineLimit(1)
                }
                TableColumn("STATE") { record in
                    WisentStatusChip(
                        text: record.marks.isEmpty
                            ? "Clean"
                            : record.marks.joined(separator: " · "),
                        tone: record.marks.isEmpty ? .success : .warning
                    )
                }
                TableColumn("PASS") { record in
                    HStack(spacing: WisentDesign.Space.x2) {
                        WisentStatusChip(text: passLabel(record), tone: passTone(record))
                        WisentActionButton(action: keepAction(record))
                        if record.owner == nil {
                            WisentActionButton(action: claimAction(record))
                        }
                    }
                }
            }
            .tableStyle(.inset)
            .textSelection(.disabled)
        }
    }

    // MARK: - Marking a row

    /// Kept and claimed are the operator's own decisions, refused is the
    /// product's, so none of the three shares a tone or a word.
    func passLabel(_ record: CopyRecord) -> String {
        if model.isKept(record) { return "Kept" }
        if model.isClaimed(record) { return "Claimed" }
        if model.isRefused(record) { return "Refused" }
        return model.claimed.isEmpty ? "Removable" : "Out of pass"
    }

    func passTone(_ record: CopyRecord) -> WisentTone {
        if model.isKept(record) { return .info }
        if model.isClaimed(record) { return .warning }
        return model.isRefused(record) ? .warning : .neutral
    }

    /// One verb per row, named for what it does to this pass rather than for
    /// the flag it becomes.
    func keepAction(_ record: CopyRecord) -> WisentAction {
        WisentAction(model.isKept(record) ? "Include" : "Keep", kind: .plain) {
            model.toggleKept(record)
        }
    }

    /// Only a row the pass refuses for having no canonical checkout can be
    /// claimed: that is the one refusal an operator can answer, and claiming
    /// narrows the whole pass to what they name.
    func claimAction(_ record: CopyRecord) -> WisentAction {
        WisentAction(model.isClaimed(record) ? "Release" : "Claim", kind: .plain) {
            model.toggleClaimed(record)
        }
    }

    private func badges(for record: CopyRecord) -> [(String, WisentTone)] {
        let marks: [(String, WisentTone)] = record.marks.isEmpty
            ? [("Clean", .success)]
            : record.marks.map { ($0, .warning) }
        if model.isKept(record) { return [("Kept", .info)] + marks }
        if model.isClaimed(record) { return [("Claimed", .warning)] + marks }
        return marks
    }

    // MARK: - Inspector

    private var selectedCopy: CopyRecord? {
        guard let selection else { return nil }
        return model.copies.first { $0.id == selection }
    }

    @ViewBuilder
    var inspector: some View {
        if let record = selectedCopy {
            WisentInspector(
                eyebrow: record.sizeLabel,
                title: record.path,
                badges: badges(for: record)
            ) {
                if model.isKept(record) {
                    Text("Kept out of this pass as --except: not removed, not counted as removable, never refused.")
                        .font(WisentTypeScale.body())
                        .foregroundStyle(WisentDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                }
                if let refusal = model.refusals.first(where: { $0.path == record.path }) {
                    Text(refusal.sentence)
                        .font(WisentTypeScale.body())
                        .foregroundStyle(WisentDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                }
                WisentField(label: "Copy of", value: record.ownerLabel)
                WisentField(label: "Origin", value: record.originLabel)
                WisentField(label: "Apparent size", value: record.sizeLabel)
                WisentField(
                    label: "State",
                    value: record.marks.isEmpty
                        ? "Nothing uncommitted, every commit on a remote"
                        : record.marks.joined(separator: ", "),
                    tone: record.marks.isEmpty ? .success : .warning
                )
                WisentActionButton(action: keepAction(record))
                if record.owner == nil {
                    WisentActionButton(action: claimAction(record))
                }
            }
        } else {
            WisentInspector(
                eyebrow: "Copy",
                title: model.copyCount == .zero ? "Nothing scanned yet" : "No copy selected"
            ) {
                Text("Select a copy to see the checkout it duplicates and what removal would do.")
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - The decision

    /// Removing a copy deletes a directory from disk, which git cannot undo.
    /// What the preview reported is what this dialog lists, and the override
    /// is named again here because it is the one setting that destroys work.
    var removalDecision: some View {
        var lines = [
            "Every copy listed below is deleted from disk.",
            "The canonical checkout of each repository is never touched.",
            "\(copiedSize(model.removableBytes)) comes back if the pass applies.",
        ]
        if model.overridesRefusals {
            let losing = model.copiesLosingWork.count
            lines.append(
                losing == .zero
                    ? "The override is on; no listed copy carries work that exists nowhere else."
                    : "The override is on: \(counted(losing, "copy")) carries work that exists nowhere else."
            )
        }
        if !model.claimed.isEmpty {
            lines.append(
                "\(counted(model.claimed.count, "copy")) claimed as --only: the pass is narrowed to exactly those."
            )
        }
        if !model.kept.isEmpty {
            lines.append(
                "\(counted(model.kept.count, "copy")) kept out of this pass as --except: left completely alone."
            )
        }
        return WisentDecisionDialog(
            tone: .danger,
            title: "Remove \(counted(model.removableCount, "repository copy"))",
            lines: lines,
            listing: model.removableCopies.map(\.path).sorted(),
            actions: [
                WisentAction("Cancel", kind: .plain) { isDecidingRemoval = false },
                WisentAction("Remove", kind: .destructive) {
                    isDecidingRemoval = false
                    Task { await model.applyRemoval() }
                },
            ]
        )
    }
}
