import SwiftUI

struct ViolationReportView: View {
    let report: ViolationReport
    @ObservedObject var model: ViolationsModel
    @State private var isConfirmingClean = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary
                if report.totals.violations > 0 || model.cleanState != .idle {
                    cleanSection
                }
                if !report.problems.isEmpty {
                    GroupBox("Problems") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(report.problems, id: \.error) { problem in
                                Label(
                                    "\([problem.owner, problem.repo].compactMap { $0 }.joined(separator: " ")): \(problem.error)",
                                    systemImage: "exclamationmark.triangle.fill"
                                )
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                ForEach(report.repos) { repo in
                    repoSection(repo)
                }
            }
            .padding()
        }
        .alert(
            "Clean violations with a headless agent?",
            isPresented: $isConfirmingClean
        ) {
            Button("Clean violations") {
                Task { await model.clean() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "A headless model agent will edit files in \(model.repoPath) to resolve the violations. "
                    + "It only changes the repository working tree and never commits. "
                    + "This can take several minutes; review the result with git diff afterwards."
            )
        }
    }

    private var summary: some View {
        GroupBox("Summary") {
            LabeledContent("Files scanned", value: report.scannedFiles.formatted())
            Divider()
            LabeledContent("Skipped files", value: report.skippedFiles.formatted())
            Divider()
            LabeledContent("Scan errors", value: report.scanErrors.formatted())
            Divider()
            LabeledContent("Total violations") {
                Text(report.totals.violations.formatted())
                    .foregroundStyle(report.totals.violations > 0 ? .red : .green)
            }
        }
    }

    private var cleanSection: some View {
        GroupBox("Clean") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    switch model.cleanState {
                    case .idle:
                        Text("A headless model agent can try to resolve these violations.")
                            .foregroundStyle(.secondary)
                    case .running:
                        ProgressView()
                            .controlSize(.small)
                        Text("Cleaning… a headless model agent is editing the working tree.")
                            .foregroundStyle(.secondary)
                    case .done:
                        Label("Clean finished", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failed:
                        Label("Clean failed", systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    if report.totals.violations > 0 {
                        Button("Clean violations", systemImage: "wand.and.stars") {
                            isConfirmingClean = true
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.cleanState == .running)
                    }
                }
                if case let .done(summary) = model.cleanState {
                    Text(summary)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if case let .failed(message) = model.cleanState {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func repoSection(_ repo: ViolationRepoReport) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Repository") {
                    Text(repo.repo)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                LabeledContent("Enumeration", value: repo.mode)

                if repo.violations.isEmpty {
                    Label("No violations found", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ForEach(repo.ruleGroups) { group in
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(group.violations) { violation in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(violation.path)
                                            .font(.body.monospaced())
                                            .textSelection(.enabled)
                                        Text(violation.message)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        } label: {
                            HStack {
                                Text(group.rule)
                                    .font(.headline)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(group.violations.count.formatted()) hit(s)")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                if !repo.errors.isEmpty {
                    DisclosureGroup("Scan errors (\(repo.errors.count.formatted()))") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(repo.errors, id: \.path) { error in
                                Text("\(error.path) — \(error.message)")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }

                if !repo.skippedFiles.isEmpty {
                    DisclosureGroup("Skipped files (\(repo.skippedFiles.count.formatted()))") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(repo.skippedFiles, id: \.path) { skipped in
                                Text("\(skipped.path) — \(skipped.reason)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
