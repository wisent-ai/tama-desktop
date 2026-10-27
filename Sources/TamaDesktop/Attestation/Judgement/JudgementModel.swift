import Foundation

struct JudgementInspection: Decodable, Sendable {
    struct Failure: Decodable, Sendable, Equatable {
        let cause: String
        let attestable: Bool?
        let observedAtUnixMilliseconds: String?
        let caller: [String]?
        let attributionError: String?
        let priorFailureError: String?
    }
    struct Attestation: Decodable, Sendable {
        struct Answer: Decodable, Sendable {
            let choice: String
            let reason: String
        }
        let source: String
        let attester: [String]?
        let answer: Answer
        let unavailable: String
    }
    let question: String
    let options: [String]
    let failure: Failure?
    let failures: [Failure]?
    let failureError: String?
    let historyError: String?
    let attestationError: String?
    let attestation: Attestation?
}

/// Both surfaces use Tama's library operations, not command text parsing.
@MainActor
final class JudgementModel: ObservableObject {
    @Published var request = ""
    @Published var choice = ""
    @Published var reason = ""
    /// What the model is doing now, named for the operator; `nil` when idle.
    @Published private(set) var working: String?
    @Published private(set) var inspection: JudgementInspection?
    @Published private(set) var failure: String?
    @Published private(set) var mutationResult: String?

    var ready: Bool {
        working == nil && !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func clearInspection() {
        inspection = nil
        choice = ""
        reason = ""
        failure = nil
        mutationResult = nil
    }

    func run(_ operation: String) async {
        guard ready else { return }
        failure = nil
        inspection = nil
        mutationResult = nil
        defer { working = nil }
        // The refusal names the step that failed: after an attestation was
        // recorded or withdrawn, a refused re-read must not read as a refused
        // mutation, which would invite the operator to repeat it.
        var step = "Review failure and alternative [judgement/show]"
        do {
            let body = ["request": request, "choice": choice, "reason": reason]
            if operation == "judgement/attest" {
                step = "Explicit review attestation [\(operation)]"
                working = "Recording the local attestation"
                let _: JudgementInspection.Attestation = try await TamaClient().request(
                    operation, body: body, as: JudgementInspection.Attestation.self,
                    describing: "Explicit review attestation")
                mutationResult = "The local attestation was recorded."
            } else if operation == "judgement/revoke" {
                step = "Withdraw review attestation [\(operation)]"
                working = "Withdrawing the local attestation"
                let result: RemovedJudgement = try await TamaClient().request(
                    operation, body: body, as: RemovedJudgement.self,
                    describing: "Withdraw review attestation")
                mutationResult = "The withdrawal request completed (removed: \(result.removed))."
            }
            step = "Review failure and alternative [judgement/show]"
            working = "Reading the local review record"
            inspection = try await TamaClient().request(
                "judgement/show", body: ["request": request], as: JudgementInspection.self,
                describing: "Review failure and alternative")
            if let inspection, !inspection.options.contains(choice) {
                choice = ""
            }
        } catch {
            let sentence = "\(step): \(error.localizedDescription)"
            failure = sentence
            TamaFailureReporting.reportSurfaced(
                failurePoint: "tama.judgement", error: error, sentence: sentence)
        }
    }
}

private struct RemovedJudgement: Decodable {
    let removed: Bool
}
