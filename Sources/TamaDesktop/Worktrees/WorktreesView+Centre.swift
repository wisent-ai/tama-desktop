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
            keptOut
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

    /// The worktrees the operator marked to keep, stated as a list and not as
    /// an alert: nothing here needs settling, which is the whole difference
    /// between kept and refused. Paths are read from the model, so a document
    /// that reported `excepted` back shows the same rows as a fresh mark.
    @ViewBuilder
    private var keptOut: some View {
        let paths = model.kept.sorted()
        if !paths.isEmpty {
            WisentSectionBox(
                title: "Kept",
                detail: "Sent as --except: left alone, neither removed nor refused.",
                trailing: counted(paths.count, "worktree")
            ) {
                ForEach(paths, id: \.self) { path in
                    HStack(spacing: WisentDesign.Space.x3) {
                        Text(path)
                            .font(WisentTypeScale.identifierSmall())
                            .foregroundStyle(WisentDesign.ink)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        WisentStatusChip(text: "Kept", tone: .info)
                        WisentActionButton(
                            action: WisentAction("Include", kind: .plain) {
                                model.setKept(path, false)
                            }
                        )
                    }
                }
            }
        }
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
        // A kept worktree is refused nothing, so the two refusal counters read
        // the removable rows and not every row git reported.
        let removable = model.removableWorktrees
        return WisentCounterRow(counters: [
            WisentCounterRow.Counter(
                "Removable",
                value: model.removableCount.formatted(.number),
                detail: "Of \(counted(model.worktreeCount, "linked checkout")) in \(counted(model.repositories.count, "repository"))",
                tone: model.removableCount == .zero ? .success : .warning
            ),
            WisentCounterRow.Counter(
                "Kept",
                value: model.kept.count.formatted(.number),
                detail: "Marked --except; this pass leaves them alone",
                tone: model.kept.isEmpty ? .neutral : .info
            ),
            WisentCounterRow.Counter(
                "Uncommitted",
                value: removable.filter(\.dirty).count.formatted(.number),
                detail: "Removal refuses these without discarding",
                tone: removable.contains(where: \.dirty) ? .warning : .neutral
            ),
            WisentCounterRow.Counter(
                "Locked",
                value: removable.filter(\.locked).count.formatted(.number),
                detail: "Git refuses to remove a locked worktree",
                tone: removable.contains(where: \.locked) ? .warning : .neutral
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
