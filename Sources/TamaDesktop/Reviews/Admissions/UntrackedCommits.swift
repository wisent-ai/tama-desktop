import SwiftUI
import WisentDesignSystem

/// One commit no defect or task tracks, as `reviews/untracked` lists it.
struct UntrackedCommit: Decodable, Sendable, Hashable {
    let commit: String
    let why: String
    let session: String?
}

private struct UntrackedAnswer: Decodable, Sendable {
    let untracked: [UntrackedCommit]
}

@MainActor
final class UntrackedCommitsModel: ObservableObject {
    enum State: Equatable {
        case idle, loading, ready
        case failed(String)
    }

    @Published var repository = ""
    @Published var since = ""
    @Published private(set) var state: State = .idle
    @Published private(set) var commits: [UntrackedCommit] = []

    func read() async {
        let checkout = repository.trimmingCharacters(in: .whitespacesAndNewlines)
        let after = since.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !checkout.isEmpty, !after.isEmpty else {
            state = .failed("Name the checkout and the commit after which its commits are read.")
            return
        }
        state = .loading
        commits = []
        do {
            let answer = try await TamaClient().request(
                "reviews/untracked", body: ["repository": checkout, "since": after],
                as: UntrackedAnswer.self, describing: "Untracked commits of \(checkout) after \(after)"
            )
            commits = answer.untracked
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
            TamaFailureReporting.reportSurfaced(
                failurePoint: "tama.reviews.untracked", error: error,
                sentence: error.localizedDescription
            )
        }
    }
}

/// Every commit after a revision that no defect or task tracks: the same
/// listing as `tama reviews untracked`.
struct UntrackedCommitsView: View {
    @StateObject private var model = UntrackedCommitsModel()

    var body: some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
            Text("Untracked commits").font(WisentTypeScale.body())
            HStack {
                TextField("Checkout path", text: $model.repository)
                TextField("After commit", text: $model.since)
                Button("Read untracked commits") { Task { await model.read() } }
                    .disabled(model.state == .loading)
            }
            switch model.state {
            case .idle:
                Text("Each commit is kept with the defect or task its session declared; these are the ones with none.")
            case .loading:
                WisentProgressPanel(
                    title: "Reading the commits",
                    detail: "Reading each commit's admission.")
            case .failed(let cause):
                WisentAlertPanel(tone: .danger, title: "The commits could not be read", detail: cause)
            case .ready:
                if model.commits.isEmpty {
                    Text("Every commit after \(model.since) was made for a defect or task.")
                } else {
                    WisentAlertPanel(
                        tone: .warning, title: "\(model.commits.count) commit(s) no item tracks",
                        detail: "Record the defect or task each served, or repair the session that made it.")
                    ForEach(model.commits, id: \.commit) { untracked in
                        VStack(alignment: .leading) {
                            Text(untracked.commit).font(WisentTypeScale.identifier()).textSelection(.enabled)
                            Text(untracked.why)
                            if let session = untracked.session {
                                Text("Session \(session)").textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
        .padding(WisentDesign.Space.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
