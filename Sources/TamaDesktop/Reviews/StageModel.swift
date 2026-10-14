import Foundation

struct StageReport: Decodable, Sendable {
    let session: String
    let repository: String
    let paths: [String]
    let calls: [String]
    let tree: String
    let applied: Bool
}

@MainActor
final class StageModel: ObservableObject {
    @Published var session = ""
    @Published var repository = ""
    @Published private(set) var running = false
    @Published private(set) var report: StageReport?
    @Published private(set) var failure: String?

    var ready: Bool {
        !running && !session.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func run(inspect: Bool) async {
        guard ready else { return }
        running = true
        report = nil
        failure = nil
        defer { running = false }
        do {
            report = try await TamaClient().request(
                "stage", body: ["session": session, "repository": repository, "inspect": inspect],
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
