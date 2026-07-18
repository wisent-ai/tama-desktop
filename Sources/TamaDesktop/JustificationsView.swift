import SwiftUI

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
            case .all:
                true
            case .valid:
                isValid(entry, requirement: collection.requirement)
            case .issues:
                !isValid(entry, requirement: collection.requirement)
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
        if collections.isEmpty {
            ContentUnavailableView(
                "No justification hooks",
                systemImage: "text.badge.checkmark",
                description: Text("The catalog has no requires_justification hook definitions.")
            )
        } else {
            VStack(spacing: 0) {
                registryPicker
                Divider()
                if let collection = selectedCollection, let loadError = collection.loadError {
                    ContentUnavailableView(
                        "Registry unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                } else {
                    HSplitView {
                        entryList
                            .frame(minWidth: 360, idealWidth: 460)
                        if let collection = selectedCollection, let entry = selectedEntry {
                            entryDetail(entry, requirement: collection.requirement)
                                .frame(maxWidth: .infinity)
                        } else {
                            ContentUnavailableView(
                                "Select a justification",
                                systemImage: "text.badge.checkmark"
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .onAppear {
                selectInitialCollection()
            }
            .onChange(of: selectedCollectionID) {
                selectedEntryID = filteredEntries.first?.id
            }
        }
    }

    private var registryPicker: some View {
        HStack(spacing: 12) {
            Picker("Registry", selection: $selectedCollectionID) {
                ForEach(collections) { collection in
                    Text(collection.requirement.title).tag(collection.id)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)

            if let collection = selectedCollection {
                Text(collection.requirement.registryPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
                Text("\(collection.entries.count.formatted()) entries")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var entryList: some View {
        VStack(spacing: 0) {
            Picker("Status", selection: $filter) {
                ForEach(JustificationFilter.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            List(filteredEntries, selection: $selectedEntryID) { entry in
                VStack(alignment: .leading, spacing: 5) {
                    Text(URL(fileURLWithPath: entry.registryKey).lastPathComponent)
                        .font(.headline)
                    Text(entry.registryKey)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if let collection = selectedCollection {
                        JustificationStatusBadge(
                            entry: entry,
                            requirement: collection.requirement
                        )
                    }
                }
                .padding(.vertical, 4)
                .tag(entry.id)
            }
            .searchable(text: $searchText, prompt: "Path or justification")
            .overlay {
                if filteredEntries.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    private func entryDetail(
        _ entry: JustificationEntry,
        requirement: JustificationRequirement
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(URL(fileURLWithPath: entry.registryKey).lastPathComponent)
                            .font(.title2.bold())
                        Text(requirement.title)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    JustificationStatusBadge(entry: entry, requirement: requirement)
                }

                GroupBox("Contract") {
                    VStack(alignment: .leading, spacing: 8) {
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
                                .monospacedDigit()
                        }
                        Divider()
                        LabeledContent("Target file") {
                            Text(entry.targetExists ? "Present" : "Missing")
                                .foregroundStyle(entry.targetExists ? .green : .red)
                        }
                        if let expiresAt = entry.expiresAt {
                            Divider()
                            LabeledContent("Expires") {
                                Text(expiresAt, format: .dateTime.year().month().day().hour().minute())
                                    .foregroundStyle(entry.isExpired ? .red : .primary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Path") {
                    Text(entry.registryKey)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Justification") {
                    Text(entry.justification.isEmpty ? "No value recorded for \(requirement.field)." : entry.justification)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let quoteField = requirement.directUserQuoteField {
                    GroupBox("Direct user request") {
                        Text(recordedUserQuote(entry) ?? "No value recorded for \(quoteField).")
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding()
        }
    }

    private func selectInitialCollection() {
        if selectedCollectionID.isEmpty {
            selectedCollectionID = collections.first?.id ?? ""
        }
        if selectedEntryID == nil {
            selectedEntryID = filteredEntries.first?.id
        }
    }

    private func isValid(
        _ entry: JustificationEntry,
        requirement: JustificationRequirement
    ) -> Bool {
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
    guard let quote = entry.directUserQuote,
          quote.contains(where: { !$0.isWhitespace })
    else {
        return nil
    }
    return quote
}

private func hasRequiredDirectUserQuote(
    _ entry: JustificationEntry,
    requirement: JustificationRequirement
) -> Bool {
    guard requirement.directUserQuoteField != nil else { return true }
    guard let quote = recordedUserQuote(entry) else { return false }
    return entry.justification.contains(quote)
}

private struct JustificationStatusBadge: View {
    let entry: JustificationEntry
    let requirement: JustificationRequirement

    private var presentation: (text: String, symbol: String, color: Color) {
        if !entry.targetExists {
            return ("Missing file", "doc.badge.ellipsis", .red)
        }
        if entry.isExpired {
            return ("Expired", "calendar.badge.exclamationmark", .red)
        }
        if requirement.directUserQuoteField != nil {
            guard let quote = recordedUserQuote(entry) else {
                return ("Missing user quote", "quote.bubble.fill", .red)
            }
            if !entry.justification.contains(quote) {
                return ("Quote not embedded", "quote.bubble.fill", .red)
            }
        }
        if entry.wordCount < requirement.minimumWords {
            return ("Too short", "text.badge.exclamationmark", .orange)
        }
        return ("Valid", "checkmark.seal.fill", .green)
    }

    var body: some View {
        Label(presentation.text, systemImage: presentation.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(presentation.color)
            .accessibilityLabel("Justification status: \(presentation.text)")
    }
}
