import Foundation

/// One commit an agent session made, as the commit review or
/// `tama standing score` recorded it; `unformatted` names the Rust files that
/// cost it a point, and is empty for a commit that earned one.
struct StandingCommit: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let session: String
    let agent: String
    let repository: String
    let tree: String
    let unformatted: [String]
    let recordedAt: String
}

/// A session's points and the charges that lost them, as
/// `tama standing show --json` prints it.
struct SessionStanding: Decodable, Identifiable, Equatable, Sendable {
    let session: String
    let earned: Int
    let lost: Int
    let standing: Int
    let blocked: Bool
    let charges: [StandingCommit]
    let rule: String
    var id: String { session }
}

/// What `tama standing score` made of one commit of the range.
struct ScoredCommit: Decodable, Identifiable, Sendable {
    let commit: String
    let subject: String
    let session: String?
    let unformatted: [String]
    let recorded: Bool
    let cause: String?
    var id: String { commit }
}

struct StandingWithdrawal: Decodable, Sendable {
    struct Taken: Decodable, Sendable {
        let commit: StandingCommit
        let reason: String
        let withdrawnAt: String
    }

    let withdrawn: Taken
    let standing: SessionStanding
}

/// The same operations `tama standing list|show|score|withdraw` makes, through
/// `tama request standing/…`, one process per operation, with the command's
/// own refusals.
struct StandingClient: Sendable {
    /// Nil runs the binary sealed into this build's hook release.
    var command: TamaCommand?

    func list() async throws -> [SessionStanding] {
        try await client().request(
            "standing/list", as: [SessionStanding].self,
            describing: "Reading every session's commit standing")
    }

    func show(session: String) async throws -> SessionStanding {
        try await client().request(
            "standing/show", body: ["session": session],
            as: SessionStanding.self, describing: "Reading the session's commit standing")
    }

    /// Charges the commits of `range` in `repository` to the sessions whose
    /// commit calls made them.
    func score(repository: String, range: String) async throws -> [ScoredCommit] {
        try await client().request(
            "standing/score", body: ["repository": repository, "range": range],
            as: [ScoredCommit].self, describing: "Scoring the commits of the range")
    }

    func withdraw(charge: String, reason: String) async throws -> StandingWithdrawal {
        try await client().request(
            "standing/withdraw", body: ["id": charge, "reason": reason],
            as: StandingWithdrawal.self, describing: "Taking the charge back")
    }

    private func client() -> TamaClient {
        TamaClient(command: command)
    }
}
