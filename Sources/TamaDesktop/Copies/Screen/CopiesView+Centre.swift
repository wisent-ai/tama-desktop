import SwiftUI
import WisentDesignSystem

extension CopiesView {
    // MARK: - Centre

    @ViewBuilder
    var centre: some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
            removalBar
            roots
            if case let .failed(message) = model.scanState {
                WisentAlertPanel(tone: .danger, title: "Scan refused", detail: message)
            }
            if case let .failed(message) = model.removalState {
                WisentAlertPanel(tone: .danger, title: "Removal refused", detail: message)
            }
            marked
            refusals
            crossed
            if model.copyCount > .zero { counters }
            content
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
            WisentMutationBar(outcome: .working("Removing copies."), clear: {})
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
            detail: "Each root is walked for checkouts; a checkout below another one is a copy.",
            trailing: model.roots.isEmpty ? nil : counted(model.roots.count, "root")
        ) {
            if model.roots.isEmpty {
                Text(CopiesError.rootRequiredSentence)
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
            Toggle(isOn: overrideBinding) {
                Text("Remove past every refusal (--force)")
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.secondary)
            }
            .toggleStyle(.switch)
            .accessibilityIdentifier("tama.copies.force")
        }
    }

    /// Turning the override on or off changes what applying would do, so the
    /// model drops the preview it invalidates; the binding routes through the
    /// model instead of keeping a second copy of the flag in the view.
    private var overrideBinding: Binding<Bool> {
        Binding(
            get: { model.overridesRefusals },
            set: { model.setOverridesRefusals($0) }
        )
    }

    /// What the operator marked, stated as lists and not as alerts: nothing
    /// here needs settling, which is the whole difference between a mark and a
    /// refusal. Kept travels as `--except`, claimed as `--only`, and the two
    /// never travel together.
    @ViewBuilder
    private var marked: some View {
        let kept = model.kept.sorted()
        let claimed = model.claimed.sorted()
        if !claimed.isEmpty {
            WisentSectionBox(
                title: "Claimed",
                detail: "Sent as --only: the pass is narrowed to these, and every refusal that protects history still applies.",
                trailing: counted(claimed.count, "copy")
            ) {
                ForEach(claimed, id: \.self) { path in
                    markedRow(path, chip: "Claimed", tone: .warning, verb: "Release") {
                        model.setClaimed(path, false)
                    }
                }
            }
        }
        if !kept.isEmpty {
            WisentSectionBox(
                title: "Kept",
                detail: "Sent as --except: left alone, neither removed nor refused.",
                trailing: counted(kept.count, "copy")
            ) {
                ForEach(kept, id: \.self) { path in
                    markedRow(path, chip: "Kept", tone: .info, verb: "Include") {
                        model.setKept(path, false)
                    }
                }
            }
        }
    }

    private func markedRow(
        _ path: String,
        chip: String,
        tone: WisentTone,
        verb: String,
        undo: @escaping () -> Void
    ) -> some View {
        HStack(spacing: WisentDesign.Space.x3) {
            Text(path)
                .font(WisentTypeScale.identifierSmall())
                .foregroundStyle(WisentDesign.ink)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
            WisentStatusChip(text: chip, tone: tone)
            WisentActionButton(action: WisentAction(verb, kind: .plain) { undo() })
        }
    }

    /// One panel per refused copy, carrying the command's own sentence: it
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

    /// What the walk crossed and this pass does not remove: linked worktrees,
    /// which `tama worktrees` owns, twin checkouts, where the choice is the
    /// operator's, and candidates git would not answer for.
    @ViewBuilder
    private var crossed: some View {
        ForEach(model.twins) { twin in
            WisentAlertPanel(tone: .info, title: "Twin checkout", detail: twin.sentence)
        }
        if !model.linkedWorktrees.isEmpty {
            WisentAlertPanel(
                tone: .info,
                title: counted(model.linkedWorktrees.count, "linked worktree") + " crossed",
                detail: "Git tracks those, so the Worktrees screen lists and removes them."
            )
        }
        ForEach(model.unreadable, id: \.self) { path in
            WisentAlertPanel(
                tone: .warning,
                title: "Skipped: \(URL(fileURLWithPath: path).lastPathComponent)",
                detail: "\(path): git does not answer for it as a repository, so this pass reports it instead of reading it."
            )
        }
    }

    private var counters: some View {
        let removable = model.removableCopies
        return WisentCounterRow(counters: [
            WisentCounterRow.Counter(
                "Removable",
                value: model.removableCount.formatted(.number),
                detail: "Of \(counted(model.copyCount, "copy")) found, \(copiedSize(model.removableBytes))",
                tone: model.removableCount == .zero ? .success : .warning
            ),
            WisentCounterRow.Counter(
                "Claimed",
                value: model.claimed.count.formatted(.number),
                detail: "Marked --only; the pass is narrowed to them",
                tone: model.claimed.isEmpty ? .neutral : .warning
            ),
            WisentCounterRow.Counter(
                "Kept",
                value: model.kept.count.formatted(.number),
                detail: "Marked --except; this pass leaves them alone",
                tone: model.kept.isEmpty ? .neutral : .info
            ),
            WisentCounterRow.Counter(
                "Work only here",
                value: removable.filter(\.carriesWorkNowhereElse).count.formatted(.number),
                detail: "Uncommitted, unpushed, or no origin to compare against",
                tone: removable.contains(where: \.carriesWorkNowhereElse) ? .warning : .neutral
            ),
            WisentCounterRow.Counter(
                "Removed",
                value: model.removed.count.formatted(.number),
                detail: "Deleted by the last applied pass"
            ),
        ])
    }

    @ViewBuilder
    private var content: some View {
        if model.roots.isEmpty {
            WisentEmptyPanel(
                title: "No root selected",
                detail: "Choose a directory to scan for second full checkouts.",
                symbol: "folder.badge.questionmark",
                action: WisentAction("Add root…", kind: .primary) { chooseRoot() }
            )
            Spacer(minLength: .zero)
        } else if model.scanState == .scanning {
            WisentProgressPanel(
                title: "Scanning \(counted(model.roots.count, "root"))",
                detail: "Walking every checkout below the roots and asking git about each one."
            )
            Spacer(minLength: .zero)
        } else if model.listing == nil, model.preview == nil {
            WisentEmptyPanel(
                title: "These roots have not been scanned",
                detail: "Scan to list every second full checkout under them.",
                symbol: "magnifyingglass",
                action: WisentAction("Scan", kind: .primary, isEnabled: model.canScan) {
                    Task { await model.list() }
                }
            )
            Spacer(minLength: .zero)
        } else if model.copies.isEmpty {
            WisentEmptyPanel(
                title: "One checkout per repository under these roots",
                detail: "No checkout below another one was found.",
                symbol: "checkmark.seal"
            )
            Spacer(minLength: .zero)
        } else {
            table
        }
    }
}
