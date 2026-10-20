import SwiftUI
import WisentDesignSystem

/// One finding of a harsh review round, as `tama reviews harsh` keeps it.
struct HarshFinding: Decodable, Sendable, Hashable {
    let quote: String
    let problem: String
    let require: String
}

/// Who reviewed a round: a session, a model or the operator.
enum HarshReviewer: Decodable, Sendable, Hashable {
    case session(String)
    case model(String)
    case operatorShell

    private enum Keys: String, CodingKey { case kind, id }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        switch try values.decode(String.self, forKey: .kind) {
        case "session": self = .session(try values.decode(String.self, forKey: .id))
        case "model": self = .model(try values.decode(String.self, forKey: .id))
        case "operator": self = .operatorShell
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: values, debugDescription: "unknown reviewer kind \(other)")
        }
    }

    var named: String {
        switch self {
        case .session(let session): "session \(session)"
        case .model(let route): "model \(route)"
        case .operatorShell: "the operator"
        }
    }
}

/// One line of the register: a round, or a finding recorded as a defect.
enum HarshEntry: Decodable, Sendable, Hashable, Identifiable {
    case round(tree: String, reviewer: HarshReviewer, findings: [HarshFinding], atMs: UInt64)
    case disposed(quote: String, defect: String, atMs: UInt64)

    private enum Keys: String, CodingKey { case entry, tree, reviewer, findings, quote, defect, atMs }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        let at = try values.decode(UInt64.self, forKey: .atMs)
        switch try values.decode(String.self, forKey: .entry) {
        case "round":
            self = .round(
                tree: try values.decode(String.self, forKey: .tree),
                reviewer: try values.decode(HarshReviewer.self, forKey: .reviewer),
                findings: try values.decode([HarshFinding].self, forKey: .findings), atMs: at)
        case "disposed":
            self = .disposed(
                quote: try values.decode(String.self, forKey: .quote),
                defect: try values.decode(String.self, forKey: .defect), atMs: at)
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .entry, in: values, debugDescription: "unknown register entry \(other)")
        }
    }

    var id: String {
        switch self {
        case .round(let tree, _, _, let at): "round-\(at)-\(tree)"
        case .disposed(let quote, _, let at): "disposed-\(at)-\(quote)"
        }
    }
}

/// The rounds of the commit a checkout is making, as `reviews/harsh` returns them.
struct HarshRoundsDocument: Decodable, Sendable {
    let register: String
    let tree: String
    let entries: [HarshEntry]
}

@MainActor
final class HarshRoundsModel: ObservableObject {
    enum State: Equatable {
        case idle, loading, ready
        case failed(String)
    }

    @Published var repository = ""
    @Published private(set) var state: State = .idle
    @Published private(set) var document: HarshRoundsDocument?

    func read() async {
        let checkout = repository.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !checkout.isEmpty else {
            state = .failed("Name the checkout whose commit is being made.")
            return
        }
        state = .loading
        document = nil
        do {
            document = try await TamaClient().request(
                "reviews/harsh", body: ["repository": checkout], as: HarshRoundsDocument.self,
                describing: "Harsh review rounds of \(checkout)"
            )
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
            TamaFailureReporting.reportSurfaced(
                failurePoint: "tama.reviews.harsh", error: error,
                sentence: error.localizedDescription
            )
        }
    }
}

/// The rounds of harsh review the next commit of a checkout has, each with its
/// reviewer and findings, and the findings recorded as defects: what
/// `tama hook review-commit` reads before it lets the commit through.
struct HarshRoundsView: View {
    @StateObject private var model = HarshRoundsModel()

    var body: some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
            Text("Harsh review rounds").font(WisentTypeScale.body())
            HStack {
                TextField("Checkout path", text: $model.repository)
                Button("Read rounds") { Task { await model.read() } }
                    .disabled(model.state == .loading)
            }
            switch model.state {
            case .idle:
                Text(
                    "A commit is made only after a reviewer that is not its author recorded a round that found nothing."
                )
            case .loading:
                WisentProgressPanel(title: "Reading rounds", detail: "Reading the checkout's register.")
            case .failed(let cause):
                WisentAlertPanel(tone: .danger, title: "Rounds could not be read", detail: cause)
            case .ready:
                if let document = model.document { rounds(document) }
            }
        }
        .padding(WisentDesign.Space.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func rounds(_ document: HarshRoundsDocument) -> some View {
        Text(document.register).textSelection(.enabled)
        Text("Staged tree \(document.tree)").font(WisentTypeScale.identifier())
        if document.entries.isEmpty {
            Text(
                "No round is recorded for this commit; review-commit refuses it until one by another reviewer finds nothing."
            )
        }
        ForEach(document.entries) { entry in
            switch entry {
            case .round(let tree, let reviewer, let findings, _):
                VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                    Text("Round by \(reviewer.named) over \(tree): \(findings.count) findings")
                    ForEach(findings, id: \.self) { finding in
                        Text("\(finding.quote) — \(finding.problem); required: \(finding.require)")
                            .textSelection(.enabled)
                    }
                }
            case .disposed(let quote, let defect, _):
                Text("Recorded as defect \(defect): \(quote)").textSelection(.enabled)
            }
        }
    }
}
