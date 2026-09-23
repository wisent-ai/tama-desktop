import SwiftUI
import WisentDesignSystem

extension SessionView {
    @ViewBuilder
    func grants(_ session: AgentSessionRecord) -> some View {
        let grants = session.capability?.grants ?? []
        WisentSectionBox(
            title: "Tool access",
            detail: "Allowed tools and actions.",
            trailing: counted(grants.count, "grant")
        ) {
            if grants.isEmpty {
                WisentPanel {
                    Text("No additional access is granted.")
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
    func runtime(_ session: AgentSessionRecord) -> some View {
        WisentSectionBox(
            title: "Session status",
            trailing: session.runtime.map(TamaTone.runtimeLabel) ?? "not reported"
        ) {
            WisentPanel {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                    HStack(alignment: .top, spacing: WisentDesign.Space.x4) {
                        WisentField(
                            label: "Session release",
                            value: session.runtime?.loadedReleaseId ?? "Not reported"
                        )
                        WisentField(
                            label: "Installed release",
                            value: session.runtime?.installedReleaseId ?? "Not reported"
                        )
                    }
                    if session.globallyDisabled {
                        Divider()
                        Text("Only selected policies are enabled for this session.")
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
    func decisions(_ session: AgentSessionRecord) -> some View {
        let events = (session.semanticRuntime?.recentEvents ?? []).reversed().map { $0 }
        WisentSectionBox(
            title: "Recent decisions",
            detail: "Latest policy decisions.",
            trailing: counted(events.filter(\.isBlocking).count, "block")
        ) {
            if events.isEmpty {
                WisentPanel {
                    Text("No decisions yet.")
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
                        TableColumn("POLICY") { event in
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
    static let visibleDecisionRows = 8
    func tableHeight(rows: Int) -> CGFloat {
        let header = WisentAppLayout.denseRowHeight
        let visible = min(rows, Self.visibleDecisionRows)
        return header + CGFloat(visible) * WisentAppLayout.tableRowHeight
    }
    @ViewBuilder
    var inspector: some View {
        if let session = model.selectedAgentSession {
            WisentInspector(
                eyebrow: session.agentDisplayName,
                title: session.sessionId,
                badges: inspectorBadges(session)
            ) {
                WisentField(label: "Project", value: session.cwd)
                WisentField(label: "Updated at", value: session.updatedAt)
                if let policy = session.systemPolicy {
                    Divider()
                    WisentField(label: "Policy mode", value: policy.mode)
                }
            }
        } else {
            WisentInspector(eyebrow: "Session", title: "No session selected") {
                Text("Select a session to view its policy and access.")
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    /// One table showing every live session and its hook state, so the
    /// operator sees "which hook on which session" without clicking through
    /// each session one at a time.
    @ViewBuilder
    var sessionHookSummary: some View {
        if !model.agentSessions.isEmpty {
            WisentSectionBox(title: "Policy state per session") {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                    HStack {
                        Text("SESSION")
                            .font(WisentTypeScale.eyebrow())
                            .tracking(0.6)
                            .foregroundStyle(WisentDesign.muted)
                            .frame(width: 220, alignment: .leading)
                        Text("POLICY STATE")
                            .font(WisentTypeScale.eyebrow())
                            .tracking(0.6)
                            .foregroundStyle(WisentDesign.muted)
                            .frame(width: 120, alignment: .leading)
                        Text("ACTIVE")
                            .font(WisentTypeScale.eyebrow())
                            .tracking(0.6)
                            .foregroundStyle(WisentDesign.muted)
                            .frame(width: 60, alignment: .leading)
                        Text("ENABLED POLICIES")
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
                            Text(session.globallyDisabled ? "Limited" : "Enabled")
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
                                    ? "None"
                                    : session.enabledHookIds.joined(separator: ", ")
                                : session.disabledHookIds.isEmpty ? "All" : "\(session.disabledHookIds.count) disabled")
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
    func inspectorBadges(_ session: AgentSessionRecord) -> [(String, WisentTone)] {
        var badges: [(String, WisentTone)] = []
        if let policy = session.systemPolicy {
            badges.append(
                policy.ready && policy.mode == "kernel-gated"
                    ? ("Protected", .success)
                    : (policy.configured ? ("Protection unavailable", .warning) : ("Protection not set up", .neutral))
            )
        }
        if let capability = session.capability {
            badges.append((capability.lifetime, .brand))
        }
        return badges
    }
}
