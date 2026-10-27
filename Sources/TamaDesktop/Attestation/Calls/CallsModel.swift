import Foundation

/// One session's calls that failed or a gate refused, as Tama keeps them by
/// call identity (`calls/failed`).
struct FailedCalls: Decodable, Sendable {
    struct Failed: Decodable, Sendable {
        let tool: String
        let said: String
        /// Everything that answered the call; empty for a call kept before
        /// whole answers were kept.
        let answer: String?
        let by: String
        let at: String
        let catalog: String
        let retry: String?
    }
    let calls: [String: Failed]
}

private struct Retried: Decodable, Sendable {
    let call: String
}

/// The same library operations `tama calls failed|retry` runs.
@MainActor
final class FailedCallsModel: ObservableObject {
    @Published var session = ""
    @Published var because = ""
    /// What the model is doing now, named for the operator; `nil` when idle.
    @Published private(set) var working: String?
    @Published private(set) var listed: FailedCalls?
    @Published private(set) var failure: String?
    @Published private(set) var mutationResult: String?

    var ready: Bool {
        working == nil && !session.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func clear() {
        listed = nil
        failure = nil
        mutationResult = nil
    }

    /// Release `call` with the stated reason, then read the calls again; a
    /// refused re-read names the read, not the release.
    func run(retry call: String?) async {
        guard ready else { return }
        clear()
        defer { working = nil }
        var step = "Failed calls [calls/failed]"
        do {
            if let call {
                step = "Retry a failed call [calls/retry]"
                working = "Keeping why the repeat differs"
                let body = ["session": session, "call": call, "because": because]
                let _: Retried = try await TamaClient().request(
                    "calls/retry", body: body, as: Retried.self, describing: "Retry a failed call")
                mutationResult =
                    "The reason was kept: the hold on repeating this unchanged call is lifted until it fails again. Every other gate still decides the next call, an open defect that binds it among them."
                because = ""
                step = "Failed calls [calls/failed]"
            }
            working = "Reading the session's failed calls"
            listed = try await TamaClient().request(
                "calls/failed", body: ["session": session], as: FailedCalls.self,
                describing: "Failed calls")
        } catch {
            let sentence = "\(step): \(error.localizedDescription)"
            failure = sentence
            TamaFailureReporting.reportSurfaced(
                failurePoint: "tama.calls", error: error, sentence: sentence)
        }
    }
}
