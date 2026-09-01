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
                    detail: "Preparing the planned changes."
                )
            } else if inspection.planError == nil {
                WisentEmptyPanel(
                    title: "No plan has been read yet",
                    detail: "Read the plan before installation.",
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
            WisentSignal("Scopes", value: counted(plan.levels.count, "scope")),
            WisentSignal(
                "Additional setup",
                value: plan.levels.allSatisfy(\.activeByArchiveAlone) ? "None" : "Required",
                tone: .neutral
            )
        ])
    }

    private func level(_ level: InstallPlanLevel) -> some View {
        WisentSectionBox(
            title: level.level,
            detail: setupGuidance(for: level).first,
            trailing: level.activeByArchiveAlone ? "ready" : "setup required"
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
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, WisentDesign.Space.x4)
                        .frame(minHeight: WisentAppLayout.denseRowHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                    }
                    ForEach(setupGuidance(for: level).dropFirst(), id: \.self) { guidance in
                        Text(guidance)
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

    private func setupGuidance(for level: InstallPlanLevel) -> [String] {
        if level.key == "os-level" {
            return [
                "After installation, open System Settings and enable Tama’s whole-computer protection. The installer cannot enable it for you."
            ]
        }
        if !level.notes.isEmpty {
            return level.notes
        }
        return [
            level.activeByArchiveAlone
                ? "Included in the installation."
                : "Finish the remaining setup shown below before protection is active."
        ]
    }

    @ViewBuilder
    private var mcpSection: some View {
        WisentSectionBox(
            title: "Tool connection",
            detail: "Use this configuration in your client."
        ) {
            if let mcpError = inspection.mcpError {
                WisentAlertPanel(
                    tone: .warning,
                    title: "Configuration could not be read",
                    detail: mcpError,
                                    )
            } else if let configuration = inspection.mcpConfiguration {
                WisentPanel {
                    Text(configuration)
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(WisentDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if inspection.isReadingMCP {
                WisentLoadingPanel(
                    title: "Reading configuration",
                    detail: "Preparing the connection details."
                )
            }
        }
    }
}
