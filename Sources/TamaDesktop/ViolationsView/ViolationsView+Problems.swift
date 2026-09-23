import SwiftUI
import WisentDesignSystem

extension ViolationsView {
    @ViewBuilder
    var problems: some View {
        ForEach(Array((report?.problems ?? []).enumerated()), id: \.offset) { _, problem in
            WisentAlertPanel(
                tone: .warning,
                title: "The scanner could not enumerate \([problem.owner, problem.repo].compactMap { $0 }.joined(separator: "/"))",
                detail: problem.error,
                            )
        }
    }
    @ViewBuilder
    func content(visible: [ViolationRecord]) -> some View {
        if !hasScope {
            WisentEmptyPanel(
                title: "No repository selected",
                detail: "Choose a repository to scan.",
                symbol: "folder.badge.questionmark"
            )
            Spacer(minLength: 0)
        } else if model.scanState == .scanning {
            WisentProgressPanel(
                title: "Scanning \(URL(fileURLWithPath: model.repoPath).lastPathComponent)",
                detail: "Checking tracked files."
            )
            Spacer(minLength: 0)
        } else if model.report == nil {
            WisentEmptyPanel(
                title: "This repository has not been scanned",
                detail: "Scan to find blocked, skipped, or unreadable files.",
                symbol: "magnifyingglass",
                action: WisentAction("Scan", kind: .primary, isEnabled: model.canScan) {
                    Task { await model.scan() }
                }
            )
            Spacer(minLength: 0)
        } else if !model.hasViolations {
            WisentEmptyPanel(
                title: "No violations found",
                detail: "No scanned file violates a policy.",
                symbol: "checkmark.seal"
            )
            Spacer(minLength: 0)
        } else if visible.isEmpty {
            WisentEmptyPanel(
                title: "No finding matches this selection",
                detail: "\(counted(model.report?.totals.violations ?? .zero, "finding")) available. Clear the filters to see all findings.",
                symbol: "line.3.horizontal.decrease.circle",
                action: WisentAction("Clear filters", kind: .secondary) {
                    ruleFacet = nil
                    repoFacet = nil
                }
            )
            Spacer(minLength: 0)
        } else {
            table(visible: visible)
        }
    }
    func table(visible: [ViolationRecord]) -> some View {
        WisentTableFrame {
            Table(visible, selection: $selection) {
                TableColumn("PATH") { violation in
                    Text(violation.path)
                        .font(WisentTypeScale.identifier())
                        .foregroundStyle(WisentDesign.ink)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .help(violation.path)
                        .frame(height: WisentAppLayout.tableRowHeight, alignment: .leading)
                }
                .width(min: 130, ideal: 210)
                TableColumn("RULE") { violation in
                    Text(violation.rule)
                        .font(WisentTypeScale.body())
                        .foregroundStyle(WisentDesign.secondary)
                        .lineLimit(1)
                        .help(violation.rule)
                }
                .width(min: 90, ideal: 160)
                TableColumn("POLICY") { violation in
                    Text(violation.hook)
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(WisentDesign.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .width(min: 60, ideal: 110)
            }
            .tableStyle(.inset)
            // A click on this table already means "select this finding" and a
            // drag means "extend that selection", so selectable cell text would
            // compete with both. Opting out restores exactly the behaviour the
            // index had before the window turned selection on.
            .textSelection(.disabled)
        }
    }
    var selectedViolation: ViolationRecord? {
        guard let selection else { return nil }
        return report?.allViolations.first { $0.id == selection }
    }
    @ViewBuilder
    var inspector: some View {
        if let violation = selectedViolation {
            WisentInspector(
                eyebrow: violation.rule,
                title: violation.path,
                badges: [("Refused on write", .warning)]
            ) {
                Text(violation.message)
                    .font(WisentTypeScale.body())
                    .foregroundStyle(WisentDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                WisentField(label: "Policy", value: violation.hook)
                WisentField(label: "Repository", value: model.repoPath)
            }
        } else {
            WisentInspector(
                eyebrow: "Finding",
                title: model.report == nil ? "Nothing scanned yet" : "No finding selected"
            ) {
                Text("Select a finding to view why it was blocked.")
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    /// A headless model agent editing a working tree is not undoable from here:
    /// the edits land in files the operator has open, and only the final rescan
    /// says whether they were an improvement.
    var repairDecision: some View {
        let paths = Set((report?.allViolations ?? []).map(\.path)).sorted()
        return WisentDecisionDialog(
            tone: .danger,
            title: "Repair findings in the selected repository",
            lines: [
                "An external agent may edit, move, or create files throughout the selected repository.",
                "Tama will not commit or push the changes.",
                "Review the changes after the final scan.",
            ],
            listing: paths,
            actions: [
                WisentAction("Cancel", kind: .plain) { isDecidingRepair = false },
                WisentAction("Repair", kind: .destructive) {
                    isDecidingRepair = false
                    Task { await model.clean() }
                },
                WisentAction("Read the findings first", kind: .primary) {
                    isDecidingRepair = false
                },
            ]
        )
    }
}
