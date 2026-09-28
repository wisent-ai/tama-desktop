import Foundation

/// One path the operator approved test code under, as `tama tests list`
/// reports it.
struct TestApproval: Decodable, Identifiable, Sendable {
    let path: String
    let approvedAt: String

    var id: String { path }

    enum CodingKeys: String, CodingKey {
        case path
        case approvedAt = "approved_at"
    }
}

struct TestApprovalListing: Decodable, Sendable {
    let approved: [TestApproval]
    let record: String
}

struct TestApprovalChange: Decodable, Sendable {
    let changed: [String]
    let action: String
    let approved: [TestApproval]
    let record: String
}

/// `tama request tests/approvals|approve|revoke`: the same record and the same
/// change `tama tests` makes in the operator's terminal.
struct TestApprovalClient: Sendable {
    /// Nil runs the binary sealed into this build's hook release.
    var command: TamaCommand?

    func list() async throws -> TestApprovalListing {
        try await client().request("tests/approvals", as: TestApprovalListing.self,
            describing: "Reading test approvals")
    }

    func approve(paths: [String]) async throws -> TestApprovalChange {
        try await client().request("tests/approve", body: ["paths": paths],
            as: TestApprovalChange.self, describing: "Approving test code")
    }

    func revoke(paths: [String]) async throws -> TestApprovalChange {
        try await client().request("tests/revoke", body: ["paths": paths],
            as: TestApprovalChange.self, describing: "Revoking a test approval")
    }

    private func client() -> TamaClient {
        TamaClient(command: command)
    }
}
