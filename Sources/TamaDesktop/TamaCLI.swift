import Darwin
import Foundation

/// Every `tama` invocation the application makes goes through this one runner.
///
/// The scan, the cleanup, the provider coverage read and the install plan read
/// all need the same four things: a supported Node, the CLI that ships inside
/// this build, bounded output, and a process tree that dies when the operator
/// says stop. One runner means a failure in any of them reaches the screen as
/// the same literal sentence plus the command that reproduces it.
struct TamaCLI: Sendable {
    struct Result: Sendable {
        let stdout: Data
        let stderr: Data
        let status: Int32

        var stdoutSnippet: String {
            Self.snippet(stdout, limit: Int("4000")!)
        }

        var stderrSnippet: String {
            Self.snippet(stderr, limit: Int("600")!)
        }

        private static func snippet(_ data: Data, limit: Int) -> String {
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard text.count > limit else { return text }
            return String(text.prefix(limit)) + "…"
        }
    }

    /// The command name used in error sentences, so a failed read names the
    /// command the operator can paste into a terminal.
    let command: String
    private let arguments: [String]
    private let extraEnvironment: [String: String]
    private let outputLimit: Int
    private let timeoutSeconds: Int

    init(
        command: String,
        arguments: [String],
        extraEnvironment: [String: String] = [:],
        outputLimit: Int = Int("16777216")!,
        timeoutSeconds: Int = Int("900")!
    ) {
        self.command = command
        self.arguments = arguments
        self.extraEnvironment = extraEnvironment
        self.outputLimit = outputLimit
        self.timeoutSeconds = timeoutSeconds
    }

    static func executableCandidates(named name: String) -> [URL] {
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

    func run() throws -> Result {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = try Self.nodeURL()
        process.arguments = [try Self.cliURL().path] + arguments
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in extraEnvironment {
            environment[key] = value
        }
        environment["PATH"] = Self.executableCandidates(named: "node")
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
            stdoutBox.drain(stdout.fileHandleForReading, retaining: outputLimit)
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
        let deadline = DispatchTime.now() + .seconds(timeoutSeconds)
        let pollInterval = DispatchTimeInterval.milliseconds(Int("100")!)
        var terminalError: TamaCLIError?
        while completed.wait(timeout: .now() + pollInterval) == .timedOut {
            if Task.isCancelled {
                terminalError = .cancelled(command)
                break
            }
            if DispatchTime.now() >= deadline {
                terminalError = .timedOut(command)
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
            if group.wait(timeout: .now() + .seconds(Int("5")!)) == .timedOut {
                try? stdout.fileHandleForReading.close()
                try? stderr.fileHandleForReading.close()
            }
            throw terminalError
        }
        if group.wait(timeout: .now() + .seconds(Int("30")!)) == .timedOut {
            try? stdout.fileHandleForReading.close()
            try? stderr.fileHandleForReading.close()
            throw TamaCLIError.outputReadFailed(
                command,
                "output pipes did not close after the command exited"
            )
        }
        if let readError = stdoutBox.readError ?? stderrBox.readError {
            throw TamaCLIError.outputReadFailed(command, readError)
        }
        if stdoutBox.wasTruncated || stderrBox.wasTruncated {
            throw TamaCLIError.outputExceeded(command)
        }
        return Result(
            stdout: stdoutBox.data,
            stderr: stderrBox.data,
            status: process.terminationStatus
        )
    }

    /// A read that only accepts exit zero, and reports the backend's own
    /// stderr when it gets anything else.
    func readJSON<Value: Decodable>(_ type: Value.Type) throws -> Value {
        let result = try run()
        guard result.status == EXIT_SUCCESS else {
            throw TamaCLIError.commandFailed(
                command,
                status: result.status,
                message: result.stderrSnippet.isEmpty
                    ? result.stdoutSnippet
                    : result.stderrSnippet
            )
        }
        do {
            return try JSONDecoder().decode(type, from: result.stdout)
        } catch {
            throw TamaCLIError.unreadableOutput(command, error.localizedDescription)
        }
    }

    func readText() throws -> String {
        let result = try run()
        guard result.status == EXIT_SUCCESS else {
            throw TamaCLIError.commandFailed(
                command,
                status: result.status,
                message: result.stderrSnippet.isEmpty
                    ? result.stdoutSnippet
                    : result.stderrSnippet
            )
        }
        return result.stdoutSnippet
    }

    private static func nodeURL() throws -> URL {
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
            } catch let TamaCLIError.unsupportedNodeVersion(version) {
                unsupportedVersion = version
            }
        }
        if let unsupportedVersion {
            throw TamaCLIError.unsupportedNodeVersion(unsupportedVersion)
        }
        throw TamaCLIError.nodeUnavailable
    }

    private static func validatedNodeURL(_ url: URL) throws -> URL {
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
            throw TamaCLIError.unsupportedNodeVersion(version)
        }
        return url
    }

    private static func cliURL() throws -> URL {
        let root = try HookCatalogClient().hookReleaseRoot()
        let cli = root.appendingPathComponent("src/cli.mjs")
        guard FileManager.default.fileExists(atPath: cli.path) else {
            throw TamaCLIError.cliMissing(cli.path)
        }
        return cli
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

enum TamaCLIError: LocalizedError {
    case cliMissing(String)
    case nodeUnavailable
    case unsupportedNodeVersion(String)
    case usageRejected(String, String)
    case commandFailed(String, status: Int32, message: String)
    case unreadableOutput(String, String)
    case outputExceeded(String)
    case outputReadFailed(String, String)
    case timedOut(String)
    case cancelled(String)

    var errorDescription: String? {
        switch self {
        case let .cliMissing(path):
            "The Tama CLI was not found at \(path)."
        case .nodeUnavailable:
            "Node.js is unavailable. Install Node.js 20 or newer in a supported executable location, then retry."
        case let .unsupportedNodeVersion(version):
            "Unsupported Node.js \(version). Install Node.js 20 or newer in a supported executable location."
        case let .usageRejected(command, message):
            message.isEmpty
                ? "The Tama CLI rejected tama \(command)."
                : message
        case let .commandFailed(command, status, message):
            message.isEmpty
                ? "tama \(command) failed with exit code \(status)."
                : "tama \(command) failed (exit \(status)): \(message)"
        case let .unreadableOutput(command, message):
            "tama \(command) produced output Tama could not parse: \(message)"
        case let .outputExceeded(command):
            "tama \(command) exceeded Tama's bounded output limit; excess output was discarded. Review the repository before retrying."
        case let .outputReadFailed(command, message):
            "Tama could not read bounded output from tama \(command): \(message)"
        case let .timedOut(command):
            "tama \(command) exceeded its bounded runtime and was terminated. Review the repository, then retry explicitly."
        case let .cancelled(command):
            "tama \(command) was cancelled."
        }
    }
}
