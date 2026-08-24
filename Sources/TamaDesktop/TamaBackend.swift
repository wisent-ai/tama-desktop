import Darwin
import Foundation

/// The one Tama backend process for the app's lifetime. Spawned lazily on
/// first use as `tama-cli serve --port 0 --root <bundled release>`, which
/// binds 127.0.0.1 on an ephemeral port and prints a single ready line
/// naming that port; the process then serves HTTP until the app kills it on
/// quit. Reads never build argv for the backend's other commands.
final class TamaBackend: @unchecked Sendable {
    static let shared = TamaBackend()

    private let lock = NSLock()
    private var process: Process?
    private var baseURL: URL?
    private var inFlight: Task<URL, Error>?

    private init() {}

    /// The loopback base URL of the running backend, spawning it on first
    /// use or after a death. Concurrent callers share one spawn.
    func endpoint() async throws -> URL {
        if let url = withLock({ () -> URL? in
            if let process, process.isRunning, let baseURL { return baseURL }
            return nil
        }) {
            return url
        }
        if let inFlight = withLock({ inFlight }) {
            return try await inFlight.value
        }
        let task = Task { try await spawn() }
        withLock { inFlight = task }
        defer { withLock { inFlight = nil } }
        return try await task.value
    }

    /// NSLock cannot be locked directly from an async context; these critical
    /// sections never suspend, so they go through one synchronous helper.
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// Kills the backend, if one is running. Synchronous so the application
    /// delegate can call it while the process is already terminating.
    func stop() {
        let running = withLock { () -> Process? in
            let process = self.process
            self.process = nil
            baseURL = nil
            return process
        }
        running?.terminate()
    }

    private func spawn() async throws -> URL {
        let root = try HookCatalogClient().hookReleaseRoot()
        let executable = try Self.executableURL(root: root)
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executable
        process.arguments = ["serve", "--port", "0", "--root", root.path]
        var environment = ProcessInfo.processInfo.environment
        if let stateDirectory = Self.cleanStateDirectory() {
            environment["TAMA_CLEAN_STATE_DIR"] = stateDirectory
        }
        process.environment = environment
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw TamaBackendError.startFailed(error.localizedDescription)
        }
        do {
            let port = try await Self.awaitReady(
                process: process,
                stdout: stdout.fileHandleForReading,
                stderr: stderr.fileHandleForReading
            )
            guard let url = URL(string: "http://127.0.0.1:\(port)") else {
                throw TamaBackendError.startFailed("the ready line named no usable port")
            }
                        withLock {
                self.process = process
                baseURL = url
            }
            return url
        } catch {
            signalProcessTree(rootPID: process.processIdentifier, signal: SIGTERM)
            throw error
        }
    }

    /// Waits for the single ready line the backend prints once it has bound
    /// its port. Any other outcome — exit, timeout, unreadable line — is a
    /// start failure reported with the backend's own stderr tail.
    private static func awaitReady(
        process: Process,
        stdout: FileHandle,
        stderr: FileHandle
    ) async throws -> Int {
        let handshake = ReadyHandshake()
        handshake.attach(stdout: stdout, stderr: stderr)
        return try await withCheckedThrowingContinuation { continuation in
            handshake.scheduleTimeout {
                handshake.finish {
                    signalProcessTree(rootPID: process.processIdentifier, signal: SIGTERM)
                    continuation.resume(
                        throwing: TamaBackendError.startFailed(handshake.stderrSuffix())
                    )
                }
            }
            process.terminationHandler = { _ in
                handshake.finish {
                    continuation.resume(
                        throwing: TamaBackendError.startFailed(handshake.stderrSuffix())
                    )
                }
            }
            stdout.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                guard let line = handshake.appendOutput(data) else { return }
                handshake.finish {
                    if let port = Self.readyPort(line) {
                        continuation.resume(returning: port)
                    } else {
                        continuation.resume(
                            throwing: TamaBackendError.startFailed(handshake.stderrSuffix())
                        )
                    }
                }
            }
            stderr.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                handshake.appendError(text)
            }
        }
    }

    /// The port out of the ready line `{"ready":true,"port":N}`, or nil for
    /// any other line.
    private static func readyPort(_ line: Data) -> Int? {
        guard
            let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            object["ready"] as? Bool == true,
            let port = object["port"] as? NSNumber,
            (1...65535).contains(port.intValue)
        else {
            return nil
        }
        return port.intValue
    }

    /// The backend executable: the binary sealed into this build's hook
    /// release. A DEBUG build may point at a workspace binary instead.
    private static func executableURL(root: URL) throws -> URL {
        let manager = FileManager.default
#if DEBUG
        if let override = ProcessInfo.processInfo.environment["TAMA_CLI"],
           !override.isEmpty {
            let url = URL(fileURLWithPath: override).standardizedFileURL
            guard manager.isExecutableFile(atPath: url.path) else {
                throw TamaBackendError.backendMissing(url.path)
            }
            return url
        }
#endif
        let bundled = root
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("tama-cli")
        guard manager.isExecutableFile(atPath: bundled.path) else {
            throw TamaBackendError.backendMissing(bundled.path)
        }
        return bundled
    }

    /// Cleanup journals and locks cannot live inside the read-only release
    /// directory, so the backend gets the same state directory the
    /// application has always used.
    private static func cleanStateDirectory() -> String? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Tama", isDirectory: true)
            .appendingPathComponent("violations", isDirectory: true)
            .path
    }
}

/// Lock-guarded state for the ready handshake: stdout buffer, stderr tail,
/// the timeout, and the once-only resume of the awaiting continuation.
private final class ReadyHandshake: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutBuffer = Data()
    private var stderrTail = ""
    private var resumed = false
    private var timeoutItem: DispatchWorkItem?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?

    func attach(stdout: FileHandle, stderr: FileHandle) {
        lock.lock()
        stdoutHandle = stdout
        stderrHandle = stderr
        lock.unlock()
    }

    /// Buffers stdout; returns the first complete line once it arrives.
    func appendOutput(_ data: Data) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        stdoutBuffer.append(data)
        guard let newline = stdoutBuffer.firstIndex(of: UInt8(ascii: "\n")) else {
            return nil
        }
        return Data(stdoutBuffer[..<newline])
    }

    func appendError(_ text: String) {
        lock.lock()
        stderrTail = String((stderrTail + text).suffix(Int("2000")!))
        lock.unlock()
    }

    /// The captured stderr, formatted as a trailing sentence fragment.
    func stderrSuffix() -> String {
        lock.lock()
        defer { lock.unlock() }
        let trimmed = stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : trimmed
    }

    func scheduleTimeout(_ action: @escaping () -> Void) {
        let item = DispatchWorkItem(block: action)
        lock.lock()
        timeoutItem = item
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(Int("15")!), execute: item)
    }

    /// Runs `body` exactly once, cancelling the pending timeout and
    /// detaching both read handlers.
    func finish(_ body: () -> Void) {
        lock.lock()
        guard !resumed else {
            lock.unlock()
            return
        }
        resumed = true
        timeoutItem?.cancel()
        let stdout = stdoutHandle
        let stderr = stderrHandle
        lock.unlock()
        stdout?.readabilityHandler = nil
        stderr?.readabilityHandler = nil
        body()
    }
}

enum TamaBackendError: LocalizedError {
    case backendMissing(String)
    case startFailed(String)
    case notHTTP
    case streamClosedEarly
    case refused(String)
    case unreadableOutput(String, String)
    case cancelled(String)

    var errorDescription: String? {
        switch self {
        case let .backendMissing(path):
            "The Tama backend is missing from this build at \(path). Rebuild with Scripts/build-app.sh."
        case let .startFailed(detail):
            detail.isEmpty
                ? "The Tama backend did not start."
                : "The Tama backend did not start: \(detail)"
        case .notHTTP:
            "The Tama backend sent a response the app could not read."
        case .streamClosedEarly:
            "The Tama backend closed the stream before reporting a result."
        case let .refused(message):
            message
        case let .unreadableOutput(operation, reason):
            "\(operation) produced an answer Tama could not parse: \(reason)"
        case let .cancelled(operation):
            "\(operation) was cancelled."
        }
    }
}

/// Locates an executable by name: the PATH entries first, then the
/// well-known install locations.
func executableCandidates(named name: String) -> [URL] {
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
