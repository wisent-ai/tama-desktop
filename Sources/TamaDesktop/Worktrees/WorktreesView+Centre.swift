import SwiftUI
import WisentDesignSystem

extension WorktreesView {
    // MARK: - Centre

    @ViewBuilder
    func centre(visible: [WorktreeRecord]) -> some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
            removalBar
            roots
            if case let .failed(message) = model.scanState {
                WisentAlertPanel(tone: .danger, title: "Scan refused", detail: message)
            }
            if case let .failed(message) = model.removalState {
                WisentAlertPanel(tone: .danger, title: "Removal refused", detail: message)
            }
            refusals
            if model.worktreeCount > .zero { counters }
            content(visible: visible)
        }
        .padding(WisentDesign.Space.x5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var removalBar: some View {
        switch model.removalState {
        case .previewing:
            WisentMutationBar(outcome: .working("Reading what removal would do."), clear: {})
        case .applying:
            WisentMutationBar(outcome: .working("Removing worktrees."), clear: {})
        case let .applied(summary):
            WisentMutationBar(outcome: .succeeded(summary), clear: {})
        case .idle, .previewed, .failed:
            EmptyView()
        }
    }

    /// The roots are the screen's scope, and there is deliberately no default
    /// one: the refusal is stated here rather than only after a request that
    /// would never have been sent.
    private var roots: some View {
        WisentSectionBox(
            title: "Roots",
            detail: "Each root is walked for repositories; git names their worktrees.",
            trailing: model.roots.isEmpty ? nil : counted(model.roots.count, "root")
        ) {
            if model.roots.isEmpty {
                Text(WorktreesError.rootRequiredSentence)
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(model.roots, id: \.self) { root in
                    HStack(spacing: WisentDesign.Space.x3) {
                        Text(root)
                            .font(WisentTypeScale.identifierSmall())
                            .foregroundStyle(WisentDesign.ink)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        WisentActionButton(
                            action: WisentAction("Drop", kind: .plain) {
                                model.remove(root: root)
                            }
                        )
                    }
                }
            }
            Toggle(isOn: forceBinding) {
                Text("Discard uncommitted changes and unlock (--force)")
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.secondary)
            }
            .toggleStyle(.switch)
            .accessibilityIdentifier("tama.worktrees.force")
        }
    }

    /// Turning discarding on or off changes what applying would do, so the
    /// model drops the preview it invalidates; the binding routes through the
    /// model instead of keeping a second copy of the flag in the view.
    private var forceBinding: Binding<Bool> {
        Binding(
            get: { model.discardsUncommittedChanges },
            set: { model.setDiscardsUncommittedChanges($0) }
        )
    }

    /// One panel per refused worktree, carrying the command's own sentence: it
    /// names the path and the remedy, so there is nothing to paraphrase.
    @ViewBuilder
    private var refusals: some View {
        ForEach(model.refusals) { refusal in
            WisentAlertPanel(
                tone: .warning,
                title: "Not removed: \(URL(fileURLWithPath: refusal.path).lastPathComponent)",
                detail: refusal.sentence
            )
        }
    }

    private var counters: some View {
        WisentCounterRow(counters: [
            WisentCounterRow.Counter(
                "Worktrees",
                value: model.worktreeCount.formatted(.number),
                detail: "Linked checkouts in \(counted(model.repositories.count, "repository"))",
                tone: model.worktreeCount == .zero ? .success : .warning
            ),
            WisentCounterRow.Counter(
                "Uncommitted",
                value: model.worktrees.filter(\.dirty).count.formatted(.number),
                detail: "Removal refuses these without discarding",
                tone: model.worktrees.contains(where: \.dirty) ? .warning : .neutral
            ),
            WisentCounterRow.Counter(
                "Locked",
                value: model.worktrees.filter(\.locked).count.formatted(.number),
                detail: "Git refuses to remove a locked worktree",
                tone: model.worktrees.contains(where: \.locked) ? .warning : .neutral
            ),
            WisentCounterRow.Counter(
                "Removed",
                value: model.removed.count.formatted(.number),
                detail: "Deleted by the last applied pass"
            ),
        ])
    }

    @ViewBuilder
    private func content(visible: [WorktreeRecord]) -> some View {
        if model.roots.isEmpty {
            WisentEmptyPanel(
                title: "No root selected",
                detail: "Choose a directory to scan for linked worktrees.",
                symbol: "folder.badge.questionmark",
                action: WisentAction("Add root…", kind: .primary) { chooseRoot() }
            )
            Spacer(minLength: .zero)
        } else if model.scanState == .scanning {
            WisentProgressPanel(
                title: "Scanning \(counted(model.roots.count, "root"))",
                detail: "Asking git for the worktrees of every repository found."
            )
            Spacer(minLength: .zero)
        } else if model.listing == nil, model.preview == nil {
            WisentEmptyPanel(
                title: "These roots have not been scanned",
                detail: "Scan to list every linked worktree git reports.",
                symbol: "magnifyingglass",
                action: WisentAction("Scan", kind: .primary, isEnabled: model.canScan) {
                    Task { await model.list() }
                }
            )
            Spacer(minLength: .zero)
        } else if model.worktrees.isEmpty {
            WisentEmptyPanel(
                title: "No linked worktree under these roots",
                detail: "Every repository found has only its main worktree.",
                symbol: "checkmark.seal"
            )
            Spacer(minLength: .zero)
        } else if visible.isEmpty {
            WisentEmptyPanel(
                title: "No worktree in this repository",
                detail: "\(counted(model.worktreeCount, "worktree")) available. Clear the filter to see all of them.",
                symbol: "line.3.horizontal.decrease.circle",
                action: WisentAction("Show every repository", kind: .secondary) {
                    repositoryFacet = nil
                }
            )
            Spacer(minLength: .zero)
        } else {
            table(visible: visible)
        }
    }
}
