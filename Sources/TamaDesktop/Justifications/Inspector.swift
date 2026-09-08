import SwiftUI
import WisentDesignSystem

/// The evidence pane of `JustificationsView` and the verdict it renders.
///
/// Split out of that view so the view fits the three hundred line limit the
/// operator's own gate enforces: a file at the limit cannot take another
/// feature, and the recording action belongs there. Behaviour is unchanged and
/// every member keeps its name; only the file boundary moves.
extension JustificationsView {
    @ViewBuilder
    func inspector(collection: JustificationCollection?) -> some View {
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
                    label: "Status",
                    value: entry.targetExists ? "Present" : "Missing",
                    tone: entry.targetExists ? .neutral : .warning
                )
                if let expiresAt = entry.expiresAt {
                    WisentField(
                        label: entry.isExpired ? "Expired" : "Expires",
                        value: expiresAt.formatted(date: .abbreviated, time: .shortened),
                        tone: entry.isExpired ? .warning : .neutral
                    )
                }
                Divider()
                prose(
                    "JUSTIFICATION",
                    entry.justification.isEmpty
                        ? "No justification recorded."
                        : entry.justification
                )
                if requirement.directUserQuoteField != nil {
                    prose(
                        "DIRECT USER REQUEST",
                        recordedQuote(entry) ?? "No user request recorded."
                    )
                }
            }
        } else {
            WisentInspector(
                eyebrow: "Justification",
                title: collections.isEmpty ? "No justification policy" : "No record selected"
            ) {
                Text("Select a record to view its justification and user request.")
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func prose(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
            Text(label)
                .font(WisentTypeScale.eyebrow())
                .tracking(0.6)
                .foregroundStyle(WisentDesign.muted)
            Text(text)
                .font(WisentTypeScale.caption())
                .foregroundStyle(WisentDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    struct Verdict {
        let label: String
        let tone: WisentTone
        let holds: Bool
    }

    /// A record that is merely incomplete is amber, never red: the operator has
    /// evidence to finish, not an outage to fix.
    func verdict(
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

    func recordedQuote(_ entry: JustificationEntry) -> String? {
        guard let quote = entry.directUserQuote, quote.contains(where: { !$0.isWhitespace }) else {
            return nil
        }
        return quote
    }
}
