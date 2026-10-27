import Darwin
import Foundation
import XCTest
@testable import TamaDesktop

/// Streamed jobs against the real backend's `violations/scan` over this
/// checkout: one that runs to its end, and one the caller cancels.
final class StreamedJobTests: XCTestCase, @unchecked Sendable {
    private func checkout(of root: URL) -> URL {
        root.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// A real scan streams one log event per step, many per pipe read and
    /// some split across reads; every one is read, none is left unreadable,
    /// and the job ends with its result.
    func testCompletedStreamedJobReadsEveryEvent() async throws {
        let (client, root, _) = try fixture()
        let result = try await client.job(
            "violations/scan", body: ["repo": checkout(of: root).path, "mode": "size-only"],
            describing: "Scan this checkout")
        try Data(result.failureSentence.utf8).write(to: root.appendingPathComponent("scan.txt"))
        guard case .result = result.exchange.end else {
            return XCTFail("The scan ended without its result: \(result.failureSentence)")
        }
        XCTAssertEqual(result.exchange.terminationReason, .exit, result.failureSentence)
        XCTAssertEqual(Int(result.exchange.exitStatus), result.status, result.failureSentence)
        XCTAssertEqual(result.exchange.unreadableEvents, [], result.failureSentence)
        XCTAssertEqual(result.exchange.outputErrors, [], result.failureSentence)
        // The scan logs every step on its stderr channel (`log` events with
        // stream "stderr"); stdout carries no log of its own.
        XCTAssertFalse(result.exchange.stderrText.isEmpty, "The scan streamed no log event: \(result.failureSentence)")
    }

    /// A real scan result read by a consumer whose schema it does not match
    /// is refused with the decoder's cause and the whole exchange: the
    /// result document, the process exit and the streamed output.
    func testIncompatibleStreamedResultKeepsItsExchange() async throws {
        let (client, root, _) = try fixture()
        let result = try await client.job(
            "violations/scan", body: ["repo": checkout(of: root).path, "mode": "size-only"],
            describing: "Scan this checkout")
        do {
            let _: JudgementInspection = try result.decoded(
                as: JudgementInspection.self, describing: "Read a scan as a review")
            XCTFail("A scan report must not become a review inspection")
        } catch let error as TamaBackendError {
            try Data(error.localizedDescription.utf8)
                .write(to: root.appendingPathComponent("streamed-mismatch.txt"))
            guard case .unreadableOutput(let context, let cause) = error else {
                return XCTFail("Expected a streamed document mismatch, observed: \(error)")
            }
            XCTAssertTrue(context.contains("violations/scan"), context)
            XCTAssertTrue(cause.contains("keyNotFound"), cause)
            XCTAssertTrue(cause.contains("job result document:"), cause)
            XCTAssertTrue(cause.contains("\"repos\""), cause)
            XCTAssertTrue(cause.contains("request process exit status:"), cause)
            XCTAssertTrue(cause.contains("streamed job standard error:"), cause)
        }
    }

    /// A streamed job the caller cancels ends as the operator's cancellation,
    /// not as a failure and not with a result.
    func testCancelledStreamedJobEndsAsCancellation() async throws {
        let (client, root, _) = try fixture()
        let repository = checkout(of: root).path
        let job = Task {
            try await client.job(
                "violations/scan", body: ["repo": repository, "mode": "size-only"],
                describing: "Scan this checkout")
        }
        job.cancel()
        do {
            let result = try await job.value
            XCTFail("A cancelled job returned a result: \(result.failureSentence)")
        } catch let error as TamaBackendError {
            try Data(error.localizedDescription.utf8).write(to: root.appendingPathComponent("cancelled.txt"))
            guard case .cancelled(let description) = error else {
                return XCTFail("Expected the operator's cancellation, observed: \(error)")
            }
            XCTAssertEqual(description, "Scan this checkout")
        }
    }

    /// A running job cancelled from inside its first real log event ends as
    /// the operator's cancellation, and the process that sent the event is
    /// gone once the job settles: no timer decides when it is cancelled.
    func testRunningStreamedJobCancelledOnItsFirstEvent() async throws {
        let observed = try await cancelScan(on: { $0.stream != "process" }, keeping: "running-cancellation.json")
        XCTAssertNotEqual(observed.event.stream, "process", "\(observed.record)")
        XCTAssertFalse(observed.event.chunk.isEmpty, "\(observed.record)")
    }

    /// A job cancelled from inside its launch event, after the process started
    /// and before its output readers exist, settles as the operator's
    /// cancellation with its process gone; the cancellation runs in the job's
    /// own task, so it lands in that interval and not after it.
    func testLaunchedStreamedJobCancelledBeforeItsReadersExist() async throws {
        let observed = try await cancelScan(on: { $0.stream == "process" }, keeping: "launch-cancellation.json")
        XCTAssertEqual(observed.event.chunk, "launched", "\(observed.record)")
        XCTAssertEqual(observed.cancelledBy, "the job's own task inside the event", "\(observed.record)")
    }

    /// Runs a real scan, cancels it on the first event `matching` accepts,
    /// keeps what was observed in `file`, and requires the operator's
    /// cancellation and the event's process gone once the job settled.
    private func cancelScan(
        on matching: @escaping @Sendable (TamaJobEvent) -> Bool, keeping file: String
    ) async throws -> (event: TamaJobEvent, cancelledBy: String?, record: [String: Any]) {
        let (client, root, _) = try fixture()
        let repository = checkout(of: root).path
        let first = FirstEvent(matching: matching)
        let job = Task {
            try await client.job(
                "violations/scan", body: ["repo": repository, "mode": "size-only"],
                describing: "Scan this checkout", onEvent: { first.received($0) })
        }
        first.attach(job)
        let outcome: String
        do {
            let result = try await job.value
            outcome = "result: \(result.failureSentence)"
        } catch {
            outcome = error.localizedDescription
        }
        let event = first.event
        let probe = event?.processID.map(processProbe)
        let record: [String: Any] = [
            "eventStream": event?.stream ?? NSNull(), "eventChunk": event?.chunk ?? NSNull(),
            "processID": event?.processID.map { Int($0) } ?? NSNull(), "outcome": outcome,
            "cancelledBy": first.cancelledBy ?? NSNull(),
            "killResultAfterSettlement": probe.map { Int($0.result) } ?? NSNull(),
            "killErrnoAfterSettlement": probe.map { Int($0.errno) } ?? NSNull(),
            "killErrnoName": probe.map { String(cString: strerror($0.errno)) } ?? NSNull(),
            "pipeSettlement": "not observable: a cancelled job throws TamaBackendError.cancelled and returns no exchange"
        ]
        try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent(file))
        let received = try XCTUnwrap(event, "The scan settled before the awaited event: \(outcome)")
        XCTAssertNotNil(received.processID, "The event carried no launched process: \(record)")
        XCTAssertEqual(probe?.errno, ESRCH, "The job's process was not gone: \(record)")
        XCTAssertEqual(outcome, TamaBackendError.cancelled("Scan this checkout").localizedDescription,
                       "\(record)")
        return (received, first.cancelledBy, record)
    }

    /// Killing the actual request after launch is not task cancellation: its
    /// exchange must retain Foundation's signal reason rather than inventing
    /// a normal exit from the integer status.
    func testSignalTerminatedRequestRetainsItsObservedReason() async throws {
        let (client, root, _) = try fixture()
        let command = try XCTUnwrap(client.command)
        let body = try JSONSerialization.data(withJSONObject: [
            "repo": checkout(of: root).path, "mode": "size-only"
        ])
        let signal = SignalOnLaunch()
        let exchange: TamaExchange
        do {
            exchange = try await TamaRequestProcess.run(
                command, operation: "violations/scan", body: body,
                onEvent: { signal.received($0) })
        } catch {
            let requestFailure = error
            do {
                try Data(String(reflecting: requestFailure).utf8)
                    .write(to: root.appendingPathComponent("signal-request-error.txt"))
            } catch {
                XCTFail("Request failed: \(String(reflecting: requestFailure)); retaining its evidence also failed: \(String(reflecting: error))")
            }
            throw requestFailure
        }
        let observed = signal.observed
        let probe = observed.map { processProbe($0.pid) }
        let record: [String: Any] = [
            "processID": observed.map { Int($0.pid) } ?? NSNull(),
            "sentSignal": Int(SIGKILL),
            "signalResult": observed.map { Int($0.result) } ?? NSNull(),
            "signalErrno": observed.map { Int($0.errno) } ?? NSNull(),
            "terminationReason": String(describing: exchange.terminationReason),
            "terminationReasonRawValue": exchange.terminationReason.rawValue,
            "exitStatus": Int(exchange.exitStatus),
            "killResultAfterSettlement": probe.map { Int($0.result) } ?? NSNull(),
            "killErrnoAfterSettlement": probe.map { Int($0.errno) } ?? NSNull(),
            "exchange": exchange.diagnostics,
            "qualifiedSurface": "actual request termination reason; not terminal-result disagreement or GUI"
        ]
        try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("signal-request.json"))
        let launched = try XCTUnwrap(observed, "\(record)")
        XCTAssertEqual(launched.result, .zero, "\(record)")
        XCTAssertEqual(exchange.terminationReason, .uncaughtSignal, "\(record)")
        XCTAssertEqual(exchange.exitStatus, SIGKILL, "\(record)")
        XCTAssertEqual(probe?.errno, ESRCH, "\(record)")
    }

    /// What Darwin `kill` answers for `pid` with the POSIX null signal, which
    /// checks the process exists and delivers nothing, and the errno it left
    /// read at once: ESRCH is absence; EPERM is a process that exists.
    private func processProbe(_ pid: Int32) -> (result: Int32, errno: Int32) {
        let nullSignal = Int32()
        Darwin.errno = .zero
        let result = Darwin.kill(pid, nullSignal)
        return (result, Darwin.errno)
    }
}

/// The first event a running job delivers that `matching` accepts, and how
/// the job was cancelled on it: from inside the event when it runs in the
/// job's own task, else through the job's handle by whichever of the event
/// and the handle arrives second.
private final class FirstEvent: @unchecked Sendable {
    private let lock = NSLock()
    private let matching: @Sendable (TamaJobEvent) -> Bool
    private var first: TamaJobEvent?
    private var job: Task<TamaClient.JobResult, Error>?
    private var cancelling: String?

    init(matching: @escaping @Sendable (TamaJobEvent) -> Bool) {
        self.matching = matching
    }

    var event: TamaJobEvent? { lock.withLock { first } }
    var cancelledBy: String? { lock.withLock { cancelling } }

    func received(_ event: TamaJobEvent) {
        guard matching(event) else { return }
        let inTask = withUnsafeCurrentTask { $0 != nil }
        let (accepted, handle) = lock.withLock { () -> (Bool, Task<TamaClient.JobResult, Error>?) in
            guard first == nil else { return (false, nil) }
            first = event
            if inTask {
                cancelling = "the job's own task inside the event"
                return (true, nil)
            }
            if job != nil { cancelling = "the job's handle inside the event" }
            return (true, job)
        }
        guard accepted else { return }
        if inTask { withUnsafeCurrentTask { $0?.cancel() } }
        handle?.cancel()
    }

    func attach(_ task: Task<TamaClient.JobResult, Error>) {
        let arrived = lock.withLock { () -> Bool in
            job = task
            guard first != nil, cancelling == nil else { return false }
            cancelling = "the job's handle after the event"
            return true
        }
        if arrived { task.cancel() }
    }
}

/// Delivers one real signal at the request's launch boundary, before it can
/// consume the scan input. No task cancellation or substitute process is used.
private final class SignalOnLaunch: @unchecked Sendable {
    private let lock = NSLock()
    private var observation: (pid: Int32, result: Int32, errno: Int32)?

    var observed: (pid: Int32, result: Int32, errno: Int32)? {
        lock.withLock { observation }
    }

    func received(_ event: TamaJobEvent) {
        guard event.stream == "process", let pid = event.processID else { return }
        lock.withLock {
            guard observation == nil else { return }
            Darwin.errno = .zero
            let result = Darwin.kill(pid, SIGKILL)
            let cause = Darwin.errno
            observation = (pid, result, cause)
        }
    }
}
