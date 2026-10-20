import Foundation

/// The scope a session declared: the work it serves and the repositories that
/// work may change, as `tama task scope show --json` prints it.
struct TaskScope: Decodable, Equatable, Sendable {
    let session: String
    let task: String
    let repositories: [String]
    let defect: String
    let taskID: String
    let servesCurrentInstruction: Bool?

    private enum CodingKeys: String, CodingKey {
        case session, task, repositories, defect
        case taskID = "task_id"
        case servesCurrentInstruction = "serves_current_instruction"
    }

    /// The entry the gate holds the session to, as the terminal names it.
    var entry: String {
        switch (defect.isEmpty, taskID.isEmpty) {
        case (true, true): "nothing — this scope authorises no change"
        case (false, true): "defect \(defect)"
        case (true, false): "task \(taskID)"
        case (false, false): "defect \(defect) and task \(taskID)"
        }
    }
}

struct TaskScopeShown: Decodable, Sendable {
    let session: String
    let scope: TaskScope?
}

struct TaskScopeDeclared: Decodable, Sendable {
    let session: String
    let scope: TaskScope
    let notice: String?
}

struct TaskScopeCleared: Decodable, Sendable {
    let session: String
    let cleared: Bool
}

/// The same operations `tama task scope show|set|clear` makes, through
/// `tama request task-scope/…`, one process per operation, with the
/// command's own refusals.
struct TaskScopeClient: Sendable {
    /// Nil runs the binary sealed into this build's hook release.
    var command: TamaCommand?

    func show(session: String) async throws -> TaskScopeShown {
        try await client().request(
            "task-scope/show", body: ["session": session],
            as: TaskScopeShown.self, describing: "Reading the task scope")
    }

    /// Declares `defect` or `task` for `session`; no repository named takes
    /// the task contract's own list.
    func set(
        session: String, repositories: [String], defect: String, task: String
    ) async throws -> TaskScopeDeclared {
        var body: [String: Any] = ["session": session, "repositories": repositories]
        if !defect.isEmpty { body["defect"] = defect }
        if !task.isEmpty { body["task"] = task }
        return try await client().request(
            "task-scope/set", body: body,
            as: TaskScopeDeclared.self, describing: "Declaring the task scope")
    }

    func clear(session: String) async throws -> TaskScopeCleared {
        try await client().request(
            "task-scope/clear", body: ["session": session],
            as: TaskScopeCleared.self, describing: "Clearing the task scope")
    }

    private func client() -> TamaClient {
        TamaClient(command: command)
    }
}
