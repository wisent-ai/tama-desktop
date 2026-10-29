import Foundation

/// A recorded file a staging left out, and why (`tama stage`'s `omitted`).
struct StageOmission: Decodable, Sendable, Hashable {
    let path: String
    let cause: String
}

struct StageReport: Decodable, Sendable {
    let session: String
    let repository: String
    let paths: [String]
    let omitted: [StageOmission]
    let calls: [String]
    let tree: String
    let applied: Bool
}

@MainActor
final class StageModel: ObservableObject {
    @Published var session = ""
    @Published var repository = ""
    /// Files to stage, one per line, as `tama stage --path` takes them; empty
    /// stages every recorded edit of the session.
    @Published var paths = ""
    /// Sessions that wrote the session's files together with it, one per
    /// line, as `tama stage --with` takes them; empty names none.
    @Published var coauthors = ""
    /// The Oko task this session took over from a stopped co-author, as
    /// `tama stage --task` takes it; empty names none.
    @Published var task = ""
    @Published private(set) var running = false
    @Published private(set) var report: StageReport?
    @Published private(set) var failure: String?

    var ready: Bool {
        !running && !session.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The files named in `paths`, one per non-blank line, trimmed.
    var selectedPaths: [String] {
        paths.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The sessions named in `coauthors`, one per non-blank line, trimmed.
    var namedCoauthors: [String] {
        coauthors.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func run(inspect: Bool) async {
        guard ready else { return }
        running = true
        report = nil
        failure = nil
        defer { running = false }
        var body: [String: Any] = [
            "session": session, "repository": repository, "inspect": inspect,
        ]
        let selected = selectedPaths
        if !selected.isEmpty {
            body["paths"] = selected
        }
        let with = namedCoauthors
        if !with.isEmpty {
            body["with"] = with
        }
        let takenTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        if !takenTask.isEmpty {
            body["task"] = takenTask
        }
        do {
            report = try await TamaClient().request(
                "stage", body: body,
                as: StageReport.self, describing: "Session-owned staging"
            )
        } catch {
            failure = error.localizedDescription
            TamaFailureReporting.reportSurfaced(
                failurePoint: "tama.stage", error: error,
                sentence: error.localizedDescription
            )
        }
    }
}
