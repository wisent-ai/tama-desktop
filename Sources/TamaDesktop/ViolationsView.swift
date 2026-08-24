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

    @State private var ruleFacet: String?
    @State private var repoFacet: String?
    @State private var selection: ViolationRecord.ID?
    @State private var isDecidingRepair = false

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

    private var freshness: String {
        switch model.scanState {
        case .idle: hasScope ? "not scanned" : "no repository selected"
        case .scanning: "scanning now"
        case .failed: "scan failed"
        case .done: counted(model.report?.scannedFiles ?? .zero, "file scanned")
        }
    }

    private var actions: [WisentAction] {
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

    private var report: ViolationReport? { model.report }

    private var facetGroups: [WisentFacetGroup] {
        var groups: [WisentFacetGroup] = []
        if let ruleGroup { groups.append(ruleGroup) }
        if let repoGroup { groups.append(repoGroup) }
        return groups
    }

    /// Rules ranked by how many files they hit, because that is the order an
    /// operator repairs them in. Aggregated before rendering, not counted by eye.
    private var ruleGroup: WisentFacetGroup? {
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

    private var repoGroup: WisentFacetGroup? {
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

    private var filtered: [ViolationRecord] {
        guard let report else { return [] }
        let scoped = repoFacet
            .flatMap { path in report.repos.first { $0.repo == path }?.violations }
            ?? report.allViolations
        guard let ruleFacet else { return scoped }
        return scoped.filter { $0.rule == ruleFacet }
    }

    // MARK: - Centre

    @ViewBuilder
    private func centre(visible: [ViolationRecord]) -> some View {
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
                    command: TamaCommand.findViolations(repository: model.repoPath),
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
                    title: "Repair did not finish clean",
                    detail: message,
                    command: TamaCommand.clean(repository: model.repoPath)
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
    private var cleanBar: some View {
        switch model.cleanState {
        case .idle:
            EmptyView()
        case .running:
            WisentMutationBar(
                outcome: .working("A headless agent is editing the working tree in \(model.repoPath)."),
                clear: {}
            )
        case .cancelling:
            WisentMutationBar(
                outcome: .working("Stopping the repair. Partial edits are preserved and rescanned."),
                clear: {}
            )
        case .rescanning:
            WisentMutationBar(
                outcome: .working("Rescanning the working tree before reporting the result."),
                clear: {}
            )
        case let .done(summary):
            WisentMutationBar(outcome: .succeeded(summary), clear: {})
        case .failed:
            EmptyView()
        }
    }

    private func counters(_ report: ViolationReport) -> some View {
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

    @ViewBuilder
    private var problems: some View {
        ForEach(Array((report?.problems ?? []).enumerated()), id: \.offset) { _, problem in
            WisentAlertPanel(
                tone: .warning,
                title: "The scanner could not enumerate \([problem.owner, problem.repo].compactMap { $0 }.joined(separator: "/"))",
                detail: problem.error,
                command: TamaCommand.findViolations(repository: model.repoPath)
            )
        }
    }

    @ViewBuilder
    private func content(visible: [ViolationRecord]) -> some View {
        if !hasScope {
            WisentEmptyPanel(
                title: "No repository is in view",
                detail: "Choose a Git repository you own in the sidebar. Tama enumerates it with the approved pre-write rules and reads nothing outside it.",
                symbol: "folder.badge.questionmark"
            )
            Spacer(minLength: 0)
        } else if model.scanState == .scanning {
            WisentLoadingPanel(
                title: "Scanning \(model.repoPath)",
                detail: "Every tracked file is checked against the pre-write rules this build declares. Nothing is written."
            )
            Spacer(minLength: 0)
        } else if model.report == nil {
            WisentEmptyPanel(
                title: "This repository has not been scanned",
                detail: "Scan the repository to list refused, skipped, and unreadable files before choosing a clean operation.",
                symbol: "magnifyingglass",
                action: WisentAction("Scan", kind: .primary, isEnabled: model.canScan) {
                    Task { await model.scan() }
                }
            )
            Spacer(minLength: 0)
        } else if !model.hasViolations {
            WisentEmptyPanel(
                title: "No violation in this working tree",
                detail: "Every scanned file satisfies the pre-write rules this build declares.",
                symbol: "checkmark.seal"
            )
            Spacer(minLength: 0)
        } else if visible.isEmpty {
            WisentEmptyPanel(
                title: "No finding matches this selection",
                detail: "The scan reported \(counted(model.report?.totals.violations ?? .zero, "violation")). The facets in force exclude every one of them.",
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

    private func table(visible: [ViolationRecord]) -> some View {
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
                TableColumn("HOOK") { violation in
                    Text(violation.hook)
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(WisentDesign.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .width(min: 60, ideal: 110)
            }
            .tableStyle(.inset)
        }
    }

    // MARK: - Inspector

    private var selectedViolation: ViolationRecord? {
        guard let selection else { return nil }
        return report?.allViolations.first { $0.id == selection }
    }

    @ViewBuilder
    private var inspector: some View {
        if let violation = selectedViolation {
            WisentInspector(
                eyebrow: violation.rule,
                title: violation.path,
                badges: [("Refused on write", .warning)]
            ) {
                Text(violation.message)
                    .font(WisentTypeScale.body())
                    .foregroundStyle(WisentDesign.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                WisentField(label: "Hook", value: violation.hook)
                WisentField(label: "Repository", value: model.repoPath)
            }
        } else {
            WisentInspector(
                eyebrow: "Finding",
                title: model.report == nil ? "Nothing scanned yet" : "No finding selected"
            ) {
                Text("Choose a row to read the sentence the hook would print when it refuses the write.")
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                WisentCapabilityList(
                    title: "This screen can",
                    items: [
                        "Enumerate a repository you own",
                        "Ask one headless agent to edit the working tree",
                    ],
                    isAvailable: true
                )
                WisentCapabilityList(
                    title: "It never can",
                    items: [
                        "Commit, push, or move a branch ref",
                        "Touch a repository owned by another user",
                        "Repair without a final rescan",
                    ],
                    isAvailable: false
                )
            }
        }
    }

    // MARK: - The decision

    /// A headless model agent editing a working tree is not undoable from here:
    /// the edits land in files the operator has open, and only the final rescan
    /// says whether they were an improvement.
    private var repairDecision: some View {
        let paths = Set((report?.allViolations ?? []).map(\.path)).sorted()
        return WisentDecisionDialog(
            tone: .danger,
            title: "Let a headless agent edit \(counted(paths.count, "file")) in this working tree",
            lines: [
                "One external model agent per repository edits \(model.repoPath) until the findings are gone or its bounded rounds are spent. The provider is external to Tama.",
                "Tama requests working-tree edits only. It rejects a changed HEAD, a changed checked-out branch and changed local branch refs, and it never commits or pushes.",
                "A final rescan always runs, and the reported result is that rescan rather than the agent's own claim.",
                "Review git status, branch refs, remote state and the final diff afterwards."
            ],
            reasonCode: model.report.map { "\($0.totals.violations) violations in \($0.totals.repositories) repositories" },
            listing: paths,
            footnote: "the agent runs with Codex; Tama refuses to start the repair when Codex is absent",
            actions: [
                WisentAction("Cancel", kind: .plain) { isDecidingRepair = false },
                WisentAction("Repair with a headless agent", kind: .destructive) {
                    isDecidingRepair = false
                    Task { await model.clean() }
                },
                WisentAction("Read the findings first", kind: .primary) {
                    isDecidingRepair = false
                }
            ]
        )
    }
}
