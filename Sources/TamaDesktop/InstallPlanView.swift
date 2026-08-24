import SwiftUI
import WisentDesignSystem

/// Where an install would write, scope by scope, and the MCP snippet that goes
/// with it.
///
/// The install plan and the MCP snippet had no surface, so an operator
/// approving a privileged install could not see which files it would touch. The
/// plan is read-only: this screen states target paths, and performs none of
/// the changes.
struct InstallPlanView: View {
    @ObservedObject var inspection: InspectionModel

    var body: some View {
        WisentScreen(
            title: "Install plan",
            scope: inspection.plan.map { _ in "planned changes" },
            freshness: freshness,
            actions: [
                WisentAction(
                    "Re-read plan",
                    symbol: "arrow.clockwise",
                    kind: .secondary,
                    isEnabled: !inspection.isReadingPlan
                ) {
                    Task { await inspection.loadPlan(force: true) }
                }
            ]
        ) {
            if let planError = inspection.planError {
                WisentAlertPanel(
                    tone: .danger,
                    title: "Install plan could not be read",
                    detail: planError,
                                        actions: [
                        WisentAction("Retry", symbol: "arrow.clockwise", kind: .primary) {
                            Task { await inspection.loadPlan(force: true) }
                        }
                    ]
                )
            }
            if let plan = inspection.plan {
                signals(plan)
                ForEach(plan.levels) { level($0) }
                mcpSection
            } else if inspection.isReadingPlan {
                WisentLoadingPanel(
                    title: "Reading the install plan",
                    detail: "Scopes, the files each one would write, and the commands that write them."
                )
            } else if inspection.planError == nil {
                WisentEmptyPanel(
                    title: "No plan has been read yet",
                    detail: "The plan is derived from the bundled release and your home directory. Nothing is written to read it.",
                    symbol: "shippingbox",
                    action: WisentAction("Read the plan", kind: .primary) {
                        Task { await inspection.loadPlan(force: true) }
                    }
                )
            }
        }
        .task { await inspection.loadPlan() }
    }

    private var freshness: String {
        if inspection.isReadingPlan { return "reading now" }
        guard let readAt = inspection.planReadAt else { return "not read yet" }
        return "read \(readAt.formatted(date: .omitted, time: .standard))"
    }

    /// Nothing in the plan is active by the archive alone; saying so once in a
    /// strip is enough, and it is the healthy state.
    private func signals(_ plan: InstallPlan) -> some View {
        WisentSignalStrip(signals: [
            WisentSignal("Archive root", value: plan.archiveRoot, tone: .success),
            WisentSignal("Scopes", value: counted(plan.levels.count, "scope")),
            WisentSignal(
                "Active by archive alone",
                value: plan.levels.contains(where: \.activeByArchiveAlone) ? "Some" : "None",
                tone: .neutral
            )
        ])
    }

    private func level(_ level: InstallPlanLevel) -> some View {
        WisentSectionBox(
            title: level.level,
            detail: level.notes.first,
            trailing: level.activeByArchiveAlone ? "active" : "needs a runtime"
        ) {
            WisentPanel(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(level.fields) { field in
                        HStack(alignment: .firstTextBaseline, spacing: WisentDesign.Space.x4) {
                            Text(field.label.uppercased())
                                .font(WisentTypeScale.eyebrow())
                                .tracking(0.6)
                                .foregroundStyle(WisentDesign.muted)
                                .frame(width: 168, alignment: .leading)
                            Text(field.value)
                                .font(WisentTypeScale.identifierSmall())
                                .foregroundStyle(WisentDesign.ink)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, WisentDesign.Space.x4)
                        .frame(minHeight: WisentAppLayout.denseRowHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                    }
                    ForEach(level.notes.dropFirst(), id: \.self) { note in
                        Text(note)
                            .font(WisentTypeScale.caption())
                            .foregroundStyle(WisentDesign.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(WisentDesign.Space.x4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var mcpSection: some View {
        WisentSectionBox(
            title: "MCP server",
            detail: "Paste this into a client configuration to expose the bundled Tama tools.",
                    ) {
            if let mcpError = inspection.mcpError {
                WisentAlertPanel(
                    tone: .warning,
                    title: "MCP snippet could not be read",
                    detail: mcpError,
                                    )
            } else if let configuration = inspection.mcpConfiguration {
                WisentPanel {
                    Text(configuration)
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(WisentDesign.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if inspection.isReadingMCP {
                WisentLoadingPanel(
                    title: "Reading the MCP snippet",
                    detail: "The server command and arguments for this release."
                )
            }
        }
    }
}
