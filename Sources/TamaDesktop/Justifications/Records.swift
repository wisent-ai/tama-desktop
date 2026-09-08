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
        return WisentCounterRow(counters: [
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
            WisentCounterRow.Counter(
                "Minimum words",
                value: requirement.minimumWords.formatted(.number),
                detail: "Required length"
            )
        ])
    }

    @ViewBuilder
    func content(
        collection: JustificationCollection?,
        entries: [JustificationEntry],
        visible: [JustificationEntry]
    ) -> some View {
        if collections.isEmpty {
            if isRefreshing {
                WisentSkeletonTable(
                    rows: 6,
                    columns: 4,
                    header: true,
                    label: "Reading justifications"
                )
            } else {
                WisentEmptyPanel(
                    title: "No justification policy",
                    detail: "No justifications are required.",
                    symbol: "text.badge.checkmark"
                )
            }
            Spacer(minLength: 0)
        } else if entries.isEmpty {
            WisentEmptyPanel(
                title: "No justifications recorded",
                detail: collection?.loadError == nil
                    ? "No records yet."
                    : "Justifications could not be read.",
                symbol: "tray"
            )
            Spacer(minLength: 0)
        } else if visible.isEmpty {
            WisentEmptyPanel(
                title: "No record matches this selection",
                detail: "\(counted(entries.count, "record")) available. Change or clear the filters.",
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
    func table(
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
            // A click on this table already means "select this record" and a
            // drag means "extend that selection", so selectable cell text would
            // compete with both. Opting out restores exactly the behaviour the
            // index had before the window turned selection on.
            .textSelection(.disabled)
        }
    }
}
