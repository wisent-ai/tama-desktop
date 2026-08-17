import Darwin
import Foundation

struct ViolationReport: Decodable, Sendable {
    let repos: [ViolationRepoReport]
    let problems: [ViolationProblem]
    let totals: ViolationTotals

    var scannedFiles: Int {
        repos.reduce(0) { $0 + $1.scannedFiles }
    }

    var skippedFiles: Int {
        repos.reduce(0) { $0 + $1.skippedFiles.count }
    }

    var scanErrors: Int {
        repos.reduce(0) { $0 + $1.errors.count }
    }

    /// Every finding, flattened once, because the repair screen ranks by rule
    /// across repositories instead of nesting disclosure groups per repository.
    var allViolations: [ViolationRecord] {
        repos.flatMap(\.violations)
    }
}

struct ViolationRepoReport: Decodable, Identifiable, Sendable {
    let repo: String
    let hook: String
    let mode: String
    let scannedFiles: Int
    let skippedFiles: [ViolationSkippedFile]
    let violations: [ViolationRecord]
    let errors: [ViolationScanError]

    var id: String { repo }

    var ruleGroups: [ViolationRuleGroup] {
        var groups: [ViolationRuleGroup] = []
        var indexByRule: [String: Int] = [:]
        for violation in violations {
            if let index = indexByRule[violation.rule] {
                groups[index].violations.append(violation)
            } else {
                indexByRule[violation.rule] = groups.count
                groups.append(ViolationRuleGroup(rule: violation.rule, violations: [violation]))
            }
        }
        return groups
    }
}

struct ViolationRuleGroup: Identifiable, Sendable {
    let rule: String
    var violations: [ViolationRecord]

    var id: String { rule }
}

struct ViolationRecord: Decodable, Identifiable, Sendable {
    let hook: String
    let rule: String
    let path: String
    let message: String

    var id: String { "\(rule)|\(path)" }
}

struct ViolationSkippedFile: Decodable, Sendable {
    let path: String
    let reason: String
}

struct ViolationScanError: Decodable, Sendable {
    let path: String
    let message: String
}

struct ViolationProblem: Decodable, Sendable {
    let owner: String?
    let repo: String?
    let error: String
}

struct ViolationTotals: Decodable, Equatable, Sendable {
    let repositories: Int
    let violations: Int
    let problems: Int
}

struct ViolationsClient: Sendable {
    static let scanCommand = "find-violations"
    static let cleanCommand = "clean"

    func scan(repoPath: String) throws -> ViolationReport {
        let path = try validatedRepositoryPath(repoPath)
        let result = try TamaCLI(
            command: Self.scanCommand,
            arguments: [Self.scanCommand, "--repo", path, "--json"]
        ).run()
        switch result.status {
        // Exit 1 is "violations found", which is a report and not a failure.
        case 0, 1:
            do {
                return try JSONDecoder().decode(ViolationReport.self, from: result.stdout)
            } catch {
                // The decoding reason is the only evidence there is when the
                // scanner's output and this build disagree about the report.
                throw TamaCLIError.unreadableOutput(
                    Self.scanCommand,
                    error.localizedDescription
                )
            }
        case 2:
            throw TamaCLIError.usageRejected(Self.scanCommand, result.stderrSnippet)
        default:
            throw TamaCLIError.commandFailed(
                Self.scanCommand,
                status: result.status,
                message: result.stderrSnippet
            )
        }
    }

    func clean(repoPath: String) throws -> String {
        let path = try validatedRepositoryPath(repoPath)
        try ensureCleanupAgentAvailable()
        let result = try TamaCLI(
            command: Self.cleanCommand,
            arguments: [Self.cleanCommand, "--repo", path],
            extraEnvironment: cleanStateEnvironment()
        ).run()
        switch result.status {
        case EXIT_SUCCESS:
            let summary = result.stdoutSnippet
            return summary.isEmpty
                ? "The clean command finished without printing a summary."
                : summary
        case 2:
            throw TamaCLIError.usageRejected(Self.cleanCommand, result.stderrSnippet)
        default:
            let message = result.stderrSnippet.isEmpty
                ? result.stdoutSnippet
                : result.stderrSnippet
            throw TamaCLIError.commandFailed(
                Self.cleanCommand,
                status: result.status,
                message: message
            )
        }
    }

    private func cleanStateEnvironment() -> [String: String] {
        guard
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            return [:]
        }
        return [
            "TAMA_CLEAN_STATE_DIR": support
                .appendingPathComponent("Tama", isDirectory: true)
                .appendingPathComponent("violations", isDirectory: true)
                .path
        ]
    }

    private func validatedRepositoryPath(_ value: String) throws -> String {
        guard value.hasPrefix("/") else {
            throw ViolationsError.invalidRepository(value)
        }
        let manager = FileManager.default
        let root = URL(fileURLWithPath: value, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        var isDirectory = ObjCBool(false)
        guard
            manager.fileExists(atPath: root.path, isDirectory: &isDirectory),
            isDirectory.boolValue,
            manager.fileExists(atPath: root.appendingPathComponent(".git").path)
        else {
            throw ViolationsError.invalidRepository(root.path)
        }
        let attributes = try manager.attributesOfItem(atPath: root.path)
        guard
            let owner = attributes[.ownerAccountID] as? NSNumber,
            owner.uint32Value == getuid()
        else {
            throw ViolationsError.repositoryNotOwned(root.path)
        }
        return root.path
    }

    private func ensureCleanupAgentAvailable() throws {
        let manager = FileManager.default
        guard TamaCLI.executableCandidates(named: "codex").contains(where: {
            manager.isExecutableFile(atPath: $0.path)
        }) else {
            throw ViolationsError.cleanupAgentUnavailable
        }
    }
}

enum ViolationsError: LocalizedError {
    case invalidRepository(String)
    case repositoryNotOwned(String)
    case cleanupAgentUnavailable

    /// The sentence the repair screen shows when the operator stops a cleanup:
    /// the working tree is not where it started, and saying so is the whole
    /// point of reporting a cancellation at all.
    static let cleanupCancelled =
        "The clean command was cancelled. Partial working-tree edits remain visible; inspect them and complete a read-only scan before retrying."

    var errorDescription: String? {
        switch self {
        case let .invalidRepository(path):
            "Choose an existing absolute Git repository directory: \(path)"
        case let .repositoryNotOwned(path):
            "Tama refuses to mutate a repository not owned by the current user: \(path)"
        case .cleanupAgentUnavailable:
            "Codex is unavailable. Install and authenticate Codex before confirming cleanup."
        }
    }
}
