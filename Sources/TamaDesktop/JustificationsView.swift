import SwiftUI
import WisentDesignSystem

/// The register of recorded exceptions, and whether each one still holds.
///
/// Three zones: registries and verdicts on the left, the records in the middle,
/// the evidence on the right. Nothing here is red: the application is reading
/// these files successfully, and an entry whose quote was never filled in is
/// incomplete evidence, not an outage. Red is kept for a registry Tama cannot
/// read at all.
///
/// The screen also records a justification, because the CLI can and the two
/// surfaces carry the same capability. The centre pane lives in
/// `Justifications/Records.swift` and the evidence pane in
/// `Justifications/Inspector.swift`, so this file stays inside the length limit
/// the operator's own gate enforces.
struct JustificationsView: View {
    let collections: [JustificationCollection]
    let isRefreshing: Bool
    /// Called with the path that was just recorded, for a caller that wants to
    /// re-read the registries immediately.
    var onRecorded: (String) -> Void = { _ in }

    @State private var registryID: JustificationCollection.ID?
    @State var verdictFacet: VerdictFacet = .all
    @State var selection: JustificationEntry.ID?
    @State var query = ""
    @State private var isRecordingSheetOpen = false
    @State private var lastRecorded: String?

    enum VerdictFacet: String, CaseIterable, Identifiable {
        case all
        case valid
        case issues

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: "Every record"
            case .valid: "Holds"
            case .issues: "Incomplete"
            }
        }
    }

    var body: some View {
        let collection = selectedCollection
        let entries = collection?.entries ?? []
        let visible = filtered(entries, requirement: collection?.requirement)

        return WisentScreen(
            title: "Justifications",
            scope: collection?.requirement.title,
            freshness: counted(entries.count, "record"),
            scrolls: false,
            constrainsWidth: false
        ) {
            HStack(spacing: .zero) {
                WisentFacetRail(
                    groups: facetGroups(collection: collection, entries: entries)
                )
                centre(collection: collection, entries: entries, visible: visible)
                inspector(collection: collection)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search target or justification")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isRecordingSheetOpen = true
                } label: {
                    Label("Record justification", systemImage: "square.and.pencil")
                }
                .help("Record a justification for a new file or a new test")
            }
        }
        .sheet(isPresented: $isRecordingSheetOpen) {
            JustificationRecorder(collections: collections) { path in
                lastRecorded = path
                onRecorded(path)
            }
        }
        .onAppear {
            if registryID == nil { registryID = collections.first?.id }
        }
    }

    // MARK: - Facets

    var selectedCollection: JustificationCollection? {
        collections.first { $0.id == registryID } ?? collections.first
    }

    private func facetGroups(
        collection: JustificationCollection?,
        entries: [JustificationEntry]
    ) -> [WisentFacetGroup] {
        var groups: [WisentFacetGroup] = []
        if collections.count > Int("1")! {
            groups.append(
                WisentFacetGroup(
                    "Policy",
                    facets: collections.map { candidate in
                        WisentFacet(
                            id: "registry.\(candidate.id)",
                            label: candidate.requirement.title,
                            count: candidate.entries.count,
                            tone: candidate.loadError == nil ? .neutral : .danger,
                            isSelected: candidate.id == collection?.id
                        ) {
                            registryID = candidate.id
                            selection = nil
                        }
                    }
                )
            )
        }
        if let requirement = collection?.requirement {
            let holding = entries.lazy.filter { verdict($0, requirement: requirement).holds }.count
            groups.append(
                WisentFacetGroup(
                    "Verdict",
                    facets: VerdictFacet.allCases.map { facet in
                        let count = switch facet {
                        case .all: entries.count
                        case .valid: holding
                        case .issues: entries.count - holding
                        }
                        return WisentFacet(
                            id: "verdict.\(facet.rawValue)",
                            label: facet.label,
                            count: count,
                            tone: facet == .issues && count > .zero ? .warning : .neutral,
                            isSelected: verdictFacet == facet
                        ) {
                            verdictFacet = facet
                        }
                    }
                )
            )
        }
        return groups
    }

    private func filtered(
        _ entries: [JustificationEntry],
        requirement: JustificationRequirement?
    ) -> [JustificationEntry] {
        guard let requirement else { return [] }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.filter { entry in
            let holds = verdict(entry, requirement: requirement).holds
            switch verdictFacet {
            case .all: break
            case .valid where !holds: return false
            case .issues where holds: return false
            default: break
            }
            guard !needle.isEmpty else { return true }
            return entry.registryKey.lowercased().contains(needle)
                || entry.justification.lowercased().contains(needle)
                || (entry.directUserQuote?.lowercased().contains(needle) ?? false)
        }
    }

    // MARK: - Centre

    @ViewBuilder
    private func centre(
        collection: JustificationCollection?,
        entries: [JustificationEntry],
        visible: [JustificationEntry]
    ) -> some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
            if let collection, collection.loadError != nil {
                WisentAlertPanel(
                    tone: .danger,
                    title: "Justifications unavailable",
                    detail: "Reasons could not be loaded."
                )
            }
            if let lastRecorded {
                WisentAlertPanel(
                    tone: .info,
                    title: "Recorded",
                    detail: "\(lastRecorded) — the table shows it after the next read of the registries."
                )
            }
            if let collection { contract(collection) }
            content(collection: collection, entries: entries, visible: visible)
        }
        .padding(WisentDesign.Space.x5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
