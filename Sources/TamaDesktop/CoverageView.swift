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
                WisentFacetRail(
                    groups: facetGroups,
                    footerTitle: "Evidence",
                    footerDetail: "Registry-declared mappings, not live execution"
                )
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
                    command: TamaCommand.providerCoverage,
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
                        title: "Reading declared provider coverage",
                        detail: "tama provider coverage maps every registry event onto the runtimes that claim it."
                    )
                } else if inspection.coverageError == nil {
                    WisentEmptyPanel(
                        title: "The registry declares no coverage",
                        detail: "No runtime in this release claims any catalogued event.",
                        symbol: "point.3.connected.trianglepath.dotted"
                    )
                }
                Spacer(minLength: 0)
            } else if visible.isEmpty {
                WisentEmptyPanel(
                    title: "\(providerFacet ?? "This provider") maps no hook",
                    detail: selectedProvider?.note
                        ?? "The registry lists the provider and declares no event mapping for it, so nothing runs through it.",
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
                "Mappings",
                value: coverage.reduce(.zero) { $0 + $1.mappingCount }.formatted(.number),
                detail: "Event to runtime pairs"
            ),
            WisentCounterRow.Counter(
                "Hooks covered",
                value: Set(coverage.flatMap { $0.mappings.map(\.hookId) }).count.formatted(.number),
                detail: "Distinct policies reachable"
            ),
            WisentCounterRow.Counter(
                "Without mappings",
                value: uncovered.formatted(.number),
                detail: "Providers nothing runs through",
                tone: uncovered == .zero ? .neutral : .warning
            )
        ])
    }

    private func table(visible: [ProviderCoverageMapping]) -> some View {
        WisentTableFrame {
            Table(visible, selection: $selection) {
                TableColumn("HOOK") { mapping in
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
                TableColumn("RUNTIME EVENT") { mapping in
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
                WisentField(label: "Hooks", value: coverage.hookCount.formatted(.number))
                WisentField(label: "Events", value: coverage.eventCount.formatted(.number))
                WisentField(
                    label: "Adapter path",
                    value: coverage.adapterPath ?? "No adapter declared"
                )
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
                Text("Choose a provider to read its adapter path, whether the release demands live coverage evidence for it, and what the registry says its coverage is based on.")
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                WisentCapabilityList(
                    title: "This screen can",
                    items: [
                        "List declared event to runtime mappings",
                        "Name the adapter file each provider reads",
                    ],
                    isAvailable: true
                )
                WisentCapabilityList(
                    title: "It never can",
                    items: [
                        "Prove a hook ran in that runtime",
                        "Edit an adapter configuration",
                    ],
                    isAvailable: false
                )
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
