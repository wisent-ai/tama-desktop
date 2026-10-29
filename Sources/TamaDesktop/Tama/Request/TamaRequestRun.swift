import CoreFoundation
import Darwin
import Foundation

/// Lock-guarded state of one request: the stdout line buffer, the events read
/// so far, which pipes are still open, the exit status, and the once-only
/// resume of the caller.
final class RequestRun: @unchecked Sendable {
    enum Stream { case input, stdout, stderr }

    private let lock = NSLock()
    // Serialize stdout delivery while keeping callbacks outside the state lock:
    // a callback may cancel the calling task and immediately enter stop().
    private let outputDelivery = NSLock()
    private let onEvent: (@Sendable (TamaJobEvent) -> Void)?
    private var continuation: CheckedContinuation<TamaExchange, Error>?
    private var pending = Data()
    private var end: TamaExchange.End?
    private var stdoutText = ""
    private var stderrText = ""
    private var processError = Data()
    private var unreadableEvents: [String] = []
    private var inputErrors: [String] = []
    private var outputErrors: [String] = []
    private var open: Set<Stream> = [.input, .stdout, .stderr]
    private var exitStatus: Int32?
    private var terminationReason: Process.TerminationReason?
    private var processID: pid_t?
    private var stopped = false
    private var cancelled = false
    // The output readers are installed after launch; a cancelled exit closes
    // them only once both are installed, so no reader is ever installed on a
    // handle that cancellation has already closed.
    private var readersReady = false
    private var onCancelledExit: (@Sendable (RequestRun) -> Void)?

    init(
        onEvent: (@Sendable (TamaJobEvent) -> Void)? = nil,
        onCancelledExit: @escaping @Sendable (RequestRun) -> Void
    ) {
        self.onEvent = onEvent
        self.onCancelledExit = onCancelledExit
    }

    func attach(_ continuation: CheckedContinuation<TamaExchange, Error>) -> Bool {
        let accepted = lock.withLock {
            if cancelled { return false }
            self.continuation = continuation
            return true
        }
        if !accepted { continuation.resume(throwing: CancellationError()) }
        return accepted
    }

    func started(_ pid: pid_t) {
        let stopNow = lock.withLock { () -> Bool in
            processID = pid
            return stopped && exitStatus == nil
        }
        if stopNow { signalProcessTree(rootPID: pid, signal: SIGTERM) }
    }

    /// Cancellation settles after the owned process exits. Its output readers
    /// are then closed locally rather than waiting on inherited writers.
    func stop() {
        lock.withLock { cancelled = true }
        terminate()
        settleCancelledExit()
    }

    private func settleCancelledExit() {
        let close = lock.withLock { () -> (@Sendable (RequestRun) -> Void)? in
            guard cancelled, exitStatus != nil, readersReady else { return nil }
            defer { onCancelledExit = nil }
            return onCancelledExit
        }
        close?(self)
    }

    /// Both output readers are installed: from here a cancelled exit may close
    /// them, and one that already happened closes them now.
    func readersInstalled() {
        lock.withLock { readersReady = true }
        settleCancelledExit()
    }

    /// Input/output failures still drain the other streams and retain their
    /// observed causes; stopping a failed child is not a user cancellation.
    private func terminate() {
        let pid = lock.withLock { () -> pid_t? in
            stopped = true
            guard exitStatus == nil else { return nil }
            return processID
        }
        if let pid { signalProcessTree(rootPID: pid, signal: SIGTERM) }
    }

    /// Takes stdout as it arrives and handles every complete line as one event.
    func appendOutput(_ data: Data) {
        outputDelivery.withLock {
            let events = lock.withLock {
                var events: [TamaJobEvent] = []
                pending.append(data)
                var start = pending.startIndex
                while let newline = pending[start...].firstIndex(of: UInt8(ascii: "\n")) {
                    if let event = handle(Data(pending[start..<newline])) {
                        events.append(event)
                    }
                    start = pending.index(after: newline)
                }
                if start != pending.startIndex {
                    pending.removeSubrange(..<start)
                }
                return events
            }
            for event in events { onEvent?(event) }
        }
    }

    func appendError(_ data: Data) {
        lock.withLock {
            processError.append(data)
        }
    }

    func inputFailed(_ cause: String) {
        lock.withLock { inputErrors.append(cause) }
        terminate()
    }

    func outputFailed(_ cause: String) {
        lock.withLock { outputErrors.append(cause) }
        terminate()
    }

    /// Finalize the last stdout record under the same lock before recording EOF.
    func closed(_ stream: Stream) {
        if case .stdout = stream {
            outputDelivery.withLock {
                let event = lock.withLock {
                    let event = pending.isEmpty ? nil : handle(pending)
                    pending.removeAll()
                    return event
                }
                if let event { onEvent?(event) }
                finishIfDone { open.remove(stream) }
            }
        } else {
            finishIfDone { open.remove(stream) }
        }
    }

    func exited(_ code: Int32, reason: Process.TerminationReason) {
        finishIfDone {
            exitStatus = code
            terminationReason = reason
        }
        settleCancelledExit()
    }

    func fail(_ error: Error) {
        let waiting = lock.withLock { () -> CheckedContinuation<TamaExchange, Error>? in
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume(throwing: error)
    }

    /// Called with the lock held.
    private func handle(_ line: Data) -> TamaJobEvent? {
        if case .some = end {
            unreadableEvents.append(
                "an event after the terminal answer: \(String(decoding: line, as: UTF8.self))")
            return nil
        }
        let text = String(decoding: line, as: UTF8.self)
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: line)
        } catch {
            unreadableEvents.append("not JSON (\(String(reflecting: error))): \(text)")
            return nil
        }
        guard let event = parsed as? [String: Any], let type = event["type"] as? String else {
            unreadableEvents.append("not an event object with a type: \(text)")
            return nil
        }
        switch type {
        case "log":
            guard let chunk = event["chunk"] as? String else {
                unreadableEvents.append("a log event without its chunk: \(text)")
                return nil
            }
            let stream = event["stream"] as? String
            switch stream {
            case "stderr":
                stderrText += chunk
            case "stdout":
                stdoutText += chunk
            default:
                unreadableEvents.append("a log event without a supported stream: \(text)")
                return nil
            }
            if let stream, onEvent != nil {
                return TamaJobEvent(
                    processID: processID, stream: stream, chunk: chunk)
            }
        case "response":
            finish(event, text: text, response: true)
        case "result":
            finish(event, text: text, response: false)
        default:
            unreadableEvents.append("an unknown event type \(type): \(text)")
        }
        return nil
    }

    /// Called with the lock held: the answer or job end an event carries,
    /// or why it cannot be read.
    private func finish(_ event: [String: Any], text: String, response: Bool) {
        guard let number = event["status"] as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID(),
            number.compare(NSNumber(value: number.intValue)) == .orderedSame
        else {
            unreadableEvents.append("an answer event without an integer status: \(text)")
            return
        }
        let status = number.intValue
        guard let json = event["json"] else {
            unreadableEvents.append("an answer event without its json document: \(text)")
            return
        }
        let document: Data
        do {
            document = try JSONSerialization.data(
                withJSONObject: json, options: [.fragmentsAllowed])
        } catch {
            let cause = String(reflecting: error)
            unreadableEvents.append(
                "an answer whose json cannot be encoded (\(cause)): \(text)")
            return
        }
        end =
            response
            ? .response(status: status, document: document)
            : .result(status: status, document: document)
    }

    /// Input must be settled, the process exited and both output pipes closed
    /// before answering, so neither a late input failure nor output is lost.
    private func finishIfDone(_ change: () -> Void) {
        let ready = lock.withLock {
            () -> (CheckedContinuation<TamaExchange, Error>, Result<TamaExchange, Error>)? in
            change()
            guard open.isEmpty, let exitStatus, let terminationReason,
                let waiting = continuation
            else { return nil }
            continuation = nil
            if cancelled { return (waiting, .failure(CancellationError())) }
            return (
                waiting,
                .success(
                    TamaExchange(
                        end: end,
                        stdoutText: stdoutText,
                        stderrText: stderrText,
                        processError: String(decoding: processError, as: UTF8.self),
                        exitStatus: exitStatus,
                        terminationReason: terminationReason,
                        unreadableEvents: unreadableEvents,
                        inputErrors: inputErrors,
                        outputErrors: outputErrors
                    ))
            )
        }
        guard let ready else { return }
        ready.0.resume(with: ready.1)
    }
}
