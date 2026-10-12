import Foundation

struct SSHGrant: Decodable, Identifiable, Sendable {
    let userRequestQuote: String
    let allowedTargets: [String]
    let allowedOperations: [String]
    let allowedPaths: [String]
    let allowedCommands: [String]
    let lifetime: String
    let sessionId: String?

    var id: String {
        allowedTargets.joined(separator: ",") + "\n" + allowedOperations.joined(separator: ",")
            + "\n" + userRequestQuote
    }
}

struct SSHListing: Decodable, Sendable {
    let registry: String
    let authorizations: [SSHGrant]
}

struct SSHRecording: Decodable, Sendable {
    let authorization: SSHGrant
}

struct SSHRemoval: Decodable, Sendable {
    let removed: String
    let count: Int
}

/// The same operations `tama justify --kind ssh` records, through
/// `tama request`, one process per operation.
struct SSHConsentClient: Sendable {
    /// Nil runs the binary sealed into this build's hook release.
    var command: TamaCommand?

    func list() async throws -> SSHListing {
        try await client().request(
            "justifications/ssh", as: SSHListing.self, describing: "Reading SSH consent")
    }

    func record(
        session: String, targets: [String], operation: String, paths: [String],
        commands: [String], quote: String, match: Bool
    ) async throws -> SSHRecording {
        let body: [String: Any] = [
            "sessionId": session, "targets": targets, "operation": operation,
            "paths": paths, "commands": commands,
            match ? "quoteMatch" : "quote": quote,
        ]
        return try await client().request(
            "justifications/ssh/record", body: body,
            as: SSHRecording.self, describing: "Recording SSH consent")
    }

    func remove(quote: String) async throws -> SSHRemoval {
        try await client().request(
            "justifications/ssh/remove", body: ["quote": quote],
            as: SSHRemoval.self, describing: "Removing SSH consent")
    }

    private func client() -> TamaClient {
        TamaClient(command: command)
    }
}
