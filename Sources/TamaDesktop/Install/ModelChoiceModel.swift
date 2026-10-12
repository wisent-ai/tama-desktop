import Foundation

/// What the backend answers to one attestation: whether it says the task is
/// finished, every reason it does not, and where it was recorded for the
/// session when it stood.
struct AttestationVerdict: Decodable, Sendable {
    let finished: Bool
    let refusals: [String]
    let recorded: String?
}

/// The writes of the Model service section: declaring that this machine has
/// no model, returning Tama to Brama, and reading or recording a task's
/// attestation. Each is the terminal's own command as a request
/// (`tama model-provider set --none`, `unset`, `tama assignment attest`), so a
/// refusal shows the sentence the terminal prints.
@MainActor
final class ModelChoiceModel: ObservableObject {
    @Published private(set) var working: String?
    @Published private(set) var failure: String?
    @Published private(set) var verdict: AttestationVerdict?
    @Published var session = ""
    @Published var attestationFile: URL?

    private static let choiceOperation = "The model choice"
    private static let attestOperation = "The attestation reading"

    /// `tama model-provider set --none`, then the service read again.
    func declareNone(then reload: @escaping () async -> Void) {
        change("Declaring that this machine has no model", "model-provider/set", body: ["none": true], then: reload)
    }

    /// `tama model-provider unset`, then the service read again.
    func returnToBrama(then reload: @escaping () async -> Void) {
        change("Returning Tama to Brama", "model-provider/unset", body: [:], then: reload)
    }

    /// `tama assignment attest FILE [--session ID]`: the chosen file's
    /// attestation read, and recorded for the session when one is named and
    /// the attestation stands.
    func attest() {
        guard working == nil else { return }
        guard let attestationFile else {
            failure = "Choose the attestation file to read."
            return
        }
        let document: Any
        do {
            document = try JSONSerialization.jsonObject(with: Data(contentsOf: attestationFile))
        } catch {
            failure = "\(attestationFile.path) could not be read as JSON: \(error.localizedDescription)"
            return
        }
        var body: [String: Any] = ["attestation": document]
        let named = session.trimmingCharacters(in: .whitespacesAndNewlines)
        if !named.isEmpty { body["session"] = named }
        working = named.isEmpty ? "Reading the attestation" : "Reading and recording the attestation"
        failure = nil
        Task {
            do {
                verdict = try await TamaClient().request(
                    "assignment/attest", body: body, as: AttestationVerdict.self,
                    describing: Self.attestOperation)
            } catch {
                verdict = nil
                failure = Self.sentence(error)
            }
            working = nil
        }
    }

    private func change(
        _ label: String, _ operation: String, body: [String: Any],
        then reload: @escaping () async -> Void
    ) {
        guard working == nil else { return }
        working = label
        failure = nil
        Task {
            do {
                _ = try await TamaClient().request(
                    operation, body: body, as: ModelChoiceAnswer.self,
                    describing: Self.choiceOperation)
                await reload()
            } catch {
                failure = Self.sentence(error)
            }
            working = nil
        }
    }

    private static func sentence(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

/// A model-choice write answers with the choice and its check; the Install
/// screen reads the service again to show them, so nothing of the answer is
/// decoded beyond its being one.
private struct ModelChoiceAnswer: Decodable {}
