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
                WisentFacetRail(
                    groups: [sessionGroup],
                    footerTitle: "Control channel",
                    footerDetail: "Application Support/Tama/session-control"
                )
                centre
                inspector
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var actions: [WisentAction] {
        var actions = [
            WisentAction("Refresh sessions", symbol: "arrow.clockwise", kind: .secondary) {
                Task { await model.refreshAgentSessions() }
            }
        ]
        if let session = model.selectedAgentSession,
           !model.areAllHooksEnabled(in: session) {
            actions.append(
                WisentAction(
                    "Enable all hooks",
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

    private var sessionGroup: WisentFacetGroup {
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
    private var centre: some View {
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
                        title: "No supervised session is running",
                        detail: "Tama refuses to start an agent unless the platform has a ready kernel-enforcement backend. Open or resume a supported coding-agent session, and it appears here within a second.",
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
    private func faults(_ session: AgentSessionRecord) -> some View {
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
                title: "Hook registry failed to load",
                detail: error,
                            )
        }
        if let runtime = session.runtime, runtime.reloadRequired, runtime.reloadPending != true {
            WisentAlertPanel(
                tone: .warning,
                title: "The runtime is serving a stale registry",
                detail: "This session loaded release \(runtime.loadedReleaseId) and the installed release is \(runtime.installedReleaseId ?? "not recorded"). Enabling every hook reloads the registry in place.",
                                actions: [
                    WisentAction(
                        "Enable all hooks",
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
                title: "The runtime holds overrides for hooks this build does not declare",
                detail: (session.runtime?.unknownHookIds ?? []).joined(separator: ", "),
                            )
        }
    }

    private func policyActions(_ session: AgentSessionRecord) -> [WisentAction] {
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

    private func counters(_ session: AgentSessionRecord) -> some View {
        let runtime = session.runtime
        let overrides = session.globallyDisabled
            ? session.enabledHookIds.count
            : session.disabledHookIds.count
        return WisentCounterRow(counters: [
            WisentCounterRow.Counter(
                "Registered",
                value: (runtime?.registeredHookCount ?? .zero).formatted(.number),
                detail: "Hooks the runtime knows"
            ),
            WisentCounterRow.Counter(
                "Loaded",
                value: (runtime?.loadedHookCount ?? .zero).formatted(.number),
                detail: "Hooks the runtime can run",
                tone: runtime.map { $0.loadedHookCount == $0.registeredHookCount ? .neutral : .warning }
                    ?? .neutral
            ),
            WisentCounterRow.Counter(
                "Overrides",
                value: overrides.formatted(.number),
                detail: session.globallyDisabled ? "Allowlisted in this session" : "Suppressed in this session",
                tone: overrides == .zero ? .neutral : .warning
            ),
            WisentCounterRow.Counter(
                "Decisions",
                value: (session.semanticRuntime?.eventSequence ?? .zero).formatted(.number),
                detail: "Semantic events recorded"
            )
        ])
    }

    /// The capability document, rendered for the first time.
    @ViewBuilder
    private func capability(_ session: AgentSessionRecord) -> some View {
        WisentSectionBox(
            title: "Session capability",
            detail: "The signed authorisation this session holds for privileged tool use.",
            trailing: session.capability.map(\.lifetime) ?? "none issued"
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
                            WisentField(
                                label: "Schema version",
                                value: capability.schemaVersion.formatted(.number)
                            )
                            WisentField(label: "Nonce", value: capability.nonce)
                        }
                        Divider()
                        HStack(alignment: .top, spacing: WisentDesign.Space.x4) {
                            WisentField(label: "Release", value: capability.releaseId)
                            WisentField(label: "Catalog checksum", value: capability.catalogChecksum)
                        }
                    }
                } else {
                    Text("No capability has been issued to this session. Every privileged tool call is decided by the standing policy alone.")
                        .font(WisentTypeScale.body())
                        .foregroundStyle(WisentDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func grants(_ session: AgentSessionRecord) -> some View {
        let grants = session.capability?.grants ?? []
        WisentSectionBox(
            title: "Capability grants",
            detail: "Tools this session may call, and the actions each grant covers.",
            trailing: counted(grants.count, "grant")
        ) {
            if grants.isEmpty {
                WisentPanel {
                    Text(session.capability == nil
                        ? "No capability, so no grants."
                        : "The capability carries no tool grants; it authorises nothing by itself.")
                        .font(WisentTypeScale.body())
                        .foregroundStyle(WisentDesign.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                WisentTableFrame {
                    Table(grants) {
                        TableColumn("TOOL") { grant in
                            Text(grant.tool)
                                .font(WisentTypeScale.identifier())
                                .foregroundStyle(WisentDesign.ink)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(grant.tool)
                                .frame(height: WisentAppLayout.tableRowHeight, alignment: .leading)
                        }
                        .width(min: 130, ideal: 200)
                        TableColumn("ACTIONS") { grant in
                            Text(grant.actionList)
                                .font(WisentTypeScale.identifierSmall())
                                .foregroundStyle(WisentDesign.secondary)
                                .lineLimit(1)
                                .help(grant.actionList)
                        }
                        .width(min: 100, ideal: 200)
                    }
                    .tableStyle(.inset)
                    .frame(height: tableHeight(rows: grants.count))
                    // Click and drag inside a table belong to the table's own
                    // row handling, not to the text drawn in the cell. Opting
                    // out restores exactly the behaviour this grid had before
                    // the window turned selection on.
                    .textSelection(.disabled)
                }
            }
        }
    }

    private func runtime(_ session: AgentSessionRecord) -> some View {
        WisentSectionBox(
            title: "Runtime",
            detail: "What this session loaded, and how Tama knows it is still alive.",
            trailing: session.runtime.map(TamaTone.runtimeLabel) ?? "not reported"
        ) {
            WisentPanel {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                    HStack(alignment: .top, spacing: WisentDesign.Space.x4) {
                        WisentField(
                            label: "Loaded release",
                            value: session.runtime?.loadedReleaseId ?? "Not reported"
                        )
                        WisentField(
                            label: "Installed release",
                            value: session.runtime?.installedReleaseId ?? "Not reported"
                        )
                    }
                    Divider()
                    HStack(alignment: .top, spacing: WisentDesign.Space.x4) {
                        WisentField(
                            label: "Catalog checksum",
                            value: session.runtime?.catalogChecksum ?? "Not reported"
                        )
                        WisentField(
                            label: "Liveness",
                            value: session.livenessMode == "heartbeat"
                                ? "heartbeat, \(session.heartbeatTTLSeconds)s TTL"
                                : "process \(session.pid)"
                        )
                    }
                    if session.globallyDisabled {
                        Divider()
                        Text("Hooks are globally disabled on this machine. This session runs only the policies in its allowlist.")
                            .font(WisentTypeScale.caption())
                            .foregroundStyle(WisentDesign.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The register of what the policy actually decided, newest first.
    @ViewBuilder
    private func decisions(_ session: AgentSessionRecord) -> some View {
        let events = (session.semanticRuntime?.recentEvents ?? []).reversed().map { $0 }
        WisentSectionBox(
            title: "Recent decisions",
            detail: "Every semantic event the runtime published for this session.",
            trailing: counted(events.filter(\.isBlocking).count, "block")
        ) {
            if events.isEmpty {
                WisentPanel {
                    Text("This session has published no semantic events yet.")
                        .font(WisentTypeScale.body())
                        .foregroundStyle(WisentDesign.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                WisentTableFrame {
                    Table(events) {
                        TableColumn("WHEN") { event in
                            Text(event.timestamp)
                                .font(WisentTypeScale.identifierSmall())
                                .foregroundStyle(WisentDesign.secondary)
                                .lineLimit(1)
                                .frame(height: WisentAppLayout.tableRowHeight, alignment: .leading)
                        }
                        .width(min: 100, ideal: 150)
                        TableColumn("EVENT") { event in
                            Text(event.event)
                                .font(WisentTypeScale.identifierSmall())
                                .foregroundStyle(WisentDesign.ink)
                                .lineLimit(1)
                        }
                        .width(min: 90, ideal: 130)
                        TableColumn("HOOK") { event in
                            Text(event.blockedHookId ?? "—")
                                .font(WisentTypeScale.identifierSmall())
                                .foregroundStyle(WisentDesign.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .width(min: 80, ideal: 140)
                        TableColumn("DECISION") { event in
                            if event.isBlocking {
                                WisentStatusChip(text: event.decision, tone: .danger)
                            } else {
                                Text(event.decision)
                                    .font(WisentTypeScale.identifierSmall())
                                    .foregroundStyle(WisentDesign.muted)
                            }
                        }
                        .width(min: 60, ideal: 90)
                    }
                    .tableStyle(.inset)
                    .frame(height: tableHeight(rows: events.count))
                    // Click and drag inside a table belong to the table's own
                    // row handling, not to the text drawn in the cell. The
                    // blocking reason underneath the grid stays selectable,
                    // which is the sentence a person actually quotes.
                    .textSelection(.disabled)
                }
                if let reason = events.first(where: \.isBlocking)?.reason {
                    Text(reason)
                        .font(WisentTypeScale.caption())
                        .foregroundStyle(WisentDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// A table inside a scrolling column must state its height, or it asks for
    /// the height of its contents and drags the window with it.
    private func tableHeight(rows: Int) -> CGFloat {
        let header = WisentAppLayout.denseRowHeight
        let visible = min(rows, Int("8")!)
        return header + CGFloat(visible) * WisentAppLayout.tableRowHeight
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        if let session = model.selectedAgentSession {
            WisentInspector(
                eyebrow: session.agentDisplayName,
                title: session.sessionId,
                badges: inspectorBadges(session)
            ) {
                WisentField(label: "Project", value: session.cwd)
                WisentField(label: "Control key", value: shortIdentifier(session.controlKey))
                WisentField(label: "Updated at", value: session.updatedAt)
                if let policy = session.systemPolicy {
                    Divider()
                    WisentField(label: "Policy mode", value: policy.mode)
                    WisentField(label: "Policy backend", value: policy.backend ?? "Not reported")
                    WisentField(
                        label: "Backend capabilities",
                        value: policy.capabilities.isEmpty
                            ? "None reported"
                            : policy.capabilities.joined(separator: ", ")
                    )
                }
            }
        } else {
            WisentInspector(eyebrow: "Session", title: "No session selected") {
                Text("Session records are written by the supervised runtime into Application Support and removed when the process ends. Tama reads them; it never creates one.")
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    // MARK: - Per-session hook summary

    /// One table showing every live session and its hook state, so the
    /// operator sees "which hook on which session" without clicking through
    /// each session one at a time.
    @ViewBuilder
    private var sessionHookSummary: some View {
        if !model.agentSessions.isEmpty {
            WisentSectionBox(title: "Hook state per session") {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                    HStack {
                        Text("SESSION")
                            .font(WisentTypeScale.eyebrow())
                            .tracking(0.6)
                            .foregroundStyle(WisentDesign.muted)
                            .frame(width: 220, alignment: .leading)
                        Text("GLOBAL STATE")
                            .font(WisentTypeScale.eyebrow())
                            .tracking(0.6)
                            .foregroundStyle(WisentDesign.muted)
                            .frame(width: 120, alignment: .leading)
                        Text("LOADED")
                            .font(WisentTypeScale.eyebrow())
                            .tracking(0.6)
                            .foregroundStyle(WisentDesign.muted)
                            .frame(width: 60, alignment: .leading)
                        Text("ALLOWLIST")
                            .font(WisentTypeScale.eyebrow())
                            .tracking(0.6)
                            .foregroundStyle(WisentDesign.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Divider()
                    ForEach(model.agentSessions) { session in
                        HStack {
                            Text("\(session.agentDisplayName) · \(URL(fileURLWithPath: session.cwd).lastPathComponent)")
                                .font(WisentTypeScale.identifierSmall())
                                .foregroundStyle(WisentDesign.ink)
                                .lineLimit(1)
                                .frame(width: 220, alignment: .leading)
                            Text(session.globallyDisabled ? "Disabled" : "Enabled")
                                .font(WisentTypeScale.identifierSmall())
                                .foregroundStyle(session.globallyDisabled ? WisentDesign.warning : WisentDesign.success)
                                .frame(width: 120, alignment: .leading)
                            Text("\(session.runtime?.loadedHookCount ?? 0)")
                                .font(WisentTypeScale.identifierSmall())
                                .foregroundStyle(WisentDesign.secondary)
                                .monospacedDigit()
                                .frame(width: 60, alignment: .leading)
                            Text(session.globallyDisabled
                                ? session.enabledHookIds.isEmpty
                                    ? "empty"
                                    : session.enabledHookIds.joined(separator: ", ")
                                : "all (\(session.disabledHookIds.isEmpty ? "no overrides" : "\(session.disabledHookIds.count) disabled"))")
                                .font(WisentTypeScale.identifierSmall())
                                .foregroundStyle(WisentDesign.secondary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: WisentAppLayout.denseRowHeight)
                        Divider()
                    }
                }
            }
        }
    }

    private func inspectorBadges(_ session: AgentSessionRecord) -> [(String, WisentTone)] {
        var badges: [(String, WisentTone)] = []
        if let policy = session.systemPolicy {
            badges.append(
                policy.ready && policy.mode == "kernel-gated"
                    ? ("Kernel-gated", .success)
                    : (policy.configured ? ("Backend not ready", .warning) : ("Not configured", .neutral))
            )
        }
        if let capability = session.capability {
            badges.append((capability.lifetime, .brand))
        }
        return badges
    }
}
