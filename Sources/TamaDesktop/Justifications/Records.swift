import SwiftUI
import WisentDesignSystem

/// The centre pane of `JustificationsView`: the policy counters, the empty and
/// loading states, and the table of records.
///
/// Split out of that view so it can carry the recording action and still fit
/// the three hundred line limit the operator's gate enforces. Behaviour and
/// member names are unchanged; only the file boundary moves.
extension JustificationsView {
    func contract(_ collection: JustificationCollection) -> some View {
        let requirement = collection.requirement
        let holding = collection.entries.lazy
            .filter { verdict($0, requirement: requirement).holds }
            .count
        var counters = [
            WisentCounterRow.Counter(
                "Records",
                value: collection.entries.count.formatted(.number),
                detail: "Recorded justifications"
            ),
            WisentCounterRow.Counter(
                "Valid",
                value: holding.formatted(.number),
                detail: "Meet the policy",
                tone: .success
            ),
            WisentCounterRow.Counter(
                "Incomplete",
                value: (collection.entries.count - holding).formatted(.number),
                detail: "Missing evidence or expired",
                tone: holding == collection.entries.count ? .neutral : .warning
            ),
        ]
        // A minimum is shown only where the requirement states one.
        if let required = requirement.minimumWords {
            counters.append(
                WisentCounterRow.Counter(
                    "Minimum words", value: required.formatted(.number), detail: "Required length"
                )
            )
        }
        return WisentCounterRow(counters: counters)
    }

    @ViewBuilder
    func content(
        collection: JustificationCollection?,
        entries: [JustificationEntry],
        visible: [JustificationEntry]
    ) -> some View {
        if collections.isEmpty {
            if isRefreshing {
                WisentSkeletonTable(header: true, label: "Reading justifications")
            } else {
                WisentEmptyPanel(
                    title: "No justification policy",
                    detail: "No justifications are required.",
                    symbol: "text.badge.checkmark"
                )
            }
            Spacer()
        } else if entries.isEmpty {
            WisentEmptyPanel(
                title: "No justifications recorded",
                detail: collection?.loadError == nil
                    ? "No records yet."
                    : "Justifications could not be read.",
                symbol: "tray"
            )
            Spacer()
        } else if visible.isEmpty {
            WisentEmptyPanel(
                title: "No record matches this selection",
                detail:
                    "\(counted(entries.count, "record")) available. Change or clear the filters.",
                symbol: "line.3.horizontal.decrease.circle",
                action: WisentAction("Clear filters", kind: .secondary) {
                    verdictFacet = .all
                    query = ""
                }
            )
            Spacer()
        } else if let requirement = collection?.requirement {
            table(visible: visible, entries: entries, requirement: requirement)
        }
    }

    /// The chip marks the minority verdict. A registry where every record holds
    /// gets no chips at all, and the count stays in the rail.
    func table(
        visible: [JustificationEntry],
        entries: [JustificationEntry],
        requirement: JustificationRequirement
    ) -> some View {
        let holding = entries.lazy.filter { verdict($0, requirement: requirement).holds }.count
        // The chip marks the minority verdict: chips go on holding records
        // when they are no more than the records that do not hold.
        let chipsOnHolding = holding <= entries.count - holding
        return WisentTableFrame {
            Table(visible, selection: $selection) {
                TableColumn("TARGET") { entry in
                    Text(entry.registryKey)
                        .font(WisentTypeScale.identifier())
                        .foregroundStyle(WisentDesign.ink)
                        .truncationMode(.head)
                        .help(entry.registryKey)
                        .frame(height: WisentAppLayout.tableRowHeight, alignment: .leading)
                }
                TableColumn("WORDS") { entry in
                    Text(words(entry, requirement: requirement))
                    .font(WisentTypeScale.identifierSmall())
                    .foregroundStyle(
                        requirement.minimumWords.map { entry.wordCount < $0 } == true
                            ? WisentDesign.warning
                            : WisentDesign.secondary
                    )
                    .monospacedDigit()
                }
                TableColumn("EXPIRES") { entry in
                    Text(expiryText(entry.expiresAt))
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(
                            entry.isExpired ? WisentDesign.warning : WisentDesign.secondary
                        )
                        .monospacedDigit()
                }
                TableColumn("VERDICT") { entry in
                    let verdict = verdict(entry, requirement: requirement)
                    if verdict.holds == chipsOnHolding {
                        WisentStatusChip(text: verdict.label, tone: verdict.tone)
                    }
                }
            }
            .tableStyle(.inset)
            // A click on this table already means "select this record" and a
            // drag means "extend that selection", so selectable cell text would
            // compete with both. Opting out restores exactly the behaviour the
            // index had before the window turned selection on.
            .textSelection(.disabled)
        }
    }

    /// A record's word count, beside the requirement's minimum where it states one.
    func words(_ entry: JustificationEntry, requirement: JustificationRequirement) -> String {
        let counted = entry.wordCount.formatted(.number)
        switch requirement.minimumWords {
        case let .some(required): return "\(counted)/\(required.formatted(.number))"
        case .none: return counted
        }
    }

    /// A justification recorded without an expiry holds until it is revoked.
    func expiryText(_ expiresAt: Date?) -> String {
        guard let expiresAt else { return "No expiry" }
        return expiresAt.formatted(date: .numeric, time: .omitted)
    }
}
