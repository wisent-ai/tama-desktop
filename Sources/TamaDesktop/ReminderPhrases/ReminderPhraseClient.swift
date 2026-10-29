import Foundation

/// Who set a phrase and on what authority it stands.
struct ReminderPhraseSource: Decodable, Sendable {
    let kind: String
    let quote: String?
    let defect: String?
    let generatedBy: String?
}

/// One reminder phrase as `tama reminder-phrase list --json` prints it.
struct ReminderPhraseEntry: Decodable, Identifiable, Sendable {
    let id: String
    let sentence: String
    let defect: String?
    let session: String?
    let applies: Bool
    let source: ReminderPhraseSource?

    /// The scope a person reads: `machine`, or the session it belongs to.
    var scope: String {
        session.map { "session \($0)" } ?? "machine"
    }
}

struct ReminderPhraseAdded: Decodable, Sendable {
    let id: String
    let sentence: String
    let defect: String?
    let session: String?
    let applies: Bool?
}

struct ReminderPhraseRemoved: Decodable, Sendable {
    let id: String
    let removed: Bool
}

/// The same operations `tama reminder-phrase list|add|remove` makes, through
/// `tama request reminder-phrase/…`, one process per operation, with the
/// command's own refusals.
struct ReminderPhraseClient: Sendable {
    /// Nil runs the binary sealed into this build's hook release.
    var command: TamaCommand?

    func list() async throws -> ReminderPhrases {
        try await client().request(
            "reminder-phrase/list", as: ReminderPhrases.self,
            describing: "Reading the reminder phrases")
    }

    /// Adds `sentence`, bound to `defect` while Oko holds it open and to
    /// `session` or every session; empty strings name neither.
    func add(sentence: String, defect: String, session: String) async throws -> ReminderPhraseAdded {
        var body: [String: Any] = ["sentence": sentence]
        if !defect.isEmpty { body["defect"] = defect }
        if !session.isEmpty { body["session"] = session }
        return try await client().request(
            "reminder-phrase/add", body: body,
            as: ReminderPhraseAdded.self, describing: "Adding the reminder phrase")
    }

    func remove(id: String) async throws -> ReminderPhraseRemoved {
        try await client().request(
            "reminder-phrase/remove", body: ["id": id],
            as: ReminderPhraseRemoved.self, describing: "Removing the reminder phrase")
    }

    private func client() -> TamaClient {
        TamaClient(command: command)
    }
}
