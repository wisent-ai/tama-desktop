import SwiftUI
import WisentDesignSystem

extension PostureView {
    // MARK: - Healthy signals

    func signals(_ snapshot: CatalogSnapshot) -> [WisentSignal] {
        var signals = [
            WisentSignal(
                "Policy",
                value: snapshot.validation.ok ? "Valid" : "Invalid",
                tone: snapshot.validation.ok ? .success : .danger
            )
        ]
        if !snapshot.catalog.orphanSources.isEmpty {
            signals.append(
                WisentSignal(
                    "Rules without a policy",
                    value: snapshot.catalog.orphanSources.count.formatted(.number),
                    tone: .warning
                )
            )
        }
        guard model.allowsControl else {
            signals.append(
                WisentSignal("Local enforcement", value: "Not inspected", tone: .neutral)
            )
            signals.append(
                WisentSignal(
                    "Bundled release",
                    value: buildIdentity.hookRelease.map { shortIdentifier($0.releaseId) }
                        ?? "Not recorded",
                    tone: .neutral
                )
            )
            return signals
        }
        signals.append(
            WisentSignal(
                "Policy protection",
                value: model.areHooksDisabled ? "Off" : "On",
                tone: model.areHooksDisabled ? .danger : .success
            )
        )
        signals.append(
            WisentSignal(
                "Machine selection",
                value: machineSelection.selection?.modeLabel ?? "Not read",
                tone: machineSelectionTone
            )
        )
        signals.append(
            WisentSignal(
                "Installed policy",
                value: model.installedHookReleaseID.map(shortIdentifier) ?? "Not installed",
                tone: model.installedHookReleaseID == nil ? .neutral : .success
            )
        )
        // `Not registered` is the factory state of a fresh install, so it stays
        // neutral; only a registration that failed earns red.
        signals.append(
            WisentSignal(
                "System protection",
                value: model.systemPolicyServiceStatus,
                tone: TamaTone.systemPolicy(model.systemPolicyServiceStatus)
            )
        )
        signals.append(
            WisentSignal(
                "Live sessions",
                value: model.agentSessions.isEmpty
                    ? "None"
                    : counted(model.agentSessions.count, "session"),
                tone: model.agentSessions.isEmpty ? .neutral : .success
            )
        )
        if let runtime = model.selectedAgentSession?.runtime {
            signals.append(
                WisentSignal(
                    "Session policy",
                    value: TamaTone.runtimeLabel(runtime),
                    tone: TamaTone.runtime(runtime)
                )
            )
        }
        return signals
    }
    private var machineSelectionTone: WisentTone {
        guard let selection = machineSelection.selection else { return .neutral }
        if model.areHooksDisabled || selection.emergencyDisabled { return .danger }
        return selection.mode == "only" ? .warning : .success
    }


    func counters(_ snapshot: CatalogSnapshot) -> some View {
        let hooks = snapshot.catalog.hooks
        let blocking = hooks.lazy.filter(\.isBlocking).count
        return WisentCounterRow(counters: [
            WisentCounterRow.Counter(
                "Policies",
                value: hooks.count.formatted(.number),
                detail: "Available in this release"
            ),
            WisentCounterRow.Counter(
                "Blocking",
                value: blocking.formatted(.number),
                detail: "Can stop unsafe work",
                tone: .warning
            ),
            WisentCounterRow.Counter(
                "Categories",
                value: Set(hooks.map(\.category)).count.formatted(.number),
                detail: "Policy groups"
            ),
            WisentCounterRow.Counter(
                "Warnings",
                value: snapshot.validation.warnings.count.formatted(.number),
                detail: "Policy checks",
                tone: snapshot.validation.warnings.isEmpty ? .neutral : .warning
            )
        ])
    }

    // MARK: - Identity

    /// Installed, loaded and bundled release identities, and the checksum, in
    /// one place. The baseline showed the installed release on Overview and the
    /// loaded one inside a hook's detail pane, so a drifted session could not be
    /// spotted without holding two screens in mind.
    func releaseIdentity(_ snapshot: CatalogSnapshot) -> some View {
        let runtime = model.selectedAgentSession?.runtime
        return WisentSectionBox(
            title: "Versions",
            trailing: buildIdentity.channel
        ) {
            WisentPanel {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                    HStack(alignment: .top, spacing: WisentDesign.Space.x4) {
                        WisentField(label: "Product version", value: buildIdentity.productVersion)
                        WisentField(label: "Source revision", value: buildIdentity.displayedRevision)
                        WisentField(
                            label: "Target",
                            value: "\(buildIdentity.platform) · \(buildIdentity.architecture)"
                        )
                    }
                    Divider()
                    HStack(alignment: .top, spacing: WisentDesign.Space.x4) {
                        WisentField(
                            label: "Bundled policy",
                            value: buildIdentity.hookRelease?.releaseId ?? "Not recorded"
                        )
                        // Read-only inspection monitors nothing local, so the
                        // absent value is "not inspected" and never the claim
                        // that nothing is installed.
                        WisentField(
                            label: "Installed release",
                            value: model.allowsControl
                                ? (model.installedHookReleaseID ?? "Not installed by Tama")
                                : "Not inspected",
                            tone: driftTone
                        )
                        WisentField(
                            label: "Session policy",
                            value: model.allowsControl
                                ? (runtime?.loadedReleaseId ?? "No live session")
                                : "Not inspected",
                            tone: driftTone
                        )
                    }
                    Divider()
                    HStack(alignment: .top, spacing: WisentDesign.Space.x4) {
                        WisentField(label: "Built", value: buildIdentity.builtAt)
                    }
                }
            }
        }
    }

    /// Installed and loaded identities that disagree are the drift this screen
    /// exists to expose; matching ones are simply facts and stay ink-coloured.
    private var driftTone: WisentTone {
        guard
            let installed = model.installedHookReleaseID,
            let loaded = model.selectedAgentSession?.runtime?.loadedReleaseId
        else {
            return .neutral
        }
        return installed == loaded ? .neutral : .warning
    }

    func validationNotes(_ validation: ValidationResult) -> some View {
        WisentSectionBox(
            title: "Warnings",
            trailing: counted(validation.warnings.count, "warning")
        ) {
            WisentPanel(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(validation.warnings.enumerated()), id: \.offset) { index, warning in
                        if index > 0 { Divider() }
                        Text(warning)
                            .font(WisentTypeScale.body())
                            .foregroundStyle(WisentDesign.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, WisentDesign.Space.x4)
                            .padding(.vertical, WisentDesign.Space.x3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if validation.warnings.isEmpty {
                        Text("No warnings.")
                            .font(WisentTypeScale.body())
                            .foregroundStyle(WisentDesign.secondary)
                            .padding(WisentDesign.Space.x4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    // MARK: - The decision

    /// Disabling every hook is reversible only by reinstalling and reloading the
    /// approved release, and everything the policy would have stopped in the
    /// meantime is already done. That earns a dialog, not a toolbar button.
    var bypassDecision: some View {
        WisentDecisionDialog(
            tone: .danger,
            title: "Disable all policies on this machine",
            lines: [
                "Unsafe actions will no longer be blocked.",
                "Current sessions will keep running.",
                "Re-enable the policies to restore protection.",
            ],
            listing: model.hooks.filter(\.isBlocking).map(\.id),
            actions: bypassActions
        )
    }

    /// The safe verb keeps the primary button and the rightmost position; the
    /// bypass gets a red one of its own.
    private var bypassActions: [WisentAction] {
        var actions: [WisentAction] = []
        if model.lastBlockingDecision != nil {
            actions.append(
                WisentAction("Read the blocking decision", kind: .plain) {
                    isDecidingBypass = false
                    onNavigate(.session)
                }
            )
        }
        actions.append(
            WisentAction("Disable all policies", kind: .destructive) {
                isDecidingBypass = false
                model.setHooksDisabled(true)
            }
        )
        actions.append(
            WisentAction("Keep policy active", kind: .primary) {
                isDecidingBypass = false
            }
        )
        return actions
    }
}
