import Foundation

/// One branch merge on a checkout's `main`, as `tama merges review --json`
/// reports it, or one checkout git could not read (`error` set, the rest
/// absent).
struct MergeRecord: Decodable, Identifiable, Sendable {
    let repository: String
    let commit: String?
    let branch: String?
    let damaged: Bool?
    let oversized: [String]?
    let revived: [String]?
    let error: String?

    var id: String { "\(repository)/\(commit ?? error ?? "")" }

    var isDamaged: Bool { damaged == true }

    var shortCommit: String { shortIdentifier(commit ?? "") }

    /// What the merge left on main, in the command's own words.
    var findings: String {
        if let error { return "unreadable: \(error)" }
        let over = oversized ?? []
        let back = revived ?? []
        if over.isEmpty, back.isEmpty { return "clean" }
        var parts: [String] = []
        if !over.isEmpty { parts.append("over the limit: \(over.joined(separator: ", "))") }
        if !back.isEmpty { parts.append("carried back: \(back.joined(separator: ", "))") }
        return parts.joined(separator: "; ")
    }
}

/// `merges/review`, one `tama request` process.
struct MergesClient: Sendable {
    private static let operation = "The merge damage review"

    func review(root: String, since: String) async throws -> [MergeRecord] {
        try await TamaClient().request(
            "merges/review",
            body: ["root": root, "since": since],
            as: [MergeRecord].self,
            describing: Self.operation
        )
    }
}

/// The Merges screen's state: one root, one first day, the rows the review
/// answered.
@MainActor
final class MergesModel: ObservableObject {
    enum ReviewState: Equatable {
        case idle, reviewing
        case failed(String)
        case done
    }

    @Published var root: String = ""
    @Published var since: String = ""
    @Published private(set) var records: [MergeRecord] = []
    @Published private(set) var state: ReviewState = .idle

    private let client = MergesClient()

    var canReview: Bool {
        root.hasPrefix("/") && !since.isEmpty && state != .reviewing
    }

    var damagedCount: Int { records.filter(\.isDamaged).count }

    func review() async {
        state = .reviewing
        do {
            records = try await client.review(root: root, since: since)
            state = .done
        } catch {
            records = []
            state = .failed(error.localizedDescription)
            TamaFailureReporting.reportSurfaced(
                failurePoint: "tama.merges.review",
                error: error,
                sentence: error.localizedDescription
            )
        }
    }
}
