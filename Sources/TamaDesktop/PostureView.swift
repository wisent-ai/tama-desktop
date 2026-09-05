import SwiftUI
import WisentDesignSystem

/// Triage: what needs a human now, ordered by severity.
///
/// The order is fixed. A catalog that will not load, a bypassed policy and a
/// runtime that refused to load its registry each take a full-width alert
/// carrying the backend's own sentence and the command that reproduces it,
/// while every healthy check shares one strip of six lines. The baseline gave
/// both the same treatment — three metric tiles and a posture panel for health,
/// a modal alert that vanished for failure.
struct PostureView: View {
    @ObservedObject var model: AppModel
    let onNavigate: (SidebarDestination) -> Void

    @State private var isDecidingBypass = false

    private var buildIdentity: BuildIdentity { .current }

    var body: some View {
        WisentScreen(
            title: "Posture",
            scope: model.snapshot.map { counted($0.catalog.hooks.count, "policy") },
            freshness: freshness,
            actions: actions
        ) {
            WisentMutationBar(outcome: model.mutation) { model.clearMutation() }
            if let snapshot = model.snapshot {
                if let catalogError = model.catalogError {
                    WisentErrorBanner(
                        title: "Policy refresh failed",
                        detail: catalogError,
                        action: WisentAction("Retry", symbol: "arrow.clockwise", kind: .secondary) {
                            Task { await model.refresh() }
                        }
                    )
                }
                bypassAlert
                validationAlerts(snapshot.validation)
                sessionAlerts
                blockingDecisionAlert
                WisentSignalStrip(signals: signals(snapshot))
                counters(snapshot)
                releaseIdentity(snapshot)
                validationNotes(snapshot.validation)
            } else if let catalogError = model.catalogError {
                WisentAlertPanel(
                    tone: .danger,
                    title: "Policy unavailable",
                    detail: catalogError,
                                        actions: [
                        WisentAction("Retry", symbol: "arrow.clockwise", kind: .primary) {
                            Task { await model.refresh() }
                        }
                    ]
                )
            } else {
                WisentSkeletonGroup(
                    label: "Reading policy",
                    spacing: WisentDesign.Space.x4
                ) {
                    // The signal strip, the four counters, then the two
                    // section boxes the snapshot fills below them.
                    WisentSkeleton(.block, height: 56)
                    HStack(spacing: WisentDesign.Space.x3) {
                        ForEach(0 ..< 4, id: \.self) { _ in
                            WisentSkeleton(.block, height: 76)
                        }
                    }
                    WisentSkeleton(.heading, width: 140)
                    WisentSkeleton(.block, height: 120)
                    WisentSkeleton(.heading, width: 140)
                    WisentSkeleton(.block, height: 88)
                }
            }
        }
        .sheet(isPresented: $isDecidingBypass) { bypassDecision }
    }

    // MARK: - Context bar

    private var freshness: String {
        if model.isRefreshing { return "reading now" }
        guard let refreshedAt = model.refreshedAt else { return "not read yet" }
        return "read \(refreshedAt.formatted(date: .omitted, time: .standard))"
    }

    private var actions: [WisentAction] {
        guard model.allowsControl else {
            return [
                WisentAction("Reveal release", symbol: "folder", kind: .secondary) {
                    model.revealHookRelease()
                }
            ]
        }
        return [
            WisentAction("Reveal release", symbol: "folder", kind: .secondary) {
                model.revealHookRelease()
            },
            model.areHooksDisabled
                ? WisentAction(
                    "Re-enable all policies",
                    symbol: "power.circle.fill",
                    kind: .primary,
                    isEnabled: !model.isPolicyMutationInProgress
                ) {
                    model.setHooksDisabled(false)
                }
                : WisentAction(
                    "Disable all policies",
                    symbol: "exclamationmark.octagon.fill",
                    kind: .secondary,
                    isEnabled: !model.isPolicyMutationInProgress
                ) {
                    isDecidingBypass = true
                }
        ]
    }

    // MARK: - Failures

    @ViewBuilder private var bypassAlert: some View {
        if model.areHooksDisabled {
            WisentAlertPanel(
                tone: .danger,
                title: "Policy protection is off",
                detail: "Unsafe actions will not be blocked until protection is restored.",
                actions: [
                    WisentAction(
                        "Re-enable all policies",
                        kind: .primary,
                        isEnabled: !model.isPolicyMutationInProgress
                    ) {
                        model.setHooksDisabled(false)
                    }
                ]
            )
        }
    }

    @ViewBuilder private func validationAlerts(_ validation: ValidationResult) -> some View {
        ForEach(validation.errors, id: \.self) { error in
            WisentAlertPanel(
                tone: .danger,
                title: "Policy validation failed",
                detail: error,
                            )
        }
    }

    /// Session control that threw is an outage. A platform with no sessions at
    /// all is not, and is reported one line down in the strip instead.
    @ViewBuilder private var sessionAlerts: some View {
        if let sessionError = model.sessionError {
            WisentAlertPanel(
                tone: .danger,
                title: "Session control unavailable",
                detail: sessionError,
                                actions: [
                    WisentAction("Open Session", symbol: "person.badge.key", kind: .secondary) {
                        onNavigate(.session)
                    }
                ]
            )
        }
        ForEach(model.agentSessions) { session in
            if let error = session.systemPolicy?.error {
                WisentAlertPanel(
                    tone: .danger,
                    title: "System policy error in \(session.agentDisplayName) session",
                    detail: error,
                                    )
            }
            if let error = session.runtime?.registryLoadError {
                WisentAlertPanel(
                    tone: .danger,
                    title: "Session policy unavailable in \(session.agentDisplayName)",
                    detail: error,
                                    )
            }
        }
    }

    /// Why the agent stopped, in the words the hook used when it stopped it.
    ///
    /// The runtime publishes the decision, the hook that made it and the reason
    /// string; the baseline printed only the event name, so the one question
    /// this application exists to answer had no answer on any screen.
    @ViewBuilder private var blockingDecisionAlert: some View {
        if let decision = model.lastBlockingDecision {
            WisentAlertPanel(
                tone: .warning,
                title: blockingTitle(decision.event),
                detail: decision.event.reason
                    ?? "No reason was recorded.",
                                actions: [
                    WisentAction("Open Session", symbol: "person.badge.key", kind: .secondary) {
                        onNavigate(.session)
                    }
                ]
            )
        }
    }

    private func blockingTitle(_ event: SemanticEventSummary) -> String {
        let hook = event.blockedHookId ?? "A policy"
        return "\(hook) blocked \(event.event) at \(event.timestamp)"
    }

    // MARK: - Healthy signals

    private func signals(_ snapshot: CatalogSnapshot) -> [WisentSignal] {
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

    private func counters(_ snapshot: CatalogSnapshot) -> some View {
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
    private func releaseIdentity(_ snapshot: CatalogSnapshot) -> some View {
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

    private func validationNotes(_ validation: ValidationResult) -> some View {
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
    private var bypassDecision: some View {
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
