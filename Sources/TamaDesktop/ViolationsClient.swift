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
        let path = try validatedRepositoryPath(repoPath)
        let result = try run(arguments: ["find-violations", "--repo", path, "--json"])
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
        let path = try validatedRepositoryPath(repoPath)
        try ensureCleanupAgentAvailable()
        let result = try run(arguments: ["clean", "--repo", path])
        switch result.status {
        case EXIT_SUCCESS:
            let summary = result.stdoutSnippet
            return summary.isEmpty
                ? "The clean command finished without printing a summary."
                : summary
        case let status where status == Int32("1")!:
            let message = result.stderrSnippet.isEmpty
                ? result.stdoutSnippet
                : result.stderrSnippet
            throw ViolationsError.cleanFailed(status: status, message: message)
        case 2:
            throw ViolationsError.usageRejected(result.stderrSnippet)
        default:
            throw ViolationsError.cleanFailed(status: result.status, message: result.stderrSnippet)
        }
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

    private func nodeURL() throws -> URL {
        let manager = FileManager.default
#if DEBUG
        if let override = ProcessInfo.processInfo.environment["TAMA_NODE"],
           manager.isExecutableFile(atPath: override) {
            return try validatedNodeURL(URL(fileURLWithPath: override))
        }
#endif
        var unsupportedVersion: String?
        for candidate in executableCandidates(named: "node") {
            guard manager.isExecutableFile(atPath: candidate.path) else { continue }
            do {
                return try validatedNodeURL(candidate)
            } catch let ViolationsError.unsupportedNodeVersion(version) {
                unsupportedVersion = version
            }
        }
        if let unsupportedVersion {
            throw ViolationsError.unsupportedNodeVersion(unsupportedVersion)
        }
        throw ViolationsError.nodeUnavailable
    }

    private func validatedNodeURL(_ url: URL) throws -> URL {
        let process = Process()
        let output = Pipe()
        process.executableURL = url
        process.arguments = ["--version"]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        let version = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let majorText = version.drop(while: { !$0.isNumber }).prefix(while: { $0.isNumber })
        guard
            process.terminationStatus == EXIT_SUCCESS,
            let major = Int(majorText),
            let minimumMajor = Int("20"),
            major >= minimumMajor
        else {
            throw ViolationsError.unsupportedNodeVersion(version)
        }
        return url
    }

    private func ensureCleanupAgentAvailable() throws {
        let manager = FileManager.default
        guard executableCandidates(named: "codex").contains(where: {
            manager.isExecutableFile(atPath: $0.path)
        }) else {
            throw ViolationsError.cleanupAgentUnavailable
        }
    }

    private func executableCandidates(named name: String) -> [URL] {
        let manager = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        var directories = (environment["PATH"] ?? "").split(separator: ":").map {
            URL(fileURLWithPath: String($0), isDirectory: true)
        }
        directories.append(contentsOf: [
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
            manager.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin", isDirectory: true),
        ])
        var seen = Set<String>()
        return directories.compactMap { directory in
            let candidate = directory
                .appendingPathComponent(name)
                .standardizedFileURL
            return seen.insert(candidate.path).inserted ? candidate : nil
        }
    }

    private func cliURL() throws -> URL {
        let root = try HookCatalogClient().hookReleaseRoot()
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
        process.executableURL = try nodeURL()
        process.arguments = [try cliURL().path] + arguments
        var environment = ProcessInfo.processInfo.environment
        if let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            environment["TAMA_CLEAN_STATE_DIR"] = support
                .appendingPathComponent("Tama", isDirectory: true)
                .appendingPathComponent("violations", isDirectory: true)
                .path
        }
        environment["PATH"] = executableCandidates(named: "node")
            .map { $0.deletingLastPathComponent().path }
            .joined(separator: ":")
        process.environment = environment
        process.standardOutput = stdout
        process.standardError = stderr

        // Drain both pipes concurrently: scan JSON and clean progress can each
        // exceed the pipe buffer, and the child blocks when nobody reads.
        let stdoutBox = DataBox()
        let stderrBox = DataBox()
        let group = DispatchGroup()

        let completed = DispatchSemaphore(value: .zero)
        process.terminationHandler = { _ in completed.signal() }
        try process.run()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stdoutBox.drain(
                stdout.fileHandleForReading,
                retaining: Int("16777216")!
            )
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stderrBox.drain(
                stderr.fileHandleForReading,
                retaining: Int("65536")!
            )
            group.leave()
        }
        let deadline = DispatchTime.now() + .seconds(Int("900")!)
        let pollInterval = DispatchTimeInterval.milliseconds(Int("100")!)
        var terminalError: ViolationsError?
        while completed.wait(timeout: .now() + pollInterval) == .timedOut {
            if Task.isCancelled {
                terminalError = .processCancelled
                break
            }
            if DispatchTime.now() >= deadline {
                terminalError = .processTimedOut
                break
            }
        }
        if let terminalError {
            signalProcessTree(rootPID: process.processIdentifier, signal: SIGTERM)
            let grace = DispatchTime.now() + .seconds(Int("30")!)
            if completed.wait(timeout: grace) == .timedOut {
                signalProcessTree(rootPID: process.processIdentifier, signal: SIGKILL)
                completed.wait()
            }
            if group.wait(
                timeout: .now() + .seconds(Int("5")!)
            ) == .timedOut {
                try? stdout.fileHandleForReading.close()
                try? stderr.fileHandleForReading.close()
            }
            throw terminalError
        }
        if group.wait(
            timeout: .now() + .seconds(Int("30")!)
        ) == .timedOut {
            try? stdout.fileHandleForReading.close()
            try? stderr.fileHandleForReading.close()
            throw ViolationsError.processOutputReadFailed(
                "output pipes did not close after the command exited"
            )
        }
        if let readError = stdoutBox.readError ?? stderrBox.readError {
            throw ViolationsError.processOutputReadFailed(readError)
        }
        if stdoutBox.wasTruncated || stderrBox.wasTruncated {
            throw ViolationsError.processOutputExceeded
        }
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

    var stdoutSnippet: String {
        let text = String(data: stdout, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let limit = Int("4000")!
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }

    var stderrSnippet: String {
        let text = String(data: stderr, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard text.count > 600 else { return text }
        return String(text.prefix(600)) + "…"
    }
}

final class DataBox: @unchecked Sendable {
    private(set) var data = Data()
    private(set) var wasTruncated = false
    private(set) var readError: String?

    func drain(_ handle: FileHandle, retaining limit: Int) {
        let chunkSize = Int("65536")!
        do {
            while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
                let remaining = max(limit - data.count, .zero)
                if chunk.count > remaining {
                    wasTruncated = true
                }
                if remaining > .zero {
                    data.append(contentsOf: chunk.prefix(remaining))
                }
            }
        } catch {
            readError = error.localizedDescription
        }
    }
}

func signalProcessTree(rootPID: pid_t, signal: Int32) {
    var descendants: [pid_t] = []
    var seen = Set<pid_t>()

    func collectChildren(of parent: pid_t) {
        let requiredBytes = proc_listchildpids(parent, nil, .zero)
        guard requiredBytes > .zero else { return }
        var children = [pid_t](
            repeating: pid_t(),
            count: Int(requiredBytes) / MemoryLayout<pid_t>.stride
        )
        let returnedBytes = children.withUnsafeMutableBytes { buffer in
            proc_listchildpids(
                parent,
                buffer.baseAddress,
                Int32(buffer.count)
            )
        }
        guard returnedBytes > .zero else { return }
        let childCount = min(
            children.count,
            Int(returnedBytes) / MemoryLayout<pid_t>.stride
        )
        for child in children.prefix(childCount)
        where child > .zero && seen.insert(child).inserted {
            descendants.append(child)
            collectChildren(of: child)
        }
    }

    collectChildren(of: rootPID)
    for child in descendants.reversed() {
        _ = kill(child, signal)
    }
    _ = kill(rootPID, signal)
}

enum ViolationsError: LocalizedError {
    case cliMissing(String)
    case usageRejected(String)
    case scanFailed(status: Int32, message: String)
    case cleanFailed(status: Int32, message: String)
    case unreadableReport
    case invalidRepository(String)
    case repositoryNotOwned(String)
    case nodeUnavailable
    case unsupportedNodeVersion(String)
    case cleanupAgentUnavailable
    case processTimedOut
    case processCancelled
    case processOutputExceeded
    case processOutputReadFailed(String)

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
        case let .invalidRepository(path):
            "Choose an existing absolute Git repository directory: \(path)"
        case let .repositoryNotOwned(path):
            "Tama refuses to mutate a repository not owned by the current user: \(path)"
        case .nodeUnavailable:
            "Node.js is unavailable. Install Node.js 20 or newer in a supported executable location, then retry."
        case let .unsupportedNodeVersion(version):
            "Unsupported Node.js \(version). Install Node.js 20 or newer in a supported executable location."
        case .cleanupAgentUnavailable:
            "Codex is unavailable. Install and authenticate Codex before confirming cleanup."
        case .processTimedOut:
            "The violations command exceeded its bounded runtime and was terminated. Review the repository, then retry explicitly."
        case .processCancelled:
            "The violations command was cancelled. If cleanup was active, partial working-tree edits remain visible; inspect them and complete a read-only scan before retrying."
        case .processOutputExceeded:
            "The violations command exceeded Tama's bounded output limit; excess output was discarded. Review the repository before retrying."
        case let .processOutputReadFailed(message):
            "Tama could not read bounded violations output: \(message)"
        }
    }
}
