import Foundation

struct BuildApproval: Decodable, Sendable {
    let sessionID: String
    let turnDigest: String
    let capturedAt: String
    let quote: String
    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id", turnDigest = "turn_digest", capturedAt = "captured_at", quote
    }
}

struct BuildIntent: Decodable, Identifiable, Sendable {
    let kind: String
    let target: String
    let reason: String
    let revision: String?
    let completedTask: String?
    let recordedAt: UInt64
    let expiresAt: UInt64
    let usedAt: UInt64?
    let userApproval: BuildApproval?
    var id: String { "\(kind):\(target):\(revision ?? ""):\(recordedAt)" }
    enum CodingKeys: String, CodingKey {
        case kind, target, reason, revision
        case completedTask = "completed_task"
        case recordedAt = "recorded_at_epoch", expiresAt = "expires_at_epoch"
        case usedAt = "used_at_epoch"
        case userApproval = "user_approval"
    }
}

struct BuildRegistryRow: Decodable, Identifiable, Sendable {
    let key: String
    let open: Bool
    let entry: BuildIntent
    var id: String { key }
}

struct BuildAllowance: Decodable, Identifiable, Sendable {
    let kind: String
    let spent: UInt64
    let allowed: UInt64
    let left: UInt64
    var id: String { kind }
}

struct BuildListing: Decodable, Sendable {
    let registry: String
    let entries: [BuildRegistryRow]
    let ration: [BuildAllowance]
    let approvalHistory: [BuildIntent]
    enum CodingKeys: String, CodingKey {
        case registry, entries, ration
        case approvalHistory = "approval_history"
    }
}

struct BuildRecording: Decodable, Sendable { let entry: BuildIntent }
struct BuildClosing: Decodable, Sendable { let closed: String }

struct BuildRegistryClient: Sendable {
    func list() async throws -> BuildListing {
        try await client().request("builds", as: BuildListing.self, describing: "Reading build registry")
    }

    func record(target: String, revision: String, reason: String, repository: String,
                completedTask: String, session: String?, quote: String?) async throws -> BuildRecording {
        var body: [String: Any] = ["kind": "build", "target": target,
            "revision": revision, "reason": reason, "repository": repository,
            "completedTask": completedTask]
        if let session { body["approvalSession"] = session }
        if let quote { body["approvalQuote"] = quote }
        return try await client().request("builds/record", body: body,
            as: BuildRecording.self, describing: "Recording build intent and consent")
    }

    func close(kind: String, target: String) async throws -> BuildClosing {
        try await client().request("builds/close", body: ["kind": kind, "target": target],
            as: BuildClosing.self, describing: "Closing build authorization")
    }

    private func client() -> TamaClient {
        TamaClient()
    }
}
