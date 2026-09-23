import SwiftUI
import WisentDesignSystem

/// Findings in the repository under repair, and the one irreversible verb.
///
/// Three zones: rules on the left, the findings table in the middle, the
/// selected finding on the right. The baseline nested disclosure groups per
/// repository inside a scrolling page, so counting how many files one rule hit
/// meant expanding it and counting rows by eye.
struct ViolationsView: View {
    @ObservedObject var model: ViolationsModel
    let hasScope: Bool

    @State var ruleFacet: String?
    @State var repoFacet: String?
    @State var selection: ViolationRecord.ID?
    @State var isDecidingRepair = false

    var body: some View {
        let visible = filtered

        return WisentScreen(
            title: "Violations",
            scope: hasScope ? URL(fileURLWithPath: model.repoPath).lastPathComponent : nil,
            freshness: freshness,
            actions: actions,
            scrolls: false,
            constrainsWidth: false
        ) {
            HStack(spacing: 0) {
                WisentFacetRail(
                    groups: facetGroups,
                    footerTitle: "Selection",
                    footerDetail: "\(visible.count.formatted(.number)) of \((model.report?.totals.violations ?? .zero).formatted(.number))"
                )
                centre(visible: visible)
                inspector
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .sheet(isPresented: $isDecidingRepair) { repairDecision }
    }

    // MARK: - Context bar

    var freshness: String {
        switch model.scanState {
        case .idle: hasScope ? "not scanned" : "no repository selected"
        case .scanning: "scanning now"
        case .failed: "scan failed"
        case .done: counted(model.report?.scannedFiles ?? .zero, "file scanned")
        }
    }

    var actions: [WisentAction] {
        var actions: [WisentAction] = []
        if model.scanState == .scanning {
            actions.append(
                WisentAction("Stop scan", kind: .destructive) { model.cancelScan() }
            )
        } else {
            actions.append(
                WisentAction(
                    "Scan",
                    symbol: "magnifyingglass",
                    kind: .primary,
                    isEnabled: model.canScan
                ) {
                    Task { await model.scan() }
                }
            )
        }
        if model.cleanState == .running {
            actions.append(
                WisentAction("Stop repair", kind: .destructive) { model.cancelClean() }
            )
        } else if model.hasViolations {
            actions.append(
                WisentAction(
                    "Repair",
                    symbol: "wand.and.stars",
                    kind: .secondary,
                    isEnabled: model.canScan
                ) {
                    isDecidingRepair = true
                }
            )
        }
        return actions
    }

    // MARK: - Facets

    var report: ViolationReport? { model.report }

    var facetGroups: [WisentFacetGroup] {
        var groups: [WisentFacetGroup] = []
        if let ruleGroup { groups.append(ruleGroup) }
        if let repoGroup { groups.append(repoGroup) }
        return groups
    }

    /// Rules ranked by how many files they hit, because that is the order an
    /// operator repairs them in. Aggregated before rendering, not counted by eye.
    var ruleGroup: WisentFacetGroup? {
        guard let report, !report.allViolations.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for violation in report.allViolations {
            counts[violation.rule, default: .zero] += 1
        }
        let ranked = counts.sorted { left, right in
            left.value == right.value ? left.key < right.key : left.value > right.value
        }
        return WisentFacetGroup(
            "Rule",
            facets: [
                WisentFacet(
                    id: "rule.all",
                    label: "Every rule",
                    count: report.allViolations.count,
                    tone: .warning,
                    isSelected: ruleFacet == nil
                ) {
                    ruleFacet = nil
                }
            ] + ranked.map { rule, count in
                WisentFacet(
                    id: "rule.\(rule)",
                    label: rule,
                    count: count,
                    isSelected: ruleFacet == rule
                ) {
                    ruleFacet = ruleFacet == rule ? nil : rule
                }
            }
        )
    }

    var repoGroup: WisentFacetGroup? {
        guard let report, report.repos.count > Int("1")! else { return nil }
        return WisentFacetGroup(
            "Repository",
            facets: report.repos.map { repo in
                WisentFacet(
                    id: "repo.\(repo.repo)",
                    label: URL(fileURLWithPath: repo.repo).lastPathComponent,
                    count: repo.violations.count,
                    isSelected: repoFacet == repo.repo
                ) {
                    repoFacet = repoFacet == repo.repo ? nil : repo.repo
                }
            }
        )
    }

    var filtered: [ViolationRecord] {
        guard let report else { return [] }
        let scoped = repoFacet
            .flatMap { path in report.repos.first { $0.repo == path }?.violations }
            ?? report.allViolations
        guard let ruleFacet else { return scoped }
        return scoped.filter { $0.rule == ruleFacet }
    }

    // MARK: - Centre

    @ViewBuilder
    func centre(visible: [ViolationRecord]) -> some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
            cleanBar
            if case let .failed(message) = model.scanState {
                // A scan that failed keeps the previous report on screen when
                // there is one: the findings the operator was reading are still
                // the findings that were true a minute ago.
                WisentAlertPanel(
                    tone: .danger,
                    title: "Scan failed",
                    detail: message,
                                        actions: [
                        WisentAction(
                            "Scan again",
                            symbol: "arrow.clockwise",
                            kind: .primary,
                            isEnabled: model.canScan
                        ) {
                            Task { await model.scan() }
                        }
                    ]
                )
            }
            if case let .failed(message) = model.cleanState {
                WisentAlertPanel(
                    tone: .danger,
                    title: "Repair failed",
                    detail: message,
                                    )
            }
            if let report { counters(report) }
            problems
            content(visible: visible)
        }
        .padding(WisentDesign.Space.x5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The repair reports through one bar with the command's own words, in the
    /// same place whether it is running, finished or refused.
    @ViewBuilder
    var cleanBar: some View {
        switch model.cleanState {
        case .idle:
            EmptyView()
        case .running:
            WisentMutationBar(
                outcome: .working("Repairing the working tree."),
                clear: {}
            )
        case .cancelling:
            WisentMutationBar(
                outcome: .working("Stopping repair. Completed edits will remain."),
                clear: {}
            )
        case .rescanning:
            WisentMutationBar(
                outcome: .working("Checking the repaired files."),
                clear: {}
            )
        case let .done(summary):
            WisentMutationBar(outcome: .succeeded(summary), clear: {})
        case .failed:
            EmptyView()
        }
    }

    func counters(_ report: ViolationReport) -> some View {
        WisentCounterRow(counters: [
            WisentCounterRow.Counter(
                "Violations",
                value: report.totals.violations.formatted(.number),
                detail: "Findings across \(counted(report.totals.repositories, "repository"))",
                tone: report.totals.violations == .zero ? .success : .warning
            ),
            WisentCounterRow.Counter(
                "Files scanned",
                value: report.scannedFiles.formatted(.number),
                detail: "Repository inspection"
            ),
            WisentCounterRow.Counter(
                "Skipped",
                value: report.skippedFiles.formatted(.number),
                detail: "Binary or oversized inputs"
            ),
            WisentCounterRow.Counter(
                "Scan errors",
                value: report.scanErrors.formatted(.number),
                detail: "Files the scanner could not read",
                tone: report.scanErrors == .zero ? .neutral : .warning
            )
        ])
    }




    // MARK: - Inspector



    // MARK: - The decision

}
