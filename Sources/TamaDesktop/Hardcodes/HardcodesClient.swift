import Foundation

/// One line that writes down a value nobody declared, as
/// `tama hardcodes --json` reports it: a fleet host, a vault item, a number
/// or a host with a port, with the commit that wrote it when origins were
/// asked for.
struct HardcodeFinding: Decodable, Sendable {
    let path: String
    let line: Int
    let kind: String
    let value: String
    let commit: String?
    let subject: String?
}

/// One repository of the inventory.
struct HardcodeRepository: Decodable, Sendable {
    let repo: String
    let counts: [String: Int]
    let findings: [HardcodeFinding]?
}

/// A repository git could not read, with git's answer.
struct HardcodeUnreadable: Decodable, Sendable {
    let repo: String
    let error: String
}

/// The whole `tama hardcodes --json` document.
struct HardcodesDocument: Decodable, Sendable {
    struct Totals: Decodable, Sendable {
        let repositories: Int
        let findings: Int
    }

    let repositories: [HardcodeRepository]
    let unreadable: [HardcodeUnreadable]
    let totals: Totals
}

/// One table row: a finding and the repository it is in.
struct HardcodeRow: Identifiable, Sendable {
    let repository: String
    let finding: HardcodeFinding

    var id: String { "\(repository)/\(finding.path):\(finding.line)/\(finding.kind)/\(finding.value)" }

    var origin: String {
        guard let commit = finding.commit else { return "" }
        return "\(shortIdentifier(commit)) \(finding.subject ?? "")"
    }
}

/// `hardcodes/scan`, one `tama request` process.
struct HardcodesClient: Sendable {
    private static let operation = "The hardcoded value inventory"

    func scan(root: String, origins: Bool) async throws -> HardcodesDocument {
        try await TamaClient().request(
            "hardcodes/scan",
            body: ["roots": [root], "origins": origins],
            as: HardcodesDocument.self,
            describing: Self.operation
        )
    }
}

/// The Hardcodes screen's state: one root, whether origins are read, and the
/// document the inventory answered.
@MainActor
final class HardcodesModel: ObservableObject {
    enum ScanState: Equatable { case idle, scanning, failed(String), done }

    @Published var root: String = ""
    @Published var origins: Bool = false
    @Published private(set) var document: HardcodesDocument?
    @Published private(set) var state: ScanState = .idle

    private let client = HardcodesClient()

    var canScan: Bool { root.hasPrefix("/") && state != .scanning }

    var rows: [HardcodeRow] {
        (document?.repositories ?? []).flatMap { repository in
            (repository.findings ?? []).map { HardcodeRow(repository: repository.repo, finding: $0) }
        }
    }

    func scan() async {
        state = .scanning
        do {
            document = try await client.scan(root: root, origins: origins)
            state = .done
        } catch {
            document = nil
            state = .failed(error.localizedDescription)
            TamaFailureReporting.reportSurfaced(
                failurePoint: "tama.hardcodes.scan",
                error: error,
                sentence: error.localizedDescription
            )
        }
    }
}
