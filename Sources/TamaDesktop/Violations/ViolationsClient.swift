import Darwin
import Foundation

struct ViolationReport: Decodable, Sendable {
    let repos: [ViolationRepoReport]
    let problems: [ViolationProblem]
    let totals: ViolationTotals

    var scannedFiles: Int {
        repos.map(\.scannedFiles).reduce(.zero, +)
    }

    var skippedFiles: Int {
        repos.map(\.skippedFiles.count).reduce(.zero, +)
    }

    var scanErrors: Int {
        repos.map(\.errors.count).reduce(.zero, +)
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
    private static let scanOperation = "The violation scan"
    private static let cleanOperation = "The cleanup"
    private let command: TamaCommand?

    init(command: TamaCommand? = nil) {
        self.command = command
    }

    /// `hook`, when given, narrows the replay to that one registered hook, as
    /// `tama violations find --hook <id>` does; the request refuses an id the
    /// program does not run.
    func scan(repoPath: String, mode: ViolationScanMode, hook: String?) async throws
        -> ViolationReport
    {
        let path = try validatedRepositoryPath(repoPath)
        var body: [String: Any] = ["repo": path]
        if let value = mode.requestValue {
            body["mode"] = value
        }
        if let hook {
            body["hook"] = hook
        }
        let result = try await client().job(
            "violations/scan",
            body: body,
            describing: Self.scanOperation
        )
        switch result.status {
        // The scan exits with failure when it found violations, which is a
        // report and not a failure of the scan.
        case Int(EXIT_SUCCESS), Int(EXIT_FAILURE):
            return try result.decoded(as: ViolationReport.self, describing: Self.scanOperation)
        default:
            throw failedJob(result, failurePoint: "tama.violations.scan")
        }
    }

    func clean(repoPath: String, maxRounds: Int) async throws -> String {
        let path = try validatedRepositoryPath(repoPath)
        let result = try await client().job(
            "violations/clean",
            body: ["repo": path, "maxRounds": maxRounds],
            describing: Self.cleanOperation
        )
        switch result.status {
        case Int(EXIT_SUCCESS):
            let summary = result.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
            return summary.isEmpty
                ? "The cleanup finished without printing a summary."
                : summary
        default:
            throw failedJob(result, failurePoint: "tama.violations.clean")
        }
    }

    /// A rejected job status is reported here before its origin-reported error
    /// reaches a screen; accepted scan findings never enter this branch.
    private func failedJob(
        _ result: TamaClient.JobResult, failurePoint: String
    ) -> TamaBackendError {
        let error = TamaBackendError.refused(result.failureSentence)
        TamaFailureReporting.report(
            failurePoint: failurePoint,
            code: TamaFailureReporting.code(for: error),
            detail: error.localizedDescription
        )
        return error
    }

    private func client() -> TamaClient {
        TamaClient(command: command)
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
}

enum ViolationsError: LocalizedError {
    case invalidRepository(String)
    case repositoryNotOwned(String)

    /// The sentence the repair screen shows when the operator stops a cleanup:
    /// the working tree is not where it started, and saying so is the whole
    /// point of reporting a cancellation at all.
    static let cleanupCancelled =
        "The clean command was cancelled. Partial working-tree edits remain visible; inspect them and complete a read-only scan before retrying."

    var errorDescription: String? {
        switch self {
        case .invalidRepository(let path):
            "Choose an existing absolute Git repository directory: \(path)"
        case .repositoryNotOwned(let path):
            "Tama refuses to mutate a repository not owned by the current user: \(path)"
        }
    }
}
