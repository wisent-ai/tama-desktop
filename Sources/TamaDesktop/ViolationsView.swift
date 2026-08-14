import SwiftUI
import WisentDesignSystem

struct ViolationsView: View {
    @ObservedObject var model: ViolationsModel

    var body: some View {
        ZStack {
            WisentCanvasBackground()
            VStack(spacing: 0) {
                controls
                Divider()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
            WisentPageHeader(
                eyebrow: "Repository analysis",
                title: "Policy violations",
                detail: "Scan a local working tree against approved pre-write rules, then explicitly review any agent-assisted cleanup.",
                symbol: "ladybug",
                tone: .warning
            )
            HStack(spacing: WisentDesign.Space.x3) {
                TextField("Repository path", text: $model.repoPath)
                    .textFieldStyle(.roundedBorder)
                    .font(WisentTypography.mono(12))
                    .onSubmit {
                        if model.canScan { Task { await model.scan() } }
                    }
                Button("Reset", systemImage: "arrow.counterclockwise") { model.resetRepoPath() }
                    .labelStyle(.iconOnly)
                    .help("Clear the repository path")
                    .disabled(!model.isRepoPathModified)
                Button("Scan", systemImage: "magnifyingglass") { Task { await model.scan() } }
                    .buttonStyle(WisentPrimaryButtonStyle())
                    .disabled(!model.canScan)
            }
        }
        .padding(WisentDesign.Space.x6)
        .background(WisentDesign.surface)
    }

    @ViewBuilder
    private var content: some View {
        switch model.scanState {
        case .idle:
            WisentEmptyState(
                title: "Choose a repository to inspect",
                detail: "Enter a local repository path and run a read-only scan. Tama reports matching files, skipped inputs, and scanner errors.",
                symbol: "folder.badge.questionmark"
            )
        case .scanning:
            VStack(spacing: WisentDesign.Space.x4) {
                ProgressView("Scanning \(model.repoPath)…")
                    .font(WisentTypography.bodyMedium(13))
                Button("Stop scan", role: .destructive) { model.cancelScan() }
                    .buttonStyle(WisentSecondaryButtonStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            VStack(spacing: WisentDesign.Space.x4) {
                WisentEmptyState(title: "Scan failed", detail: message, symbol: "exclamationmark.triangle")
                Button("Scan again") { Task { await model.scan() } }
                    .buttonStyle(WisentSecondaryButtonStyle())
                    .disabled(!model.canScan)
            }
        case .done:
            if let report = model.report {
                ViolationReportView(report: report, model: model)
            } else {
                WisentEmptyState(
                    title: "No report",
                    detail: "The scan finished without a report. Refresh the repository path and run it again.",
                    symbol: "doc.badge.ellipsis"
                )
            }
        }
    }
}
