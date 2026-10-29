import SwiftUI
import WisentDesignSystem

/// Where admissions started in a checkout, as `reviews/cutover` returns it:
/// the tip of every local branch when review-commit admitted its first
/// candidate there.
struct AdmissionCutover: Decodable, Sendable, Hashable {
    let at: String
    let commits: [String]
}

/// The `reviews/cutover` answer: no cutover while review-commit admitted no
/// commit in the checkout.
private struct CutoverAnswer: Decodable, Sendable {
    let cutover: AdmissionCutover?
}

@MainActor
final class AdmissionCutoverModel: ObservableObject {
    enum State: Equatable {
        case idle, loading, ready
        case failed(String)
    }

    @Published var repository = ""
    @Published private(set) var state: State = .idle
    @Published private(set) var cutover: AdmissionCutover?

    func read() async {
        let checkout = repository.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !checkout.isEmpty else {
            state = .failed("Name the checkout whose admission cutover is read.")
            return
        }
        state = .loading
        cutover = nil
        do {
            let answer = try await TamaClient().request(
                "reviews/cutover", body: ["repository": checkout],
                as: CutoverAnswer.self, describing: "Admission cutover of \(checkout)"
            )
            cutover = answer.cutover
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
            TamaFailureReporting.reportSurfaced(
                failurePoint: "tama.reviews.cutover", error: error,
                sentence: error.localizedDescription
            )
        }
    }
}

/// Where a pushed commit starts to need an admission of its own: the same
/// reader as `tama reviews cutover`.
struct AdmissionCutoverView: View {
    @StateObject private var model = AdmissionCutoverModel()

    var body: some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
            Text("Admission cutover").font(WisentTypeScale.body())
            HStack {
                TextField("Checkout path", text: $model.repository)
                Button("Read cutover") { Task { await model.read() } }
                    .disabled(model.state == .loading)
            }
            switch model.state {
            case .idle:
                Text("A pushed commit made after the cutover carries review-commit's admission.")
            case .loading:
                WisentProgressPanel(
                    title: "Reading the cutover",
                    detail: "Reading the checkout's admission register.")
            case .failed(let cause):
                WisentAlertPanel(tone: .danger, title: "No cutover could be read", detail: cause)
            case .ready:
                if let cutover = model.cutover {
                    Text(
                        "Admissions started at \(cutover.at); every commit these tips hold was made before them:"
                    )
                    ForEach(cutover.commits, id: \.self) { commit in
                        Text(commit).font(WisentTypeScale.identifier()).textSelection(.enabled)
                    }
                } else {
                    Text(
                        "review-commit admitted no commit here yet, so no cutover is kept and no pushed commit is judged by its admission."
                    )
                }
            }
        }
        .padding(WisentDesign.Space.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
