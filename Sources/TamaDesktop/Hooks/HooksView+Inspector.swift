import SwiftUI
import WisentDesignSystem

extension HooksView {
    // MARK: - Inspector

    var selectedHook: HookRecord? {
        guard let selection else { return nil }
        return model.hooks.first { $0.id == selection }
    }

    @ViewBuilder
    var inspector: some View {
        if let hook = selectedHook {
            WisentInspector(
                eyebrow: hook.category,
                title: hook.id,
                badges: badges(hook)
            ) {
                if let description = hook.description {
                    prose("What it does", description)
                }
                if let why = hook.why {
                    prose("Why it exists", why)
                }
                if let sideEffects = hook.sideEffects {
                    prose("Side effects", sideEffects)
                }
                events(hook)
                WisentField(label: "Source", value: hook.sourcePath ?? "No archived source path")
                WisentField(label: "Command", value: hook.command)
                machineControl(hook)
                sessionControl(hook)
            }
        } else {
            WisentInspector(eyebrow: "Policy", title: "No policy selected") {
                Text("Select a policy to view its details and session status.")
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func badges(_ hook: HookRecord) -> [(String, WisentTone)] {
        var badges: [(String, WisentTone)] = [
            (hook.status.capitalized, hook.status == "active" ? .success : .warning)
        ]
        if hook.isBlocking {
            badges.append(("Blocking", .warning))
        }
        return badges
    }

    private func prose(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
            Text(label.uppercased())
                .font(WisentTypeScale.eyebrow())
                .tracking(0.6)
                .foregroundStyle(WisentDesign.muted)
            Text(text)
                .font(WisentTypeScale.caption())
                .foregroundStyle(WisentDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func events(_ hook: HookRecord) -> some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
            Text("EVENTS")
                .font(WisentTypeScale.eyebrow())
                .tracking(0.6)
                .foregroundStyle(WisentDesign.muted)
            ForEach(hook.events) { event in
                HStack(spacing: WisentDesign.Space.x2) {
                    Text(event.event)
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(WisentDesign.ink)
                        .lineLimit(1)
                    Spacer(minLength: WisentDesign.Space.x2)
                    if event.blocking {
                        WisentStatusChip(text: "Blocking", tone: .warning)
                    }
                    Text("\(event.timeout)s")
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(WisentDesign.muted)
                        .monospacedDigit()
                }
                .frame(height: WisentAppLayout.tableRowHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    var machineSelectionPanel: some View {
        WisentPanel {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                HStack(spacing: WisentDesign.Space.x3) {
                    Text("MACHINE SELECTION")
                        .font(WisentTypeScale.eyebrow())
                        .tracking(0.6)
                        .foregroundStyle(WisentDesign.muted)
                    if let selection = machineSelection.selection {
                        WisentStatusChip(
                            text: selection.modeLabel,
                            tone: selection.mode == "only" ? .warning : .success
                        )
                    } else {
                        WisentStatusChip(text: "Not read", tone: .neutral)
                    }
                    Spacer(minLength: WisentDesign.Space.x2)
                    if machineSelection.selection?.mode == "only", model.allowsControl {
                        WisentActionButton(
                            action: WisentAction(
                                "Select all hooks",
                                symbol: "checkmark.shield",
                                kind: .secondary,
                                isEnabled: !machineSelection.isWorking
                            ) {
                                machineSelection.setAll()
                            }
                        )
                    }
                }
                Text("This selection is machine-wide and operator-owned. A session can only add a hook for itself; it cannot remove one from this selection.")
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let error = machineSelection.readError {
                    Text(error)
                        .font(WisentTypeScale.caption())
                        .foregroundStyle(WisentDesign.danger)
                }
                WisentMutationBar(outcome: machineSelection.outcome) {
                    machineSelection.clearOutcome()
                }
            }
        }
    }

    func machineStatus(_ hook: HookRecord) -> (String, WisentTone) {
        guard let selection = machineSelection.selection else {
            return ("Not read", .neutral)
        }
        if model.areHooksDisabled || selection.emergencyDisabled {
            return ("Bypassed", .danger)
        }
        return selection.includes(hook.id)
            ? ("Enforcing", .success)
            : ("Not selected", .warning)
    }

    @ViewBuilder
    private func machineControl(_ hook: HookRecord) -> some View {
        Divider()
        let selected = machineSelection.selection?.includes(hook.id) ?? true
        let isLastSelection = machineSelection.selection?.mode == "only"
            && machineSelection.selection?.enabled.count == Int("1")!
            && selected
        let status = machineStatus(hook)
        WisentField(label: "On this machine", value: status.0, tone: status.1)
        if model.allowsControl, machineSelection.selection != nil {
            WisentActionButton(
                action: WisentAction(
                    selected ? "Remove from machine selection" : "Add to machine selection",
                    symbol: selected ? "minus.shield" : "checkmark.shield",
                    kind: selected ? .secondary : .primary,
                    isEnabled: !machineSelection.isWorking && !isLastSelection
                ) {
                    machineSelection.setEnforced(
                        !selected,
                        hookID: hook.id,
                        catalogIDs: model.hooks.map(\.id)
                    )
                }
            )
            if isLastSelection {
                Text("At least one hook must remain selected. Choose Select all hooks, or add another hook first.")
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }


    /// The one decision this screen owns: is this policy live in the session in
    /// front of the operator. Enabling restores policy, so it needs no dialog;
    /// the disabling direction does not exist per hook by design.
    @ViewBuilder
    private func sessionControl(_ hook: HookRecord) -> some View {
        if let session {
            Divider()
            let isEnabled = session.isHookEnabled(hook.id)
            WisentField(
                label: "In \(session.agentDisplayName) session",
                value: isEnabled ? "Enabled" : "Not enabled",
                tone: isEnabled ? .success : .warning
            )
            if !isEnabled {
                WisentActionButton(
                    action: WisentAction(
                        "Enable in this session",
                        symbol: "checkmark.shield",
                        kind: .primary,
                        isEnabled: !model.isPolicyMutationInProgress
                    ) {
                        model.enableHook(hook.id, in: session)
                    }
                )
            }
        }
    }
}
