import SwiftUI
import WisentDesignSystem

/// The session that made an admitted commit, as review-commit kept it.
struct AdmissionCommitter: Decodable, Sendable, Hashable {
    let agent: String
    let session: String
    /// The commit ran outside every session's process tree and was read as
    /// this session's because its index carried the session's edits.
    let carried: Bool
}

/// One commit `tama hook review-commit` admitted, as `reviews/admitted`
/// returns it: none for the committer is the operator's own commit, none
/// for the parent a root commit.
struct Admission: Decodable, Sendable, Hashable {
    let commit: String
    let parent: String?
    let tree: String
    let committer: AdmissionCommitter?
    let rounds: String?
    let admittedAt: String
    let committedAt: String
}

@MainActor
final class AdmittedCommitModel: ObservableObject {
    enum State: Equatable {
        case idle, loading, ready
        case failed(String)
    }

    @Published var repository = ""
    @Published var commit = ""
    @Published private(set) var state: State = .idle
    @Published private(set) var admission: Admission?

    func read() async {
        let checkout = repository.trimmingCharacters(in: .whitespacesAndNewlines)
        let named = commit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !checkout.isEmpty, !named.isEmpty else {
            state = .failed("Name the checkout and the commit whose admission is read.")
            return
        }
        state = .loading
        admission = nil
        do {
            admission = try await TamaClient().request(
                "reviews/admitted", body: ["repository": checkout, "commit": named],
                as: Admission.self, describing: "Admission of \(named) in \(checkout)"
            )
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
            TamaFailureReporting.reportSurfaced(
                failurePoint: "tama.reviews.admitted", error: error,
                sentence: error.localizedDescription
            )
        }
    }
}

/// Which session made a commit and the rounds review-commit admitted it on:
/// the same reader as `tama reviews admitted`.
struct AdmittedCommitView: View {
    @StateObject private var model = AdmittedCommitModel()

    var body: some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
            Text("Admitted commit").font(WisentTypeScale.body())
            HStack {
                TextField("Checkout path", text: $model.repository)
                TextField("Commit", text: $model.commit)
                Button("Read admission") { Task { await model.read() } }
                    .disabled(model.state == .loading)
            }
            switch model.state {
            case .idle:
                Text(
                    "Every commit review-commit admits is kept with the session that made it and its rounds."
                )
            case .loading:
                WisentProgressPanel(
                    title: "Reading the admission",
                    detail: "Reading the checkout's admission register.")
            case .failed(let cause):
                WisentAlertPanel(tone: .danger, title: "No admission could be read", detail: cause)
            case .ready:
                if let admission = model.admission { admitted(admission) }
            }
        }
        .padding(WisentDesign.Space.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func admitted(_ admission: Admission) -> some View {
        if let committer = admission.committer {
            Text(
                "Committed by \(committer.agent) session \(committer.session)"
                    + (committer.carried ? ", outside its process tree, carrying its edits" : "")
            )
            .textSelection(.enabled)
        } else {
            Text("Committed by the operator: no agent session made it")
        }
        if let parent = admission.parent {
            Text("Commit \(admission.commit) (tree \(admission.tree)) after \(parent)")
                .font(WisentTypeScale.identifier())
                .textSelection(.enabled)
        } else {
            Text("Root commit \(admission.commit) (tree \(admission.tree))")
                .font(WisentTypeScale.identifier())
                .textSelection(.enabled)
        }
        Text("Admitted at \(admission.admittedAt), committed at \(admission.committedAt)")
        if let rounds = admission.rounds {
            Text(rounds).textSelection(.enabled)
        } else {
            Text("No harsh-review rounds: the declared judge decided alone.")
        }
    }
}
