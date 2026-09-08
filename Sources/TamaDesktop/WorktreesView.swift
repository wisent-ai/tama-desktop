import AppKit
import SwiftUI
import WisentDesignSystem

/// Every linked worktree under the named roots, and the one verb that deletes
/// them.
///
/// Tama now blocks `git worktree add`, so the linked checkouts that exist are
/// the only ones there will be. Removing them is what reclaims disk: this
/// machine has 12.4 GiB free of 1.8 TB, and
/// `~/Documents/CodingProjects/Wisent/.worktrees/brama-stub-purge` is a linked
/// worktree of `Wisent/brama` inside a directory tree holding 519 GB. The
/// screen carries the same capability as `tama worktrees`, and the same
/// refusals.
struct WorktreesView: View {
    @ObservedObject var model: WorktreesModel

    @State var repositoryFacet: String?
    @State var selection: WorktreeRecord.ID?
    @State var isDecidingRemoval = false

    var body: some View {
        let visible = filtered

        return WisentScreen(
            title: "Worktrees",
            scope: model.roots.isEmpty ? nil : counted(model.roots.count, "root"),
            freshness: freshness,
            actions: actions,
            scrolls: false,
            constrainsWidth: false
        ) {
            HStack(spacing: .zero) {
                WisentFacetRail(
                    groups: facetGroups,
                    footerTitle: "Selection",
                    footerDetail: "\(visible.count.formatted(.number)) of \(model.worktreeCount.formatted(.number))"
                )
                centre(visible: visible)
                inspector
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .sheet(isPresented: $isDecidingRemoval) { removalDecision }
    }

    // MARK: - Context bar

    private var freshness: String {
        switch model.scanState {
        case .idle: model.roots.isEmpty ? "no root selected" : "not scanned"
        case .scanning: "scanning now"
        case .failed: "scan refused"
        case .done: counted(model.worktreeCount, "linked worktree")
        }
    }

    /// Four verbs in the order the decision is made: name a root, read what is
    /// there, read what removal would do, then remove.
    private var actions: [WisentAction] {
        [
            WisentAction("Add root…", symbol: "folder.badge.plus", kind: .secondary) {
                chooseRoot()
            },
            WisentAction(
                "Scan",
                symbol: "magnifyingglass",
                kind: .primary,
                isEnabled: model.canScan,
                isBusy: model.scanState == .scanning
            ) {
                Task { await model.list() }
            },
            WisentAction(
                "Preview removal",
                symbol: "eye",
                kind: .secondary,
                isEnabled: model.canPreview,
                isBusy: model.removalState == .previewing
            ) {
                Task { await model.previewRemoval() }
            },
            WisentAction(
                "Remove worktrees",
                symbol: "trash",
                kind: .destructive,
                isEnabled: model.canApply,
                isBusy: model.removalState == .applying
            ) {
                isDecidingRemoval = true
            },
        ]
    }

    /// A directory chooser, not a free-text field: the walk refuses a relative
    /// path and a directory that does not exist, and both are avoidable before
    /// the request leaves.
    func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Scan for worktrees"
        panel.message = "Choose a directory to scan for linked git worktrees."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { model.add(root: url.path) }
    }

    // MARK: - Facets

    private var facetGroups: [WisentFacetGroup] {
        guard !model.repositories.isEmpty else { return [] }
        return [
            WisentFacetGroup(
                "Repository",
                facets: [
                    WisentFacet(
                        id: "repository.all",
                        label: "Every repository",
                        count: model.worktrees.count,
                        isSelected: repositoryFacet == nil
                    ) {
                        repositoryFacet = nil
                    }
                ] + model.repositories.map { repository in
                    WisentFacet(
                        id: "repository.\(repository.repository)",
                        label: repository.name,
                        count: repository.worktrees.count,
                        tone: repository.dirtyCount + repository.lockedCount > .zero
                            ? .warning
                            : .neutral,
                        isSelected: repositoryFacet == repository.repository
                    ) {
                        repositoryFacet = repositoryFacet == repository.repository
                            ? nil
                            : repository.repository
                    }
                }
            )
        ]
    }

    var filtered: [WorktreeRecord] {
        guard let repositoryFacet else { return model.worktrees }
        return model.repositories
            .first { $0.repository == repositoryFacet }?
            .worktrees ?? []
    }

    /// Git is the authority on ownership, so the owning repository is read back
    /// out of the grouping the command returned and never guessed from a path.
    func repository(of record: WorktreeRecord) -> WorktreeRepository? {
        model.repositories.first { $0.worktrees.contains { $0.path == record.path } }
    }
}
