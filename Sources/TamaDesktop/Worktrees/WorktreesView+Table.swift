import SwiftUI
import WisentDesignSystem

extension WorktreesView {
    // MARK: - Table

    /// One row per linked worktree, with the owning repository beside it: git
    /// grouped them, and an operator deciding what to delete reads the pair.
    func table(visible: [WorktreeRecord]) -> some View {
        WisentTableFrame {
            Table(visible, selection: $selection) {
                TableColumn("WORKTREE") { record in
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
                TableColumn("REPOSITORY") { record in
                    Text(repository(of: record)?.name ?? "")
                        .font(WisentTypeScale.body())
                        .foregroundStyle(WisentDesign.secondary)
                        .lineLimit(1)
                }
                TableColumn("BRANCH") { record in
                    Text(record.branchLabel)
                        .font(WisentTypeScale.body())
                        .foregroundStyle(WisentDesign.secondary)
                        .lineLimit(1)
                }
                TableColumn("HEAD") { record in
                    Text(record.shortHead)
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
                    }
                }
            }
            .tableStyle(.inset)
            .textSelection(.disabled)
        }
    }

    // MARK: - Keeping a worktree out of the pass

    /// Kept is the operator's own exclusion, refused is the product's, so the
    /// two never share a tone or a word: a choice reads `.info`, a refusal
    /// `.warning`.
    func passLabel(_ record: WorktreeRecord) -> String {
        if model.isKept(record) { return "Kept" }
        return isRefused(record) ? "Refused" : "Removable"
    }

    func passTone(_ record: WorktreeRecord) -> WisentTone {
        if model.isKept(record) { return .info }
        return isRefused(record) ? .warning : .neutral
    }

    func isRefused(_ record: WorktreeRecord) -> Bool {
        model.refusals.contains { $0.path == record.path }
    }

    /// One verb per row, named for what it does to this pass rather than for
    /// the flag it becomes.
    func keepAction(_ record: WorktreeRecord) -> WisentAction {
        WisentAction(model.isKept(record) ? "Include" : "Keep", kind: .plain) {
            model.toggleKept(record)
        }
    }

    /// The kept badge comes first: it is the reason the git marks beside it do
    /// not decide anything for this pass.
    private func badges(for record: WorktreeRecord) -> [(String, WisentTone)] {
        let marks: [(String, WisentTone)] = record.marks.isEmpty
            ? [("Clean", .success)]
            : record.marks.map { ($0, .warning) }
        return model.isKept(record) ? [("Kept", .info)] + marks : marks
    }

    // MARK: - Inspector

    private var selectedWorktree: WorktreeRecord? {
        guard let selection else { return nil }
        return model.worktrees.first { $0.id == selection }
    }

    @ViewBuilder
    var inspector: some View {
        if let record = selectedWorktree {
            WisentInspector(
                eyebrow: record.branchLabel,
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
                WisentField(label: "Head", value: record.head)
                WisentField(
                    label: "Owning repository",
                    value: repository(of: record)?.repository ?? ""
                )
                WisentField(
                    label: "Git state",
                    value: record.marks.isEmpty
                        ? "Nothing uncommitted, not locked"
                        : record.marks.joined(separator: ", "),
                    tone: record.marks.isEmpty ? .success : .warning
                )
                WisentActionButton(action: keepAction(record))
            }
        } else {
            WisentInspector(
                eyebrow: "Worktree",
                title: model.worktreeCount == .zero
                    ? "Nothing scanned yet"
                    : "No worktree selected"
            ) {
                Text("Select a worktree to see the repository that owns it and what removal would do.")
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - The decision

    /// Removing a linked worktree deletes a checkout from disk. What the
    /// preview reported is what this dialog lists, and discarding is named
    /// again here because it is the one setting that destroys work.
    var removalDecision: some View {
        var lines = [
            "Every worktree listed below is deleted from disk.",
            "The main worktree of each repository is never touched.",
            "Tama then runs git worktree prune in the owning repository.",
        ]
        if model.discardsUncommittedChanges {
            let discarded = model.worktreesNeedingForce.count
            lines.append(
                discarded == .zero
                    ? "Discarding is on; no listed worktree carries uncommitted changes or a lock."
                    : "Discarding is on: \(counted(discarded, "worktree")) loses uncommitted changes or a lock."
            )
        }
        if !model.kept.isEmpty {
            lines.append(
                "\(counted(model.kept.count, "worktree")) kept out of this pass as --except: left completely alone."
            )
        }
        return WisentDecisionDialog(
            tone: .danger,
            title: "Remove \(counted(model.removableCount, "linked worktree"))",
            lines: lines,
            listing: model.removableWorktrees.map(\.path).sorted(),
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
