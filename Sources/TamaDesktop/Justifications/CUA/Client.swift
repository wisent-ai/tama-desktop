import Foundation

struct CUAGrant: Decodable, Identifiable, Sendable {
    let userRequestQuote: String
    let allowedAppName: String
    let allowedBundleId: String
    let allowedExecutable: String
    let allowedActions: [String]
    let lifetime: String
    let sessionId: String?

    var id: String { allowedBundleId + "\n" + userRequestQuote }
}

struct CUAListing: Decodable, Sendable {
    let registry: String
    let authorizations: [CUAGrant]
}

struct CUARecording: Decodable, Sendable {
    let authorization: CUAGrant
}

struct CUARemoval: Decodable, Sendable {
    let removed: String
    let count: Int
}

struct CUAConsentClient: Sendable {
    /// Nil runs the binary sealed into this build's hook release.
    var command: TamaCommand?

    func list() async throws -> CUAListing {
        try await client().request("justifications/cua", as: CUAListing.self, describing: "Reading CUA consent")
    }

    func record(session: String, app: String, actions: [String], quote: String, match: Bool) async throws -> CUARecording {
        let body: [String: Any] = [
            "sessionId": session, "app": app, "actions": actions,
            match ? "quoteMatch" : "quote": quote,
        ]
        return try await client().request("justifications/cua/record", body: body,
            as: CUARecording.self, describing: "Recording CUA consent")
    }

    func remove(quote: String) async throws -> CUARemoval {
        try await client().request("justifications/cua/remove", body: ["quote": quote],
            as: CUARemoval.self, describing: "Removing CUA consent")
    }

    private func client() -> TamaClient {
        TamaClient(command: command)
    }
}
