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
    @StateObject var machineSelection = EnforcementSelectionModel()

    @State var query = ""
    @State var enforcement: EnforcementFacet = .all
    @State var categoryFacet: String?
    @State var sessionFacet: SessionFacet?
    @State var selection: HookRecord.ID?

    enum EnforcementFacet: String, CaseIterable, Identifiable {
        case all
        case blocking
        case advisory

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: "All policies"
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
        .task { await machineSelection.refresh() }
        .searchable(
            text: $query,
            placement: .toolbar,
            prompt: "Search policy, category, event or description"
        )
    }

    // MARK: - Facets

    var session: AgentSessionRecord? { model.selectedAgentSession }

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

    func clearFilters() {
        enforcement = .all
        categoryFacet = nil
        sessionFacet = nil
        query = ""
    }

}
