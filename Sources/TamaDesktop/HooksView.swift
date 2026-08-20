import SwiftUI
import WisentDesignSystem

/// The approved catalog, and the per-hook decision that goes with it.
///
/// Three zones: facets on the left, the table in the middle, the selected hook
/// on the right. The facet rail replaces a segmented picker that carried no
/// counts, and the table replaces three-line rows: an operator comparing 40
/// policies reads identifiers, not paragraphs.
struct HooksView: View {
    @ObservedObject var model: AppModel

    @State private var query = ""
    @State private var enforcement: EnforcementFacet = .all
    @State private var categoryFacet: String?
    @State private var sessionFacet: SessionFacet?
    @State private var selection: HookRecord.ID?

    enum EnforcementFacet: String, CaseIterable, Identifiable {
        case all
        case blocking
        case advisory

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: "All hooks"
            case .blocking: "Blocking"
            case .advisory: "Non-blocking"
            }
        }

        func matches(_ hook: HookRecord) -> Bool {
            switch self {
            case .all: true
            case .blocking: hook.isBlocking
            case .advisory: !hook.isBlocking
            }
        }
    }

    enum SessionFacet: String, CaseIterable, Identifiable {
        case enabled
        case disabled

        var id: String { rawValue }

        var label: String {
            switch self {
            case .enabled: "Enabled here"
            case .disabled: "Not enabled here"
            }
        }
    }

    var body: some View {
        let scoped = model.hooks.filter { enforcement.matches($0) }
        let visible = filtered(scoped)

        return WisentScreen(
            title: "Hooks",
            scope: session.map { "session \($0.sessionId.prefix(8))" },
            freshness: counted(model.hooks.count, "policy"),
            actions: [
                WisentAction(
                    "Reveal source",
                    symbol: "folder",
                    kind: .secondary,
                    isEnabled: selectedHook?.sourcePath != nil
                ) {
                    if let hook = selectedHook { model.revealSource(for: hook) }
                }
            ],
            scrolls: false,
            constrainsWidth: false
        ) {
            HStack(spacing: 0) {
                WisentFacetRail(
                    groups: facetGroups(scope: scoped),
                    footerTitle: "Selection",
                    footerDetail: "\(visible.count.formatted(.number)) of \(model.hooks.count.formatted(.number))"
                )
                centre(visible: visible)
                inspector
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .searchable(
            text: $query,
            placement: .toolbar,
            prompt: "Search hook id, category, event or description"
        )
    }

    // MARK: - Facets

    private var session: AgentSessionRecord? { model.selectedAgentSession }

    private func facetGroups(scope: [HookRecord]) -> [WisentFacetGroup] {
        var groups = [enforcementGroup]
        if let categories = categoryGroup(scope: scope) {
            groups.append(categories)
        }
        if let session {
            groups.append(sessionGroup(scope: scope, session: session))
        }
        return groups
    }

    private var enforcementGroup: WisentFacetGroup {
        let hooks = model.hooks
        let blocking = hooks.lazy.filter(\.isBlocking).count
        return WisentFacetGroup(
            "Enforcement",
            facets: EnforcementFacet.allCases.map { facet in
                let count = switch facet {
                case .all: hooks.count
                case .blocking: blocking
                case .advisory: hooks.count - blocking
                }
                return WisentFacet(
                    id: "enforcement.\(facet.rawValue)",
                    label: facet.label,
                    count: count,
                    tone: facet == .blocking && blocking > .zero ? .warning : .neutral,
                    isSelected: enforcement == facet
                ) {
                    enforcement = facet
                }
            }
        )
    }

    /// Counts are measured inside the current enforcement scope, so the number
    /// beside a category is the number of rows selecting it produces.
    private func categoryGroup(scope: [HookRecord]) -> WisentFacetGroup? {
        var counts: [String: Int] = [:]
        for hook in scope where !hook.category.isEmpty {
            counts[hook.category, default: .zero] += 1
        }
        guard !counts.isEmpty else { return nil }
        let ranked = counts
            .sorted { left, right in
                left.value == right.value ? left.key < right.key : left.value > right.value
            }
        return WisentFacetGroup(
            "Category",
            facets: ranked.map { category, count in
                WisentFacet(
                    id: "category.\(category)",
                    label: category,
                    count: count,
                    isSelected: categoryFacet == category
                ) {
                    categoryFacet = categoryFacet == category ? nil : category
                }
            }
        )
    }

    private func sessionGroup(
        scope: [HookRecord],
        session: AgentSessionRecord
    ) -> WisentFacetGroup {
        let enabled = scope.lazy.filter { session.isHookEnabled($0.id) }.count
        return WisentFacetGroup(
            "In this session",
            facets: SessionFacet.allCases.map { facet in
                let count = facet == .enabled ? enabled : scope.count - enabled
                return WisentFacet(
                    id: "session.\(facet.rawValue)",
                    label: facet.label,
                    count: count,
                    tone: facet == .disabled && count > .zero ? .warning : .neutral,
                    isSelected: sessionFacet == facet
                ) {
                    sessionFacet = sessionFacet == facet ? nil : facet
                }
            }
        )
    }

    private func filtered(_ scope: [HookRecord]) -> [HookRecord] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard categoryFacet != nil || sessionFacet != nil || !needle.isEmpty else {
            return scope
        }
        return scope.filter { hook in
            if let categoryFacet, hook.category != categoryFacet { return false }
            if let sessionFacet, let session {
                let isEnabled = session.isHookEnabled(hook.id)
                if sessionFacet == .enabled, !isEnabled { return false }
                if sessionFacet == .disabled, isEnabled { return false }
            }
            guard !needle.isEmpty else { return true }
            return hook.id.lowercased().contains(needle)
                || hook.category.lowercased().contains(needle)
                || hook.eventNames.lowercased().contains(needle)
                || (hook.description?.lowercased().contains(needle) ?? false)
        }
    }

    private func clearFilters() {
        enforcement = .all
        categoryFacet = nil
        sessionFacet = nil
        query = ""
    }

    // MARK: - Centre

    @ViewBuilder
    private func centre(visible: [HookRecord]) -> some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
            if let catalogError = model.catalogError, model.snapshot != nil {
                WisentErrorBanner(
                    title: "Catalog re-read failed",
                    detail: catalogError,
                    action: WisentAction("Retry", symbol: "arrow.clockwise", kind: .secondary) {
                        Task { await model.refresh() }
                    }
                )
            }
            WisentMutationBar(outcome: model.mutation) { model.clearMutation() }
            if model.snapshot == nil {
                if let catalogError = model.catalogError {
                    WisentAlertPanel(
                        tone: .danger,
                        title: "Catalog unavailable",
                        detail: catalogError,
                        command: TamaCommand.hooksValidate,
                        actions: [
                            WisentAction("Retry", symbol: "arrow.clockwise", kind: .primary) {
                                Task { await model.refresh() }
                            }
                        ]
                    )
                } else {
                    WisentLoadingPanel(
                        title: "Reading the approved hook catalog",
                        detail: "Hook identifiers, categories, events and blocking behaviour."
                    )
                }
                Spacer(minLength: 0)
            } else if model.hooks.isEmpty {
                WisentEmptyPanel(
                    title: "This build carries no hooks",
                    detail: "The sealed catalog declares no policies. Rebuild Tama against a tama release that does.",
                    symbol: "tray"
                )
                Spacer(minLength: 0)
            } else if visible.isEmpty {
                WisentEmptyPanel(
                    title: "No hook matches this selection",
                    detail: "The catalog holds \(counted(model.hooks.count, "policy")). The facets and the search term in force exclude every one of them.",
                    symbol: "line.3.horizontal.decrease.circle",
                    action: WisentAction("Clear filters", kind: .secondary) { clearFilters() }
                )
                Spacer(minLength: 0)
            } else {
                table(visible: visible)
            }
        }
        .padding(WisentDesign.Space.x5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The chip marks the minority. When most of the catalog blocks, the pill
    /// moves to the advisory rows, and the majority count stays in the rail.
    private var chipsBlocking: Bool {
        let hooks = model.hooks
        let blocking = hooks.lazy.filter(\.isBlocking).count
        return blocking * Int("2")! <= hooks.count
    }

    private func table(visible: [HookRecord]) -> some View {
        WisentTableFrame {
            Table(visible, selection: $selection) {
                TableColumn("HOOK") { hook in
                    Text(hook.id)
                        .font(WisentTypeScale.identifier())
                        .foregroundStyle(WisentDesign.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(hook.id)
                        .frame(height: WisentAppLayout.tableRowHeight, alignment: .leading)
                }
                .width(min: 130, ideal: 220)
                TableColumn("CATEGORY") { hook in
                    Text(hook.category)
                        .font(WisentTypeScale.body())
                        .foregroundStyle(WisentDesign.secondary)
                        .lineLimit(1)
                }
                .width(min: 70, ideal: 110)
                TableColumn("EVENTS") { hook in
                    Text(hook.events.count.formatted(.number))
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(WisentDesign.secondary)
                        .monospacedDigit()
                }
                .width(min: 44, ideal: 60)
                TableColumn("FLAG") { hook in
                    if hook.isBlocking == chipsBlocking {
                        WisentStatusChip(
                            text: hook.isBlocking ? "Blocking" : "Advisory",
                            tone: hook.isBlocking ? .warning : .neutral
                        )
                    }
                }
                .width(min: 40, ideal: 72)
            }
            .tableStyle(.inset)
            .font(WisentTypeScale.body())
        }
    }

    // MARK: - Inspector

    private var selectedHook: HookRecord? {
        guard let selection else { return nil }
        return model.hooks.first { $0.id == selection }
    }

    @ViewBuilder
    private var inspector: some View {
        if let hook = selectedHook {
            WisentInspector(
                eyebrow: hook.category,
                title: hook.id,
                badges: badges(hook)
            ) {
                if let description = hook.description {
                    prose("What it does", description)
                }
                if let why = hook.why {
                    prose("Why it exists", why)
                }
                if let sideEffects = hook.sideEffects {
                    prose("Side effects", sideEffects)
                }
                events(hook)
                WisentField(label: "Source", value: hook.sourcePath ?? "No archived source path")
                WisentField(label: "Command", value: hook.command)
                sessionControl(hook)
            }
        } else {
            WisentInspector(eyebrow: "Hook", title: "No hook selected") {
                Text("Choose a policy to read what it does, why it exists, which events it runs on, and whether the live session has it enabled.")
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func badges(_ hook: HookRecord) -> [(String, WisentTone)] {
        var badges: [(String, WisentTone)] = [
            (hook.status.capitalized, hook.status == "active" ? .success : .warning)
        ]
        if hook.isBlocking {
            badges.append(("Blocking", .warning))
        }
        return badges
    }

    private func prose(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
            Text(label.uppercased())
                .font(WisentTypeScale.eyebrow())
                .tracking(0.6)
                .foregroundStyle(WisentDesign.muted)
            Text(text)
                .font(WisentTypeScale.caption())
                .foregroundStyle(WisentDesign.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func events(_ hook: HookRecord) -> some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
            Text("EVENTS")
                .font(WisentTypeScale.eyebrow())
                .tracking(0.6)
                .foregroundStyle(WisentDesign.muted)
            ForEach(hook.events) { event in
                HStack(spacing: WisentDesign.Space.x2) {
                    Text(event.event)
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(WisentDesign.ink)
                        .lineLimit(1)
                    Spacer(minLength: WisentDesign.Space.x2)
                    if event.blocking {
                        WisentStatusChip(text: "Blocking", tone: .warning)
                    }
                    Text("\(event.timeout)s")
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(WisentDesign.muted)
                        .monospacedDigit()
                }
                .frame(height: WisentAppLayout.tableRowHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The one decision this screen owns: is this policy live in the session in
    /// front of the operator. Enabling restores policy, so it needs no dialog;
    /// the disabling direction does not exist per hook by design.
    @ViewBuilder
    private func sessionControl(_ hook: HookRecord) -> some View {
        if let session {
            Divider()
            let isEnabled = session.isHookEnabled(hook.id)
            WisentField(
                label: "In \(session.agentDisplayName) session",
                value: isEnabled ? "Enabled" : "Not enabled",
                tone: isEnabled ? .success : .warning
            )
            if !isEnabled {
                WisentActionButton(
                    action: WisentAction(
                        "Enable in this session",
                        symbol: "checkmark.shield",
                        kind: .primary,
                        isEnabled: !model.isPolicyMutationInProgress
                    ) {
                        model.enableHook(hook.id, in: session)
                    }
                )
                Text(session.globallyDisabled
                    ? "All hooks are globally disabled. Enabling writes an allowlist entry for this agent session only."
                    : "The override is stored for this agent session and restored when the same session is resumed.")
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
