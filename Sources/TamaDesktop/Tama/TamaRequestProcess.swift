import AppKit
import Darwin
import Foundation

/// How the app runs `tama request <operation>`: the binary, the release it
/// reads, and the environment it inherits.
struct TamaCommand: Sendable {
    let executable: URL
    /// The release every operation reads; nil leaves the choice to the binary.
    let root: URL?
    let environment: [String: String]

    /// The binary sealed into this build's hook release, reading that
    /// release. A DEBUG build may point at a workspace binary instead.
    static func bundled() throws -> TamaCommand {
        let root = try HookCatalogClient().hookReleaseRoot()
        var environment = ProcessInfo.processInfo.environment
        if let stateDirectory = cleanStateDirectory() {
            environment["TAMA_CLEAN_STATE_DIR"] = stateDirectory
        }
        return TamaCommand(
            executable: try executableURL(root: root),
            root: root,
            environment: environment
        )
    }

    func arguments(operation: String) -> [String] {
        var arguments = ["request", operation]
        if let root { arguments += ["--root", root.path] }
        return arguments
    }

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
            .appendingPathComponent("tama")
        guard manager.isExecutableFile(atPath: bundled.path) else {
            throw TamaBackendError.backendMissing(bundled.path)
        }
        return bundled
    }

    /// Cleanup journals and locks cannot live inside the read-only release
    /// directory, so every request gets the same state directory the
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

/// What one request printed, and how it ended.
struct TamaExchange: Sendable {
    /// The last event: the answer of a bounded operation, or the end of a job.
    enum End: Sendable {
        case response(status: Int, document: Data)
        case result(status: Int, document: Data)
    }

    let end: End?
    /// The job's own output, from its `log` events, by stream.
    let stdoutText: String
    let stderrText: String
    /// What the process wrote to its own stderr, outside the event stream: a
    /// crash reports there and nowhere else.
    let processError: String
    let exitStatus: Int32
}

/// One `tama request <operation>` process per operation.
///
/// The app used to start `tama serve --port 0` on first use and keep it
/// for as long as it ran: a second resident Tama process with its own
/// loopback port. Every operation is now one finite process. The body goes to
/// its stdin as one JSON document, and every event it prints on stdout is read
/// until the process exits. Cancelling the calling task or quitting the app
/// ends the process and everything it started, because nobody is left to read
/// its answer.
enum TamaRequestProcess {
    static func run(_ command: TamaCommand, operation: String, body: Data) async throws -> TamaExchange {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = command.executable
        process.arguments = command.arguments(operation: operation)
        process.environment = command.environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        let run = RequestRun()
        let quit = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { _ in
            run.stop()
        }
        defer { NotificationCenter.default.removeObserver(quit) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                run.attach(continuation)
                output.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        handle.readabilityHandler = nil
                        run.closed(.stdout)
                    } else {
                        run.appendOutput(data)
                    }
                }
                errors.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        handle.readabilityHandler = nil
                        run.closed(.stderr)
                    } else {
                        run.appendError(data)
                    }
                }
                process.terminationHandler = { finished in
                    run.exited(finished.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    output.fileHandleForReading.readabilityHandler = nil
                    errors.fileHandleForReading.readabilityHandler = nil
                    run.fail(TamaBackendError.startFailed(error.localizedDescription))
                    return
                }
                run.started(process.processIdentifier)
                send(body, to: input.fileHandleForWriting)
            }
        } onCancel: {
            run.stop()
        }
    }

    /// Writes the body and closes the pipe, so the process reads one whole
    /// document and then the end of its input. The process reads its input to
    /// the end before it writes anything, and both of its output pipes are
    /// already being drained, so the write cannot wait on it. A process that
    /// exits before reading makes the write fail instead of raising a SIGPIPE
    /// that would end the app; the exit itself is what the run then reports.
    private static func send(_ body: Data, to handle: FileHandle) {
        _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
        try? handle.write(contentsOf: body)
        try? handle.close()
    }
}

/// Lock-guarded state of one request: the stdout line buffer, the events read
/// so far, which pipes are still open, the exit status, and the once-only
/// resume of the caller.
private final class RequestRun: @unchecked Sendable {
    enum Stream { case stdout, stderr }

    /// How much of the process's own stderr is kept for a failure sentence.
    private static let processErrorCharacters = 2000

    private let lock = NSLock()
    private var continuation: CheckedContinuation<TamaExchange, Error>?
    private var pending = Data()
    private var end: TamaExchange.End?
    private var stdoutText = ""
    private var stderrText = ""
    private var processError = ""
    private var open: Set<Stream> = [.stdout, .stderr]
    private var exitStatus: Int32?
    private var processID: pid_t?
    private var stopped = false

    func attach(_ continuation: CheckedContinuation<TamaExchange, Error>) {
        lock.withLock { self.continuation = continuation }
    }

    func started(_ pid: pid_t) {
        let stopNow = lock.withLock { () -> Bool in
            processID = pid
            return stopped
        }
        if stopNow { signalProcessTree(rootPID: pid, signal: SIGTERM) }
    }

    /// Ends the process and everything it started. Before it has started, the
    /// start itself ends it.
    func stop() {
        let pid = lock.withLock { () -> pid_t? in
            stopped = true
            return processID
        }
        if let pid { signalProcessTree(rootPID: pid, signal: SIGTERM) }
    }

    /// Takes stdout as it arrives and handles every complete line as one event.
    func appendOutput(_ data: Data) {
        lock.withLock {
            pending.append(data)
            while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                handle(Data(pending[..<newline]))
                pending = Data(pending[pending.index(after: newline)...])
            }
        }
    }

    func appendError(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        lock.withLock {
            processError = String((processError + text).suffix(Self.processErrorCharacters))
        }
    }

    func closed(_ stream: Stream) {
        finishIfDone { open.remove(stream) }
    }

    func exited(_ code: Int32) {
        finishIfDone { exitStatus = code }
    }

    func fail(_ error: Error) {
        let waiting = lock.withLock { () -> CheckedContinuation<TamaExchange, Error>? in
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume(throwing: error)
    }

    /// Called with the lock held.
    private func handle(_ line: Data) {
        guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = event["type"] as? String
        else { return }
        switch type {
        case "log":
            let chunk = event["chunk"] as? String ?? ""
            if event["stream"] as? String == "stderr" {
                stderrText += chunk
            } else {
                stdoutText += chunk
            }
        case "response", "result":
            let status = (event["status"] as? NSNumber)?.intValue ?? .zero
            let document = event["json"].flatMap {
                try? JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed])
            } ?? Data()
            end = type == "response"
                ? .response(status: status, document: document)
                : .result(status: status, document: document)
        default:
            return
        }
    }

    /// The run is over once the process exited and both pipes reached end of
    /// file, so no event written just before the exit is lost.
    private func finishIfDone(_ change: () -> Void) {
        let ready = lock.withLock { () -> (CheckedContinuation<TamaExchange, Error>, TamaExchange)? in
            change()
            guard open.isEmpty, let exitStatus, let waiting = continuation else { return nil }
            continuation = nil
            return (waiting, TamaExchange(
                end: end,
                stdoutText: stdoutText,
                stderrText: stderrText,
                processError: processError.trimmingCharacters(in: .whitespacesAndNewlines),
                exitStatus: exitStatus
            ))
        }
        guard let ready else { return }
        ready.0.resume(returning: ready.1)
    }
}
