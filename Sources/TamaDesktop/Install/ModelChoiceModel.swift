import Foundation

/// The writes of the Model service section: declaring that this machine has
/// no model and returning Tama to Brama. Each is the terminal's own command
/// as a request (`tama model-provider set --none`, `unset`), so a refusal
/// shows the sentence the terminal prints. The attestations Tama then reads
/// are `AttestationModel`'s.
@MainActor
final class ModelChoiceModel: ObservableObject {
    @Published private(set) var working: String?
    @Published private(set) var failure: String?

    private static let choiceOperation = "The model choice"

    /// `tama model-provider set --none`, then the service read again.
    func declareNone(then reload: @escaping () async -> Void) {
        change("Declaring that this machine has no model", "model-provider/set", body: ["none": true], then: reload)
    }

    /// `tama model-provider unset`, then the service read again.
    func returnToBrama(then reload: @escaping () async -> Void) {
        change("Returning Tama to Brama", "model-provider/unset", body: [:], then: reload)
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
