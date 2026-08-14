import SwiftUI
import WisentDesignSystem

struct JustificationsView: View {
    let collections: [JustificationCollection]

    @State private var selectedCollectionID = ""
    @State private var selectedEntryID: JustificationEntry.ID?
    @State private var searchText = ""
    @State private var filter: JustificationFilter = .all

    private var selectedCollection: JustificationCollection? {
        collections.first(where: { $0.id == selectedCollectionID }) ?? collections.first
    }

    private var filteredEntries: [JustificationEntry] {
        guard let collection = selectedCollection else { return [] }
        return collection.entries.filter { entry in
            let matchesFilter = switch filter {
            case .all: true
            case .valid: isValid(entry, requirement: collection.requirement)
            case .issues: !isValid(entry, requirement: collection.requirement)
            }
            guard matchesFilter else { return false }
            guard !searchText.isEmpty else { return true }
            return entry.registryKey.localizedStandardContains(searchText)
                || entry.justification.localizedStandardContains(searchText)
                || (entry.directUserQuote?.localizedStandardContains(searchText) ?? false)
        }
    }

    private var selectedEntry: JustificationEntry? {
        guard let selectedEntryID else { return filteredEntries.first }
        return selectedCollection?.entries.first(where: { $0.id == selectedEntryID })
    }

    var body: some View {
        ZStack {
            WisentCanvasBackground()
            if collections.isEmpty {
                WisentEmptyState(
                    title: "No justification hooks",
                    detail: "The catalog has no requires_justification hook definitions.",
                    symbol: "text.badge.checkmark"
                )
            } else {
                VStack(spacing: 0) {
                    registryPicker
                    Divider()
                    if let collection = selectedCollection, let loadError = collection.loadError {
                        WisentEmptyState(title: "Registry unavailable", detail: loadError, symbol: "exclamationmark.triangle")
                    } else {
                        HSplitView {
                            entryList
                                .frame(minWidth: TamaLayout.justificationListMinimumWidth, idealWidth: TamaLayout.justificationListIdealWidth)
                            if let collection = selectedCollection, let entry = selectedEntry {
                                entryDetail(entry, requirement: collection.requirement)
                                    .frame(maxWidth: .infinity)
                            } else {
                                WisentEmptyState(
                                    title: "Select a justification",
                                    detail: "Choose a registry record to inspect its contract and evidence.",
                                    symbol: "text.badge.checkmark"
                                )
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { selectInitialCollection() }
        .onChange(of: selectedCollectionID) { selectedEntryID = filteredEntries.first?.id }
    }

    private var registryPicker: some View {
        HStack(spacing: WisentDesign.Space.x3) {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                Text("JUSTIFICATION REGISTRY")
                    .font(WisentTypography.monoSemibold(10))
                    .tracking(0.6)
                    .foregroundStyle(WisentDesign.muted)
                Picker("Registry", selection: $selectedCollectionID) {
                    ForEach(collections) { collection in
                        Text(collection.requirement.title).tag(collection.id)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: TamaLayout.registryPickerMaximumWidth)
            }
            if let collection = selectedCollection {
                Text(collection.requirement.registryPath)
                    .font(WisentTypography.mono(10))
                    .foregroundStyle(WisentDesign.secondary)
                    .textSelection(.enabled)
                Spacer()
                WisentBadge("\(collection.entries.count.formatted()) entries", symbol: "text.badge.checkmark", tone: .info)
            }
        }
        .padding(WisentDesign.Space.x4)
        .background(WisentDesign.surface)
    }

    private var entryList: some View {
        VStack(spacing: 0) {
            Picker("Status", selection: $filter) {
                ForEach(JustificationFilter.allCases) { item in Text(item.rawValue).tag(item) }
            }
            .pickerStyle(.segmented)
            .padding(WisentDesign.Space.x4)
            Divider()
            List(filteredEntries, selection: $selectedEntryID) { entry in
                VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                    Text(URL(fileURLWithPath: entry.registryKey).lastPathComponent)
                        .font(WisentTypography.bodyMedium(13))
                        .foregroundStyle(WisentDesign.ink)
                    Text(entry.registryKey)
                        .font(WisentTypography.mono(10))
                        .foregroundStyle(WisentDesign.secondary)
                        .lineLimit(2)
                    if let collection = selectedCollection {
                        JustificationStatusBadge(entry: entry, requirement: collection.requirement)
                    }
                }
                .padding(.vertical, WisentDesign.Space.x1)
                .tag(entry.id)
            }
            .searchable(text: $searchText, prompt: "Path or justification")
            .overlay {
                if filteredEntries.isEmpty {
                    WisentEmptyState(
                        title: "No matching justifications",
                        detail: searchText.isEmpty ? "Adjust the status filter to show registry records." : "No path or justification matches “\(searchText)”.",
                        symbol: "line.3.horizontal.decrease.circle"
                    )
                }
            }
        }
        .background(WisentDesign.canvasMuted)
    }

    private func entryDetail(_ entry: JustificationEntry, requirement: JustificationRequirement) -> some View {
        TamaPage {
            HStack(alignment: .top, spacing: WisentDesign.Space.x4) {
                WisentPageHeader(
                    eyebrow: requirement.title,
                    title: URL(fileURLWithPath: entry.registryKey).lastPathComponent,
                    detail: "Recorded evidence for a policy exception or explicitly justified operation.",
                    symbol: "text.badge.checkmark",
                    tone: isValid(entry, requirement: requirement) ? .success : .warning
                )
                Spacer()
                JustificationStatusBadge(entry: entry, requirement: requirement)
            }

            TamaPanelSection("Contract", detail: "Requirements enforced by this registry") {
                LabeledContent("Hook type", value: "requires_justification")
                Divider()
                LabeledContent("Kind", value: requirement.kind)
                Divider()
                LabeledContent("Field", value: requirement.field)
                if let directUserQuoteField = requirement.directUserQuoteField {
                    Divider()
                    LabeledContent("Direct user quote field", value: directUserQuoteField)
                }
                Divider()
                LabeledContent("Words") {
                    Text("\(entry.wordCount) / \(requirement.minimumWords) minimum")
                        .font(WisentTypography.monoMedium(11))
                }
                Divider()
                LabeledContent("Target file") {
                    WisentBadge(entry.targetExists ? "Present" : "Missing", symbol: entry.targetExists ? "checkmark.circle.fill" : "doc.badge.ellipsis", tone: entry.targetExists ? .success : .danger)
                }
                if let expiresAt = entry.expiresAt {
                    Divider()
                    LabeledContent("Expires") {
                        Text(expiresAt, format: .dateTime.year().month().day().hour().minute())
                            .foregroundStyle(entry.isExpired ? WisentDesign.danger : WisentDesign.ink)
                    }
                }
            }

            TamaPanelSection("Path") {
                Text(entry.registryKey)
                    .font(WisentTypography.mono(12))
                    .textSelection(.enabled)
            }

            TamaPanelSection("Justification") {
                Text(entry.justification.isEmpty ? "No value recorded for \(requirement.field)." : entry.justification)
                    .font(WisentTypography.body(13))
                    .foregroundStyle(WisentDesign.secondary)
                    .textSelection(.enabled)
            }

            if let quoteField = requirement.directUserQuoteField {
                TamaPanelSection("Direct user request") {
                    Text(recordedUserQuote(entry) ?? "No value recorded for \(quoteField).")
                        .font(WisentTypography.body(13))
                        .foregroundStyle(WisentDesign.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func selectInitialCollection() {
        if selectedCollectionID.isEmpty { selectedCollectionID = collections.first?.id ?? "" }
        if selectedEntryID == nil { selectedEntryID = filteredEntries.first?.id }
    }

    private func isValid(_ entry: JustificationEntry, requirement: JustificationRequirement) -> Bool {
        entry.targetExists
            && !entry.isExpired
            && entry.wordCount >= requirement.minimumWords
            && hasRequiredDirectUserQuote(entry, requirement: requirement)
    }
}

private enum JustificationFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case valid = "Valid"
    case issues = "Issues"

    var id: Self { self }
}

private func recordedUserQuote(_ entry: JustificationEntry) -> String? {
    guard let quote = entry.directUserQuote, quote.contains(where: { !$0.isWhitespace }) else { return nil }
    return quote
}

private func hasRequiredDirectUserQuote(_ entry: JustificationEntry, requirement: JustificationRequirement) -> Bool {
    guard requirement.directUserQuoteField != nil else { return true }
    guard let quote = recordedUserQuote(entry) else { return false }
    return entry.justification.contains(quote)
}

private struct JustificationStatusBadge: View {
    let entry: JustificationEntry
    let requirement: JustificationRequirement

    private var presentation: (text: String, symbol: String, tone: WisentTone) {
        if !entry.targetExists { return ("Missing file", "doc.badge.ellipsis", .danger) }
        if entry.isExpired { return ("Expired", "calendar.badge.exclamationmark", .danger) }
        if requirement.directUserQuoteField != nil {
            guard let quote = recordedUserQuote(entry) else { return ("Missing user quote", "quote.bubble.fill", .danger) }
            if !entry.justification.contains(quote) { return ("Quote not embedded", "quote.bubble.fill", .danger) }
        }
        if entry.wordCount < requirement.minimumWords { return ("Too short", "text.badge.exclamationmark", .warning) }
        return ("Valid", "checkmark.seal.fill", .success)
    }

    var body: some View {
        WisentBadge(presentation.text, symbol: presentation.symbol, tone: presentation.tone)
            .accessibilityLabel("Justification status: \(presentation.text)")
    }
}
