import SwiftUI
import WisentDesignSystem

/// The register of recorded exceptions, and whether each one still holds.
///
/// Three zones: registries and verdicts on the left, the records in the middle,
/// the evidence on the right. Nothing here is red: the application is reading
/// these files successfully, and an entry whose quote was never filled in is
/// incomplete evidence, not an outage. Red is kept for a registry Tama cannot
/// read at all.
struct JustificationsView: View {
    let collections: [JustificationCollection]
    let isRefreshing: Bool

    @State private var registryID: JustificationCollection.ID?
    @State private var verdictFacet: VerdictFacet = .all
    @State private var selection: JustificationEntry.ID?
    @State private var query = ""

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
            scope: collection?.requirement.kind,
            freshness: counted(entries.count, "record"),
            scrolls: false,
            constrainsWidth: false
        ) {
            HStack(spacing: 0) {
                WisentFacetRail(
                    groups: facetGroups(collection: collection, entries: entries),
                    footerTitle: "Registry",
                    footerDetail: collection?.requirement.registryPath ?? "No registry declared"
                )
                centre(collection: collection, entries: entries, visible: visible)
                inspector(collection: collection)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search path or justification")
        .onAppear {
            if registryID == nil { registryID = collections.first?.id }
        }
    }

    // MARK: - Facets

    private var selectedCollection: JustificationCollection? {
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
                    "Registry",
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
            if let collection, let loadError = collection.loadError {
                WisentAlertPanel(
                    tone: .danger,
                    title: "Registry unreadable",
                    detail: loadError,
                    command: "python3 -m json.tool \(collection.requirement.registryPath)"
                )
            }
            if let collection { contract(collection) }
            content(collection: collection, entries: entries, visible: visible)
        }
        .padding(WisentDesign.Space.x5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func contract(_ collection: JustificationCollection) -> some View {
        let requirement = collection.requirement
        let holding = collection.entries.lazy
            .filter { verdict($0, requirement: requirement).holds }
            .count
        return WisentCounterRow(counters: [
            WisentCounterRow.Counter(
                "Records",
                value: collection.entries.count.formatted(.number),
                detail: "Entries in this registry"
            ),
            WisentCounterRow.Counter(
                "Holding",
                value: holding.formatted(.number),
                detail: "Satisfy the contract",
                tone: .success
            ),
            WisentCounterRow.Counter(
                "Incomplete",
                value: (collection.entries.count - holding).formatted(.number),
                detail: "Missing evidence or expired",
                tone: holding == collection.entries.count ? .neutral : .warning
            ),
            WisentCounterRow.Counter(
                "Minimum words",
                value: requirement.minimumWords.formatted(.number),
                detail: "Required in \(requirement.field)"
            )
        ])
    }

    @ViewBuilder
    private func content(
        collection: JustificationCollection?,
        entries: [JustificationEntry],
        visible: [JustificationEntry]
    ) -> some View {
        if collections.isEmpty {
            if isRefreshing {
                WisentLoadingPanel(
                    title: "Reading the justification registries",
                    detail: "Each requires_justification hook declares one registry path under your home directory."
                )
            } else {
                WisentEmptyPanel(
                    title: "This build declares no justification hooks",
                    detail: "No catalogued policy has type requires_justification, so there is no registry to read.",
                    symbol: "text.badge.checkmark"
                )
            }
            Spacer(minLength: 0)
        } else if entries.isEmpty {
            WisentEmptyPanel(
                title: "This registry holds no records",
                detail: collection?.loadError == nil
                    ? "The registry exists and records no exception yet. Entries appear as hooks write them."
                    : "Tama could not read the registry, so it can list nothing from it.",
                symbol: "tray"
            )
            Spacer(minLength: 0)
        } else if visible.isEmpty {
            WisentEmptyPanel(
                title: "No record matches this selection",
                detail: "The registry holds \(counted(entries.count, "record")). The verdict facet and the search term in force exclude every one of them.",
                symbol: "line.3.horizontal.decrease.circle",
                action: WisentAction("Clear filters", kind: .secondary) {
                    verdictFacet = .all
                    query = ""
                }
            )
            Spacer(minLength: 0)
        } else if let requirement = collection?.requirement {
            table(visible: visible, entries: entries, requirement: requirement)
        }
    }

    /// The chip marks the minority verdict. A registry where every record holds
    /// gets no chips at all, and the count stays in the rail.
    private func table(
        visible: [JustificationEntry],
        entries: [JustificationEntry],
        requirement: JustificationRequirement
    ) -> some View {
        let holding = entries.lazy.filter { verdict($0, requirement: requirement).holds }.count
        let chipsOnHolding = holding * Int("2")! <= entries.count
        return WisentTableFrame {
            Table(visible, selection: $selection) {
                TableColumn("TARGET") { entry in
                    Text(entry.registryKey)
                        .font(WisentTypeScale.identifier())
                        .foregroundStyle(WisentDesign.ink)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .help(entry.registryKey)
                        .frame(height: WisentAppLayout.tableRowHeight, alignment: .leading)
                }
                .width(min: 130, ideal: 220)
                TableColumn("WORDS") { entry in
                    Text("\(entry.wordCount.formatted(.number))/\(requirement.minimumWords.formatted(.number))")
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(
                            entry.wordCount >= requirement.minimumWords
                                ? WisentDesign.secondary
                                : WisentDesign.warning
                        )
                        .monospacedDigit()
                }
                .width(min: 54, ideal: 70)
                TableColumn("EXPIRES") { entry in
                    Text(entry.expiresAt.map { $0.formatted(date: .numeric, time: .omitted) } ?? "—")
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(entry.isExpired ? WisentDesign.warning : WisentDesign.secondary)
                        .monospacedDigit()
                }
                .width(min: 66, ideal: 86)
                TableColumn("VERDICT") { entry in
                    let verdict = verdict(entry, requirement: requirement)
                    if verdict.holds == chipsOnHolding {
                        WisentStatusChip(text: verdict.label, tone: verdict.tone)
                    }
                }
                .width(min: 60, ideal: 120)
            }
            .tableStyle(.inset)
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private func inspector(collection: JustificationCollection?) -> some View {
        if let collection,
           let entry = collection.entries.first(where: { $0.id == selection }) {
            let requirement = collection.requirement
            let verdict = verdict(entry, requirement: requirement)
            WisentInspector(
                eyebrow: requirement.title,
                title: URL(fileURLWithPath: entry.registryKey).lastPathComponent,
                badges: [(verdict.label, verdict.tone)]
            ) {
                WisentField(label: "Target", value: entry.registryKey)
                WisentField(
                    label: "Target file",
                    value: entry.targetExists ? "Present on disk" : "Missing on disk",
                    tone: entry.targetExists ? .neutral : .warning
                )
                WisentField(label: "Kind", value: requirement.kind)
                WisentField(label: "Field", value: requirement.field)
                if let expiresAt = entry.expiresAt {
                    WisentField(
                        label: entry.isExpired ? "Expired" : "Expires",
                        value: expiresAt.formatted(date: .abbreviated, time: .shortened),
                        tone: entry.isExpired ? .warning : .neutral
                    )
                }
                Divider()
                prose(
                    requirement.field.uppercased(),
                    entry.justification.isEmpty
                        ? "No value recorded for \(requirement.field)."
                        : entry.justification
                )
                if let quoteField = requirement.directUserQuoteField {
                    prose(
                        "DIRECT USER REQUEST",
                        recordedQuote(entry) ?? "No value recorded for \(quoteField)."
                    )
                }
            }
        } else {
            WisentInspector(
                eyebrow: "Justification",
                title: collections.isEmpty ? "No registry declared" : "No record selected"
            ) {
                Text("Choose a record to read the justification exactly as it was written, and the direct user request it must quote.")
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                WisentCapabilityList(
                    title: "This screen can",
                    items: [
                        "Read the registries declared by requires_justification hooks",
                        "Report which records satisfy their contract",
                    ],
                    isAvailable: true
                )
                WisentCapabilityList(
                    title: "It never can",
                    items: [
                        "Write, extend or delete a justification",
                        "Read the target file's contents",
                    ],
                    isAvailable: false
                )
            }
        }
    }

    private func prose(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
            Text(label)
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

    // MARK: - Verdicts

    struct Verdict {
        let label: String
        let tone: WisentTone
        let holds: Bool
    }

    /// A record that is merely incomplete is amber, never red: the operator has
    /// evidence to finish, not an outage to fix.
    private func verdict(
        _ entry: JustificationEntry,
        requirement: JustificationRequirement
    ) -> Verdict {
        if !entry.targetExists {
            return Verdict(label: "Target missing", tone: .warning, holds: false)
        }
        if entry.isExpired {
            return Verdict(label: "Expired", tone: .warning, holds: false)
        }
        if requirement.directUserQuoteField != nil {
            guard let quote = recordedQuote(entry) else {
                return Verdict(label: "No user quote", tone: .neutral, holds: false)
            }
            if !entry.justification.contains(quote) {
                return Verdict(label: "Quote not embedded", tone: .warning, holds: false)
            }
        }
        if entry.wordCount < requirement.minimumWords {
            return Verdict(label: "Too short", tone: .warning, holds: false)
        }
        return Verdict(label: "Holds", tone: .success, holds: true)
    }

    private func recordedQuote(_ entry: JustificationEntry) -> String? {
        guard let quote = entry.directUserQuote, quote.contains(where: { !$0.isWhitespace }) else {
            return nil
        }
        return quote
    }
}
