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

/// `tests/restore`: the record written again from the attestation ledger,
/// and where the record as it stood before is kept.
struct TestApprovalRestore: Decodable, Sendable {
    let action: String
    let approved: [TestApproval]
    let record: String
    let previous: String
}

/// One repository's test code as `tama tests audit` reports it.
struct TestAuditRepository: Decodable, Identifiable, Sendable {
    let repository: String
    let testCode: Int
    let approved: [String]
    let unapprovedFiles: [String]
    let unapprovedInline: [String]
    let filesRemoved: Bool

    var id: String { repository }

    enum CodingKeys: String, CodingKey {
        case repository, approved
        case testCode = "test_code"
        case unapprovedFiles = "unapproved_files"
        case unapprovedInline = "unapproved_inline"
        case filesRemoved = "files_removed"
    }
}

/// `tama tests audit --json`: every repository read, against the approvals.
struct TestAudit: Decodable, Sendable {
    let approvalRecord: String
    let repositoriesRead: Int
    let approved: Int
    let unapproved: Int
    let remaining: Int
    let repositories: [TestAuditRepository]
    let failures: [String]

    enum CodingKeys: String, CodingKey {
        case approved, unapproved, remaining, repositories, failures
        case approvalRecord = "approval_record"
        case repositoriesRead = "repositories_read"
    }
}

struct TestReview: Decodable, Sendable {
    let message: String
}

/// `tama request tests/approvals|approve|revoke|restore|audit`: the same
/// record and the same change `tama tests` makes in the operator's terminal.
struct TestApprovalClient: Sendable {
    /// Nil runs the binary sealed into this build's hook release.
    var command: TamaCommand?

    func list() async throws -> TestApprovalListing {
        try await client().request(
            "tests/approvals", as: TestApprovalListing.self,
            describing: "Reading test approvals")
    }

    func approve(paths: [String]) async throws -> TestApprovalChange {
        try await client().request(
            "tests/approve", body: ["paths": paths],
            as: TestApprovalChange.self, describing: "Approving test code")
    }

    func revoke(paths: [String]) async throws -> TestApprovalChange {
        try await client().request(
            "tests/revoke", body: ["paths": paths],
            as: TestApprovalChange.self, describing: "Revoking a test approval")
    }

    func restore() async throws -> TestApprovalRestore {
        try await client().request(
            "tests/restore", as: TestApprovalRestore.self,
            describing: "Restoring test approvals from the attestation ledger")
    }

    func audit(roots: [String], remove: Bool) async throws -> TestAudit {
        try await client().request(
            "tests/audit", body: ["roots": roots, "remove": remove],
            as: TestAudit.self,
            describing: remove ? "Removing unapproved test files" : "Auditing test code")
    }

    func review(root: String) async throws -> TestReview {
        try await client().request(
            "tests/review", body: ["root": root],
            as: TestReview.self, describing: "Reviewing tracked test files")
    }

    private func client() -> TamaClient {
        TamaClient(command: command)
    }
}
