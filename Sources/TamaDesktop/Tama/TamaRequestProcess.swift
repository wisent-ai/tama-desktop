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
                !override.isEmpty
            {
                let url = URL(fileURLWithPath: override).standardizedFileURL
                guard manager.isExecutableFile(atPath: url.path) else {
                    throw TamaBackendError.backendMissing(url.path)
                }
                return url
            }
        #endif
        let bundled =
            root
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
    let terminationReason: Process.TerminationReason
    /// Stdout lines that were not a readable event, each with why: not JSON,
    /// not an event object, or an event missing what its type needs. They
    /// used to be dropped, so a mangled answer read as "ended before it
    /// answered".
    let unreadableEvents: [String]
    /// Failures delivering or closing the request input, separate from stderr.
    let inputErrors: [String]
    /// Operating-system failures reading the process's output pipes.
    let outputErrors: [String]

    var diagnostics: String {
        let terminal = switch end {
        case .response(let status, let document):
            "bounded response status: \(status)\nbounded response document:\n\(String(decoding: document, as: UTF8.self))"
        case .result(let status, let document):
            "job result status: \(status)\njob result document:\n\(String(decoding: document, as: UTF8.self))"
        case nil:
            "no terminal event was observed"
        }
        return """
        \(terminal)
        request process exit status: \(exitStatus)
        request process termination reason: \(terminationReason) (\(terminationReason.rawValue))
        request input failures:
        \(inputErrors.joined(separator: "\n"))
        request output failures:
        \(outputErrors.joined(separator: "\n"))
        events that could not be read:
        \(unreadableEvents.joined(separator: "\n"))
        request process standard error:
        \(processError)
        streamed job standard output:
        \(stdoutText)
        streamed job standard error:
        \(stderrText)
        """
    }
}

/// An observed job event, delivered before waiting for the terminal result:
/// first stream "process" with chunk "launched" once the process is started,
/// then every log event with its stream ("stdout" or "stderr") and text.
/// The process identity is present once launch has been recorded.
struct TamaJobEvent: Sendable {
    let processID: Int32?
    let stream: String
    let chunk: String
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
    static func run(
        _ command: TamaCommand, operation: String, body: Data,
        onEvent: (@Sendable (TamaJobEvent) -> Void)? = nil
    ) async throws -> TamaExchange {
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
        let run = RequestRun(onEvent: onEvent) { run in
            // A log callback may initiate cancellation while delivering stdout.
            // Close on another queue so settling stdout cannot reenter its lock.
            DispatchQueue.global().async {
                closeCancelledOutput(
                    output.fileHandleForReading, stream: .stdout,
                    operation: operation, run: run)
                closeCancelledOutput(
                    errors.fileHandleForReading, stream: .stderr,
                    operation: operation, run: run)
            }
        }
        let readCount = Int(getpagesize())
        let quit = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { _ in
            run.stop()
        }
        defer {
            NotificationCenter.default.removeObserver(quit)
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard run.attach(continuation) else { return }
                process.terminationHandler = { finished in
                    run.exited(finished.terminationStatus, reason: finished.terminationReason)
                }
                do {
                    try process.run()
                } catch {
                    run.fail(TamaBackendError.startFailed(String(reflecting: error)))
                    return
                }
                let pid = process.processIdentifier
                run.started(pid)
                // The consumer learns the launched process before its output
                // readers exist; a cancellation it starts here is settled once
                // both readers are installed (`readersInstalled`).
                onEvent?(TamaJobEvent(processID: pid, stream: "process", chunk: "launched"))
                output.fileHandleForReading.readabilityHandler = { handle in
                    do {
                        if let data = try handle.read(upToCount: readCount), !data.isEmpty {
                            run.appendOutput(data)
                            return
                        }
                    } catch {
                        run.outputFailed(
                            "request \(operation) standard output not read: \(String(reflecting: error))")
                    }
                    handle.readabilityHandler = nil
                    run.closed(.stdout)
                }
                errors.fileHandleForReading.readabilityHandler = { handle in
                    do {
                        if let data = try handle.read(upToCount: readCount), !data.isEmpty {
                            run.appendError(data)
                            return
                        }
                    } catch {
                        run.outputFailed(
                            "request \(operation) standard error not read: \(String(reflecting: error))")
                    }
                    handle.readabilityHandler = nil
                    run.closed(.stderr)
                }
                run.readersInstalled()
                send(body, to: input.fileHandleForWriting, operation: operation, run: run)
            }
        } onCancel: {
            run.stop()
        }
    }

    private static func closeCancelledOutput(
        _ handle: FileHandle, stream: RequestRun.Stream,
        operation: String, run: RequestRun
    ) {
        handle.readabilityHandler = nil
        defer { run.closed(stream) }
        do {
            try handle.close()
        } catch {
            run.outputFailed(
                "request \(operation) \(stream) output not closed after cancellation: \(String(reflecting: error))")
        }
    }

    /// Enables and verifies per-pipe protection; only a failure allocates a diagnostic.
    static func protectInputPipe(_ handle: FileHandle) -> String? {
        errno = .zero
        // C TRUE: https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/boolean.h
        let result = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
        let setErrno = errno
        errno = .zero
        let observed = fcntl(handle.fileDescriptor, F_GETNOSIGPIPE)
        let observedErrno = errno
        guard result == .zero, observed > .zero else {
            return "fcntl(F_SETNOSIGPIPE) returned \(result), errno \(setErrno); "
                + "fcntl(F_GETNOSIGPIPE) returned \(observed), errno \(observedErrno)"
        }
        return nil
    }

    /// Delivers one document and EOF only through a verified protected pipe.
    /// Input failures stop the request and remain separate from its stderr;
    /// completion waits for input settlement and both output streams.
    private static func send(
        _ body: Data, to handle: FileHandle, operation: String, run: RequestRun
    ) {
        defer { run.closed(.input) }
        if let cause = protectInputPipe(handle) {
            run.inputFailed("request \(operation) input pipe protection failed: \(cause)")
        } else {
            do {
                try handle.write(contentsOf: body)
            } catch {
                run.inputFailed(
                    "request \(operation) body not written: \(String(reflecting: error))")
            }
        }
        do {
            try handle.close()
        } catch {
            run.inputFailed(
                "request \(operation) input not closed: \(String(reflecting: error))")
        }
    }
}
