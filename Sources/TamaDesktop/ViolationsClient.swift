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
    func scan(repoPath: String) throws -> ViolationReport {
        let result = try run(arguments: ["find-violations", "--repo", repoPath, "--json"])
        switch result.status {
        case 0, 1:
            guard let report = try? JSONDecoder().decode(ViolationReport.self, from: result.stdout) else {
                throw ViolationsError.unreadableReport
            }
            return report
        case 2:
            throw ViolationsError.usageRejected(result.stderrSnippet)
        default:
            throw ViolationsError.scanFailed(status: result.status, message: result.stderrSnippet)
        }
    }

    func clean(repoPath: String) throws -> String {
        let result = try run(arguments: ["clean", "--repo", repoPath])
        switch result.status {
        case 0, 1:
            let summary = result.stdoutText
            return summary.isEmpty
                ? "The clean command finished without printing a summary."
                : summary
        case 2:
            throw ViolationsError.usageRejected(result.stderrSnippet)
        default:
            throw ViolationsError.cleanFailed(status: result.status, message: result.stderrSnippet)
        }
    }

    private func cliURL() throws -> URL {
        let root = try HookCatalogClient().repositoryRoot()
        let cli = root.appendingPathComponent("src/cli.mjs")
        guard FileManager.default.fileExists(atPath: cli.path) else {
            throw ViolationsError.cliMissing(cli.path)
        }
        return cli
    }

    private func run(arguments: [String]) throws -> ProcessResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = try ["node", cliURL().path] + arguments
        process.standardOutput = stdout
        process.standardError = stderr

        // Drain both pipes concurrently: scan JSON and clean progress can each
        // exceed the pipe buffer, and the child blocks when nobody reads.
        let stdoutBox = DataBox()
        let stderrBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stdoutBox.data = stdout.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stderrBox.data = stderr.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        try process.run()
        process.waitUntilExit()
        group.wait()
        return ProcessResult(
            stdout: stdoutBox.data,
            stderr: stderrBox.data,
            status: process.terminationStatus
        )
    }
}

private struct ProcessResult {
    let stdout: Data
    let stderr: Data
    let status: Int32

    var stdoutText: String {
        String(data: stdout, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var stderrSnippet: String {
        let text = String(data: stderr, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard text.count > 600 else { return text }
        return String(text.prefix(600)) + "…"
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

enum ViolationsError: LocalizedError {
    case cliMissing(String)
    case usageRejected(String)
    case scanFailed(status: Int32, message: String)
    case cleanFailed(status: Int32, message: String)
    case unreadableReport

    var errorDescription: String? {
        switch self {
        case let .cliMissing(path):
            "The Tama CLI was not found at \(path)."
        case let .usageRejected(message):
            message.isEmpty
                ? "The Tama CLI rejected the request."
                : message
        case let .scanFailed(status, message):
            message.isEmpty
                ? "The violation scan failed with exit code \(status)."
                : "The violation scan failed (exit \(status)): \(message)"
        case let .cleanFailed(status, message):
            message.isEmpty
                ? "The clean command failed with exit code \(status)."
                : "The clean command failed (exit \(status)): \(message)"
        case .unreadableReport:
            "The violation scan produced output Tama could not parse."
        }
    }
}
