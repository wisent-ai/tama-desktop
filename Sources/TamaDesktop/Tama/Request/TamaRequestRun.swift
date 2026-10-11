import Darwin
import Foundation

/// Lock-guarded state of one request: the stdout line buffer, the events read
/// so far, which pipes are still open, the exit status, and the once-only
/// resume of the caller.
final class RequestRun: @unchecked Sendable {
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
    private var unreadableEvents: [String] = []
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
        let text = String(decoding: line, as: UTF8.self)
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: line)
        } catch {
            unreadableEvents.append("not JSON (\(error.localizedDescription)): \(text)")
            return
        }
        guard let event = parsed as? [String: Any], let type = event["type"] as? String else {
            unreadableEvents.append("not an event object with a type: \(text)")
            return
        }
        switch type {
        case "log":
            guard let chunk = event["chunk"] as? String else {
                unreadableEvents.append("a log event without its chunk: \(text)")
                return
            }
            if event["stream"] as? String == "stderr" {
                stderrText += chunk
            } else {
                stdoutText += chunk
            }
        case "response":
            finish(event, text: text, response: true)
        case "result":
            finish(event, text: text, response: false)
        default:
            return
        }
    }

    /// Called with the lock held: the answer or job end an event carries,
    /// or why it cannot be read.
    private func finish(_ event: [String: Any], text: String, response: Bool) {
        guard let status = (event["status"] as? NSNumber)?.intValue else {
            unreadableEvents.append("an answer event without its status: \(text)")
            return
        }
        // An event with no `json` carries no document.
        var document = Data()
        if let json = event["json"] {
            do {
                document = try JSONSerialization.data(
                    withJSONObject: json, options: [.fragmentsAllowed])
            } catch {
                let cause = error.localizedDescription
                unreadableEvents.append("an answer whose json cannot be encoded (\(cause)): \(text)")
                return
            }
        }
        end =
            response
            ? .response(status: status, document: document)
            : .result(status: status, document: document)
    }

    /// The run is over once the process exited and both pipes reached end of
    /// file, so no event written just before the exit is lost.
    private func finishIfDone(_ change: () -> Void) {
        let ready = lock.withLock {
            () -> (CheckedContinuation<TamaExchange, Error>, TamaExchange)? in
            change()
            guard open.isEmpty, let exitStatus, let waiting = continuation else { return nil }
            continuation = nil
            return (
                waiting,
                TamaExchange(
                    end: end,
                    stdoutText: stdoutText,
                    stderrText: stderrText,
                    processError: processError.trimmingCharacters(in: .whitespacesAndNewlines),
                    exitStatus: exitStatus,
                    unreadableEvents: unreadableEvents
                )
            )
        }
        guard let ready else { return }
        ready.0.resume(returning: ready.1)
    }
}
