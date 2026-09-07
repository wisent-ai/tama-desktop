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
    @StateObject var machineSelection = EnforcementSelectionModel()

    @State var isDecidingBypass = false

    var buildIdentity: BuildIdentity { .current }

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
        .task { await machineSelection.refresh() }
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

}
