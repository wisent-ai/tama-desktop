import SwiftUI
import WisentDesignSystem

/// Which runtime carries which hook, as the registry declares it.
///
/// `tama provider coverage` existed with no surface at all, so the question
/// "is Codex actually covered on this machine" could only be answered in a
/// terminal. The screen is explicit that these are declared mappings and not
/// live execution evidence, because the command says so in every row it
/// returns.
struct CoverageView: View {
    @ObservedObject var inspection: InspectionModel

    @State private var providerFacet: String?
    @State private var selection: ProviderCoverageMapping.ID?

    var body: some View {
        let visible = filteredMappings

        return WisentScreen(
            title: "Coverage",
            scope: providerFacet,
            freshness: freshness,
            actions: [
                WisentAction(
                    "Re-read coverage",
                    symbol: "arrow.clockwise",
                    kind: .secondary,
                    isEnabled: !inspection.isReadingCoverage
                ) {
                    Task { await inspection.loadCoverage(force: true) }
                }
            ],
            scrolls: false,
            constrainsWidth: false
        ) {
            HStack(spacing: 0) {
                WisentFacetRail(groups: facetGroups)
                centre(visible: visible)
                inspector
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task { await inspection.loadCoverage() }
    }

    private var freshness: String {
        if inspection.isReadingCoverage { return "reading now" }
        guard let readAt = inspection.coverageReadAt else { return "not read yet" }
        return "read \(readAt.formatted(date: .omitted, time: .standard))"
    }

    // MARK: - Facets

    private var selectedProvider: ProviderCoverage? {
        guard let providerFacet else { return nil }
        return inspection.coverage.first { $0.provider == providerFacet }
    }

    private var facetGroups: [WisentFacetGroup] {
        guard !inspection.coverage.isEmpty else { return [] }
        return [
            WisentFacetGroup(
                "Provider",
                facets: [
                    WisentFacet(
                        id: "provider.all",
                        label: "Every provider",
                        count: inspection.coverage.reduce(.zero) { $0 + $1.mappingCount },
                        isSelected: providerFacet == nil
                    ) {
                        providerFacet = nil
                    }
                ] + inspection.coverage.map { coverage in
                    WisentFacet(
                        id: "provider.\(coverage.provider)",
                        label: coverage.provider,
                        count: coverage.mappingCount,
                        tone: coverage.isUncovered ? .warning : .neutral,
                        isSelected: providerFacet == coverage.provider
                    ) {
                        providerFacet = providerFacet == coverage.provider ? nil : coverage.provider
                    }
                }
            )
        ]
    }

    private var filteredMappings: [ProviderCoverageMapping] {
        guard let selectedProvider else {
            return inspection.coverage.flatMap(\.mappings)
        }
        return selectedProvider.mappings
    }

    // MARK: - Centre

    @ViewBuilder
    private func centre(visible: [ProviderCoverageMapping]) -> some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
            if let coverageError = inspection.coverageError {
                WisentAlertPanel(
                    tone: .danger,
                    title: "Coverage could not be read",
                    detail: coverageError,
                                        actions: [
                        WisentAction("Retry", symbol: "arrow.clockwise", kind: .primary) {
                            Task { await inspection.loadCoverage(force: true) }
                        }
                    ]
                )
            }
            if !inspection.coverage.isEmpty { counters }
            if inspection.coverage.isEmpty {
                if inspection.isReadingCoverage {
                    WisentLoadingPanel(
                        title: "Reading provider coverage",
                        detail: "Checking covered policies and events."
                    )
                } else if inspection.coverageError == nil {
                    WisentEmptyPanel(
                        title: "No provider coverage",
                        detail: "No providers are covered in this release.",
                        symbol: "point.3.connected.trianglepath.dotted"
                    )
                }
                Spacer(minLength: 0)
            } else if visible.isEmpty {
                WisentEmptyPanel(
                    title: "No coverage for \(providerFacet ?? "this provider")",
                    detail: selectedProvider?.note ?? "This provider has no covered events.",
                    symbol: "line.3.horizontal.decrease.circle",
                    action: WisentAction("Show every provider", kind: .secondary) {
                        providerFacet = nil
                    }
                )
                Spacer(minLength: 0)
            } else {
                table(visible: visible)
            }
        }
        .padding(WisentDesign.Space.x5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var counters: some View {
        let coverage = inspection.coverage
        let uncovered = coverage.lazy.filter(\.isUncovered).count
        return WisentCounterRow(counters: [
            WisentCounterRow.Counter(
                "Providers",
                value: coverage.count.formatted(.number),
                detail: "Declared in this release"
            ),
            WisentCounterRow.Counter(
                "Assignments",
                value: coverage.reduce(.zero) { $0 + $1.mappingCount }.formatted(.number),
                detail: "Covered event pairs"
            ),
            WisentCounterRow.Counter(
                "Policies covered",
                value: Set(coverage.flatMap { $0.mappings.map(\.hookId) }).count.formatted(.number),
                detail: "Distinct covered policies"
            ),
            WisentCounterRow.Counter(
                "Without coverage",
                value: uncovered.formatted(.number),
                detail: "Providers without coverage",
                tone: uncovered == .zero ? .neutral : .warning
            )
        ])
    }

    private func table(visible: [ProviderCoverageMapping]) -> some View {
        WisentTableFrame {
            Table(visible, selection: $selection) {
                TableColumn("POLICY") { mapping in
                    Text(mapping.hookId)
                        .font(WisentTypeScale.identifier())
                        .foregroundStyle(WisentDesign.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(mapping.hookId)
                        .frame(height: WisentAppLayout.tableRowHeight, alignment: .leading)
                }
                .width(min: 120, ideal: 190)
                TableColumn("EVENT") { mapping in
                    Text(mapping.event)
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(WisentDesign.secondary)
                        .lineLimit(1)
                }
                .width(min: 80, ideal: 130)
                TableColumn("TRIGGER") { mapping in
                    Text(mapping.runtimeEvent)
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(WisentDesign.secondary)
                        .lineLimit(1)
                }
                .width(min: 80, ideal: 130)
                TableColumn("PROVIDER") { mapping in
                    Text(mapping.provider)
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(WisentDesign.muted)
                        .lineLimit(1)
                }
                .width(min: 60, ideal: 90)
            }
            .tableStyle(.inset)
            // A click on this table already means "select this mapping" and a
            // drag means "extend that selection", so selectable cell text would
            // compete with both. Opting out restores exactly the behaviour the
            // index had before the window turned selection on.
            .textSelection(.disabled)
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        if let coverage = selectedProvider ?? providerOfSelectedRow {
            WisentInspector(
                eyebrow: "Provider",
                title: coverage.provider,
                badges: badges(coverage)
            ) {
                WisentField(label: "Declared mappings", value: coverage.mappingCount.formatted(.number))
                WisentField(label: "Policies", value: coverage.hookCount.formatted(.number))
                WisentField(label: "Events", value: coverage.eventCount.formatted(.number))
                WisentField(
                    label: "Live coverage required",
                    value: coverage.requiredLiveCoverage.map { $0 ? "yes" : "no" }
                        ?? "not declared"
                )
                Divider()
                Text(coverage.evidence)
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = coverage.note {
                    Text(note)
                        .font(WisentTypeScale.caption())
                        .foregroundStyle(WisentDesign.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            WisentInspector(eyebrow: "Coverage", title: "No provider selected") {
                Text("Select a provider to view its coverage.")
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var providerOfSelectedRow: ProviderCoverage? {
        guard let selection else { return nil }
        return inspection.coverage.first { coverage in
            coverage.mappings.contains { $0.id == selection }
        }
    }

    private func badges(_ coverage: ProviderCoverage) -> [(String, WisentTone)] {
        var badges: [(String, WisentTone)] = [(coverage.coverageKind, .brand)]
        if coverage.isUncovered {
            badges.append(("No mappings", .warning))
        }
        return badges
    }
}
