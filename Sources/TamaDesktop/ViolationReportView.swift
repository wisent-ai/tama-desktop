import SwiftUI
import WisentDesignSystem

struct ViolationReportView: View {
    let report: ViolationReport
    @ObservedObject var model: ViolationsModel
    @State private var isConfirmingClean = false

    var body: some View {
        TamaPage {
            HStack(alignment: .firstTextBaseline) {
                WisentSectionHeader(
                    "Scan report",
                    detail: "Read-only findings for the selected working tree",
                    trailing: "\(report.totals.violations.formatted()) violations"
                )
                Spacer()
                WisentBadge(
                    report.totals.violations == 0 ? "Clean" : "Review required",
                    symbol: report.totals.violations == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    tone: report.totals.violations == 0 ? .success : .warning
                )
            }
            summary
            if report.totals.violations > 0 || model.cleanState != .idle { cleanSection }
            if !report.problems.isEmpty { problemsSection }
            ForEach(report.repos) { repo in repoSection(repo) }
        }
        .alert("Clean violations with a headless agent?", isPresented: $isConfirmingClean) {
            Button("Clean violations") { Task { await model.clean() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A headless model agent will edit files in \(model.repoPath) to resolve the violations. Tama requests working-tree edits only and rejects changed HEAD, checked-out branch, or local branch refs; it does not perform commits or pushes itself. The provider remains external. Review git status, branch refs, remote state, and the final diff afterwards.")
        }
    }

    private var summary: some View {
        TamaPanelSection("Summary", detail: "Scanner coverage and result totals") {
            LabeledContent("Files scanned", value: report.scannedFiles.formatted())
            Divider()
            LabeledContent("Skipped files", value: report.skippedFiles.formatted())
            Divider()
            LabeledContent("Scan errors", value: report.scanErrors.formatted())
            Divider()
            LabeledContent("Total violations") {
                WisentBadge(
                    report.totals.violations.formatted(),
                    symbol: report.totals.violations > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                    tone: report.totals.violations > 0 ? .danger : .success
                )
            }
        }
    }

    private var cleanSection: some View {
        TamaPanelSection("Agent-assisted cleanup", detail: "Explicit working-tree edits with a mandatory final rescan") {
            HStack(spacing: WisentDesign.Space.x3) {
                cleanStatus
                Spacer()
                if model.cleanState == .running {
                    Button("Stop cleanup", role: .destructive) { model.cancelClean() }
                } else if report.totals.violations > 0 {
                    Button("Clean violations", systemImage: "wand.and.stars") { isConfirmingClean = true }
                        .buttonStyle(WisentPrimaryButtonStyle())
                        .disabled(model.cleanState == .cancelling || model.cleanState == .rescanning)
                }
            }
            if case let .done(summary) = model.cleanState {
                Text(summary)
                    .font(WisentTypography.mono(10))
                    .foregroundStyle(WisentDesign.secondary)
                    .textSelection(.enabled)
            }
            if case let .failed(message) = model.cleanState {
                TamaNotice(title: "Cleanup failed", detail: message, symbol: "xmark.octagon.fill", tone: .danger)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var cleanStatus: some View {
        switch model.cleanState {
        case .idle:
            Text("A headless model agent can try to resolve these violations.")
                .font(WisentTypography.body(12))
                .foregroundStyle(WisentDesign.secondary)
        case .running:
            ProgressView("Cleaning… a headless model agent is editing the working tree.")
        case .cancelling:
            ProgressView("Stopping cleanup… partial edits will be preserved and rescanned.")
        case .rescanning:
            ProgressView("Rescanning the working tree before reporting the result…")
        case .done:
            WisentBadge("Clean finished", symbol: "checkmark.circle.fill", tone: .success)
        case .failed:
            WisentBadge("Clean failed", symbol: "xmark.octagon.fill", tone: .danger)
        }
    }

    private var problemsSection: some View {
        TamaPanelSection("Problems", detail: "Repository-level failures reported by the scanner") {
            ForEach(Array(report.problems.enumerated()), id: \.offset) { index, problem in
                if index > 0 { Divider() }
                Label(
                    "\([problem.owner, problem.repo].compactMap { $0 }.joined(separator: " ")): \(problem.error)",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(WisentTypography.body(12))
                .foregroundStyle(WisentDesign.danger)
                .textSelection(.enabled)
            }
        }
    }

    private func repoSection(_ repo: ViolationRepoReport) -> some View {
        TamaPanelSection(repo.repo, detail: "\(repo.mode) enumeration") {
            LabeledContent("Repository") {
                Text(repo.repo).font(WisentTypography.mono(10)).textSelection(.enabled)
            }
            LabeledContent("Enumeration", value: repo.mode)

            if repo.violations.isEmpty {
                WisentBadge("No violations found", symbol: "checkmark.circle.fill", tone: .success)
            } else {
                Divider()
                ForEach(repo.ruleGroups) { group in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                            ForEach(group.violations) { violation in
                                VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                                    Text(violation.path)
                                        .font(WisentTypography.monoMedium(11))
                                        .foregroundStyle(WisentDesign.ink)
                                        .textSelection(.enabled)
                                    Text(violation.message)
                                        .font(WisentTypography.body(12))
                                        .foregroundStyle(WisentDesign.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(.vertical, WisentDesign.Space.x2)
                    } label: {
                        HStack {
                            Text(group.rule).font(WisentTypography.bodyMedium(13)).lineLimit(1)
                            Spacer()
                            WisentBadge("\(group.violations.count.formatted()) hits", tone: .warning)
                        }
                    }
                }
            }

            if !repo.errors.isEmpty {
                Divider()
                DisclosureGroup("Scan errors (\(repo.errors.count.formatted()))") {
                    VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                        ForEach(repo.errors, id: \.path) { error in
                            Text("\(error.path) — \(error.message)")
                                .font(WisentTypography.body(11))
                                .foregroundStyle(WisentDesign.danger)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, WisentDesign.Space.x2)
                }
            }

            if !repo.skippedFiles.isEmpty {
                Divider()
                DisclosureGroup("Skipped files (\(repo.skippedFiles.count.formatted()))") {
                    VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                        ForEach(repo.skippedFiles, id: \.path) { skipped in
                            Text("\(skipped.path) — \(skipped.reason)")
                                .font(WisentTypography.body(11))
                                .foregroundStyle(WisentDesign.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, WisentDesign.Space.x2)
                }
            }
        }
    }
}
