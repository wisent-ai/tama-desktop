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
                        .foregroundStyle(WisentDesign.ink)
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
            }
            .tableStyle(.inset)
            .textSelection(.disabled)
        }
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
                badges: record.marks.isEmpty
                    ? [("Clean", .success)]
                    : record.marks.map { ($0, .warning) }
            ) {
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
        return WisentDecisionDialog(
            tone: .danger,
            title: "Remove \(counted(model.worktreeCount, "linked worktree"))",
            lines: lines,
            listing: model.worktrees.map(\.path).sorted(),
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
