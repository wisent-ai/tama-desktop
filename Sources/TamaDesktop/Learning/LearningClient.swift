import Foundation

/// One thing Tama learned across sessions and wants decided: a hook the
/// operator kept contesting, or a rule the frustration drafter recorded.
struct LearningProposal: Decodable, Identifiable, Sendable {
    let id: String
    let kind: String
    let subject: String
    let evidence: UInt64
    let first: String?
    let last: String?
    let says: String?
    let quote: String?
    let action: String
}

struct LearningSourceFailure: Decodable, Identifiable, Sendable {
    let source: String
    let error: String
    var id: String { source }
}

/// `tama rules digest --json`, as `tama request rules/digest` answers it.
struct LearningDigest: Decodable, Sendable {
    let proposals: [LearningProposal]
    let dismissed: Int
    let unreadable: [LearningSourceFailure]
}

struct LearningDismissal: Decodable, Sendable {
    let dismissed: String
    let detail: String
}

struct LearningClient: Sendable {
    func digest() async throws -> LearningDigest {
        try await TamaClient().request("rules/digest", as: LearningDigest.self,
            describing: "Reading what Tama learned across sessions")
    }

    /// The operator's own click is the approval the command asks for outside an
    /// agent session, so this one call carries it; nothing else does.
    func dismiss(_ proposal: LearningProposal) async throws -> LearningDismissal {
        let bundled = try TamaCommand.bundled()
        var environment = bundled.environment
        environment["DEVICE_HOOK_EDIT_APPROVED"] = "1"
        let command = TamaCommand(executable: bundled.executable, root: bundled.root,
                                  environment: environment)
        return try await TamaClient(command: command).request("rules/dismiss",
            body: ["id": proposal.id], as: LearningDismissal.self,
            describing: "Dismissing \(proposal.id)")
    }
}
