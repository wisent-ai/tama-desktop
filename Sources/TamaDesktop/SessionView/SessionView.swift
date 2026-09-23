import SwiftUI
import WisentDesignSystem

/// What one supervised agent session is actually allowed to do right now.
///
/// The capability document — lifetime, expiry, remaining uses and the tool
/// grants a session holds — was decoded from every session record and rendered
/// nowhere. An override the operator cannot see is an override they cannot
/// revoke, so it belongs on a screen of its own rather than inside a hook's
/// detail pane.
struct SessionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        WisentScreen(
            title: "Session",
            scope: model.agentSessions.isEmpty
                ? nil
                : counted(model.agentSessions.count, "live session"),
            freshness: model.selectedAgentSession.map { "updated \($0.updatedAt)" },
            actions: actions,
            scrolls: false,
            constrainsWidth: false
        ) {
            HStack(spacing: 0) {
                WisentFacetRail(groups: [sessionGroup])
                centre
                inspector
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    var actions: [WisentAction] {
        var actions = [
            WisentAction("Refresh sessions", symbol: "arrow.clockwise", kind: .secondary) {
                Task { await model.refreshAgentSessions() }
            }
        ]
        if let session = model.selectedAgentSession,
           !model.areAllHooksEnabled(in: session) {
            actions.append(
                WisentAction(
                    "Enable all policies",
                    symbol: "checkmark.shield.fill",
                    kind: .primary,
                    isEnabled: !model.isPolicyMutationInProgress && !model.hooks.isEmpty
                ) {
                    model.enableAllHooks(in: session)
                }
            )
        }
        return actions
    }

    var sessionGroup: WisentFacetGroup {
        WisentFacetGroup(
            "Live sessions",
            facets: model.agentSessions.map { session in
                WisentFacet(
                    id: session.id,
                    label: "\(session.agentDisplayName) · \(URL(fileURLWithPath: session.cwd).lastPathComponent)",
                    count: session.runtime?.loadedHookCount,
                    tone: session.runtime.map(TamaTone.runtime) ?? .neutral,
                    isSelected: model.selectedAgentSession?.id == session.id
                ) {
                    model.selectedAgentSessionID = session.id
                }
            }
        )
    }

    // MARK: - Centre

    @ViewBuilder
    var centre: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x5) {
                WisentMutationBar(outcome: model.mutation) { model.clearMutation() }
                if let sessionError = model.sessionError {
                    WisentAlertPanel(
                        tone: .danger,
                        title: "Session control unavailable",
                        detail: sessionError,
                                                actions: [
                            WisentAction("Retry", symbol: "arrow.clockwise", kind: .primary) {
                                Task { await model.refreshAgentSessions() }
                            }
                        ]
                    )
                }
                sessionHookSummary
                if let session = model.selectedAgentSession {
                    faults(session)
                    counters(session)
                    capability(session)
                    grants(session)
                    runtime(session)
                    decisions(session)
                } else if model.sessionError == nil {
                    WisentEmptyPanel(
                        title: "No session is running",
                        detail: model.systemPolicyServiceStatus == "Enabled"
                            ? "Open or resume a supported coding session."
                            : "Enable System protection in Settings before opening or resuming a session.",
                        symbol: "terminal"
                    )
                }
            }
            .padding(WisentDesign.Space.x5)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    func faults(_ session: AgentSessionRecord) -> some View {
        if let error = session.systemPolicy?.error {
            WisentAlertPanel(
                tone: .danger,
                title: "System policy error",
                detail: error,
                                actions: policyActions(session)
            )
        }
        if let error = session.runtime?.registryLoadError {
            WisentAlertPanel(
                tone: .danger,
                title: "Session policy unavailable",
                detail: error
            )
        }
        if let runtime = session.runtime, runtime.reloadRequired, runtime.reloadPending != true {
            WisentAlertPanel(
                tone: .warning,
                title: "Policy update available",
                detail: "This session uses \(runtime.loadedReleaseId) instead of \(runtime.installedReleaseId ?? "the installed release"). Enable all policies to update it.",
                actions: [
                    WisentAction(
                        "Enable all policies",
                        kind: .primary,
                        isEnabled: !model.isPolicyMutationInProgress
                    ) {
                        model.enableAllHooks(in: session)
                    }
                ]
            )
        }
        if !(session.runtime?.unknownHookIds.isEmpty ?? true) {
            WisentAlertPanel(
                tone: .warning,
                title: "This session includes unavailable policies",
                detail: (session.runtime?.unknownHookIds ?? []).joined(separator: ", ")
            )
        }
    }

    func policyActions(_ session: AgentSessionRecord) -> [WisentAction] {
        var actions: [WisentAction] = [
            WisentAction("Approval settings", kind: .secondary) {
                model.openSystemPolicyApprovalSettings()
            }
        ]
        if let raw = session.systemPolicy?.supportPullRequestURL, let url = URL(string: raw) {
            actions.append(
                WisentAction("Platform support", kind: .plain) {
                    NSWorkspace.shared.open(url)
                }
            )
        }
        return actions
    }

    func counters(_ session: AgentSessionRecord) -> some View {
        let runtime = session.runtime
        let overrides = session.globallyDisabled
            ? session.enabledHookIds.count
            : session.disabledHookIds.count
        return WisentCounterRow(counters: [
            WisentCounterRow.Counter(
                "Available",
                value: (runtime?.registeredHookCount ?? .zero).formatted(.number),
                detail: "Policies for this session"
            ),
            WisentCounterRow.Counter(
                "Enabled",
                value: (runtime?.loadedHookCount ?? .zero).formatted(.number),
                detail: "Policies active now",
                tone: runtime.map { $0.loadedHookCount == $0.registeredHookCount ? .neutral : .warning }
                    ?? .neutral
            ),
            WisentCounterRow.Counter(
                "Overrides",
                value: overrides.formatted(.number),
                detail: session.globallyDisabled ? "Selected for this session" : "Disabled for this session",
                tone: overrides == .zero ? .neutral : .warning
            ),
            WisentCounterRow.Counter(
                "Decisions",
                value: (session.semanticRuntime?.eventSequence ?? .zero).formatted(.number),
                detail: "Policy decisions recorded"
            )
        ])
    }

    /// The capability document, rendered for the first time.
    @ViewBuilder
    func capability(_ session: AgentSessionRecord) -> some View {
        WisentSectionBox(
            title: "Session access",
            detail: "Temporary access for this session.",
            trailing: session.capability.map(\.lifetime) ?? "none"
        ) {
            WisentPanel {
                if let capability = session.capability {
                    VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                        HStack(alignment: .top, spacing: WisentDesign.Space.x4) {
                            WisentField(label: "Lifetime", value: capability.lifetime)
                            WisentField(
                                label: "Expires at",
                                value: capability.expiresAt ?? "Not bounded by time",
                                tone: capability.expiresAt == nil ? .neutral : .warning
                            )
                            WisentField(
                                label: "Remaining uses",
                                value: capability.remainingUses.map { $0.formatted(.number) }
                                    ?? "Not bounded by count",
                                tone: (capability.remainingUses ?? Int.max) <= Int("1")!
                                    ? .warning
                                    : .neutral
                            )
                        }
                        Divider()
                        HStack(alignment: .top, spacing: WisentDesign.Space.x4) {
                            WisentField(label: "Issued by", value: capability.issuedBy)
                            WisentField(label: "Release", value: capability.releaseId)
                        }
                    }
                } else {
                    Text("No extra access has been issued.")
                        .font(WisentTypeScale.body())
                        .foregroundStyle(WisentDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }






    // MARK: - Inspector

    // MARK: - Per-session hook summary


}
