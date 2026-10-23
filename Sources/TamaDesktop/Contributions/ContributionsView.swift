import SwiftUI
import WisentDesignSystem

/// The commits that reached a remote with a standing attestation, as Wisent's
/// contribution ledger credits them to their git authors: the same
/// operations as `tama contributions pending|report`, each one
/// `tama request` process. Every refusal is shown in Tama's words.
struct ContributionEvent: Decodable, Identifiable, Sendable {
    let sourceEventId: String
    let contributorId: String
    let occurredAt: String
    let held: Bool?

    var id: String { sourceEventId }

    enum CodingKeys: String, CodingKey {
        case sourceEventId = "source_event_id"
        case contributorId = "contributor_id"
        case occurredAt = "occurred_at"
        case held
    }
}

struct ContributionOutcome: Decodable, Identifiable, Sendable {
    struct Answer: Decodable, Sendable { let recorded: Bool }
    let commit: String
    let answer: Answer?
    let refused: String?

    var id: String { commit }
}

struct ContributionReport: Decodable, Sendable {
    let ledger: String
    let events: [ContributionOutcome]
    let held: [String]
}

@MainActor
final class ContributionsModel: ObservableObject {
    @Published var repository = ""
    @Published var reference = ""
    @Published var since = ""
    @Published var ledger = ""
    @Published private(set) var events: [ContributionEvent]?
    @Published private(set) var report: ContributionReport?
    @Published private(set) var failure: String?
    @Published private(set) var isWorking = false

    /// The body's fields: only those the operator filled, as flags left out.
    private func fields(_ named: [String: String]) -> [String: Any] {
        named.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private var range: [String: Any] {
        fields(["repository": repository, "ref": reference, "since": since, "ledger": ledger])
    }

    private func perform<Answer: Decodable>(
        _ operation: String, body: [String: Any], as type: Answer.Type, describing: String
    ) async -> Answer? {
        isWorking = true
        defer { isWorking = false }
        do {
            let answer = try await TamaClient().request(operation, body: body, as: type, describing: describing)
            failure = nil
            return answer
        } catch {
            failure = error.localizedDescription
            return nil
        }
    }

    func loadPending() async {
        events = await perform(
            "contributions/pending", body: range, as: [ContributionEvent].self,
            describing: "The accepted-commit listing")
    }

    func send() async {
        report = await perform(
            "contributions/report", body: range, as: ContributionReport.self,
            describing: "The contribution report")
        if report != nil { await loadPending() }
    }
}

struct ContributionsView: View {
    @ObservedObject var model: ContributionsModel

    var body: some View {
        WisentScreen(title: SidebarDestination.contributions.title, scope: "accepted commits credited to their authors") {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x5) {
                if let failure = model.failure {
                    WisentErrorBanner(title: "Tama refused this", detail: failure)
                }
                WisentSectionBox(title: "Range", detail: "Blank ledger uses TAMA_CONTRIBUTION_LEDGER_URL; with none, commits are listed without asking") {
                    VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                        TextField("Repository path", text: $model.repository)
                        TextField("Remote branch, e.g. origin/main", text: $model.reference)
                        TextField("Since revision (optional)", text: $model.since)
                        TextField("Ledger origin (optional)", text: $model.ledger)
                        HStack {
                            Button("List") { Task { await model.loadPending() } }
                            Button("Report to the ledger") { Task { await model.send() } }
                        }
                        .disabled(model.isWorking)
                    }
                }
                if let report = model.report { sent(report) }
                if let events = model.events { listed(events) }
                linkSection
            }
        }
    }

    private func listed(_ events: [ContributionEvent]) -> some View {
        WisentSectionBox(title: "Accepted commits", detail: "\(events.count) commits") {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                ForEach(events) { event in
                    WisentField(label: event.sourceEventId, value: "\(event.contributorId) · \(event.occurredAt) · \(heldText(event.held))")
                }
            }
        }
    }

    /// The commits the ledger answered, the ones it refused counted apart:
    /// a report refused in part is answered whole, each refusal on its line.
    private func sent(_ report: ContributionReport) -> some View {
        let refused = report.events.filter { $0.refused != nil }.count
        let detail = "\(report.events.count - refused) recorded, \(refused) refused, \(report.held.count) already held by \(report.ledger)"
        return WisentSectionBox(title: "Last report", detail: detail) {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                ForEach(report.events) { outcome in
                    WisentField(label: outcome.commit, value: outcomeText(outcome))
                }
            }
        }
    }

    /// Tama links no one: an author links their address on the Rewards page,
    /// where the account's own verified email is the proof.
    private var linkSection: some View {
        WisentSectionBox(title: "Linking an author", detail: "Until an author's email is linked to a Wisent account, the ledger credits nobody for their commits") {
            Text("An author links their own address with Link my email for Tama on the Rewards page of compute.wisent.com, which takes the account's verified email; nobody can link an address that is not theirs.")
        }
    }

    private func heldText(_ held: Bool?) -> String {
        switch held {
        case .some(true): "held by the ledger"
        case .some(false): "not held yet"
        case .none: "no ledger asked"
        }
    }

    private func outcomeText(_ outcome: ContributionOutcome) -> String {
        switch (outcome.answer, outcome.refused) {
        case let (.some(answer), _): answer.recorded ? "recorded" : "already recorded"
        case let (.none, .some(refusal)): "refused: \(refusal)"
        case (.none, .none): "the ledger's answer carries neither a record nor a refusal"
        }
    }
}
