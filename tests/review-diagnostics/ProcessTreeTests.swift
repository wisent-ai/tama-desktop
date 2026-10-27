import Darwin
import Foundation
import XCTest
@testable import TamaDesktop

/// Actual Darwin processes and the product helper, not a substitute backend.
final class ProcessTreeTests: XCTestCase, @unchecked Sendable {
    private struct ObservationFailure: Error, CustomStringConvertible {
        let description: String
    }

    private func readPacket(_ handle: FileHandle, count: Int) throws -> Data {
        var received = Data()
        while received.count < count {
            guard let next = try handle.read(upToCount: count - received.count), !next.isEmpty else { break }
            received.append(next)
        }
        return received
    }

    private func children(of parent: pid_t) throws -> [pid_t] {
        errno = .zero
        let capacity = proc_listchildpids(parent, nil, .zero)
        let queryErrno = errno
        guard capacity > .zero else {
            throw ObservationFailure(description:
                "proc_listchildpids(\(parent), nil) returned \(capacity), errno \(queryErrno)")
        }
        var pids = [pid_t](repeating: pid_t(), count: Int(capacity))
        errno = .zero
        let count = pids.withUnsafeMutableBytes { buffer in
            proc_listchildpids(parent, buffer.baseAddress, Int32(buffer.count))
        }
        let fillErrno = errno
        guard count > .zero, Int(count) <= pids.count else {
            throw ObservationFailure(description:
                "proc_listchildpids(\(parent), buffer) returned \(count) PID entries for capacity \(pids.count), errno \(fillErrno)")
        }
        return Array(pids.prefix(Int(count))).filter { $0 > .zero }
    }

    private func writePacket(_ bytes: Data, to handle: FileHandle) -> (count: Int, error: Int32) {
        errno = .zero
        let count = bytes.withUnsafeBytes { buffer in
            Darwin.write(handle.fileDescriptor, buffer.baseAddress, buffer.count)
        }
        return (count, errno)
    }

    func testSignalProcessTreeStopsAnActuallyConsumingDescendant() throws {
        let (_, root, _) = try fixture()
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/time")
        process.arguments = ["/bin/cat"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        var observation: [String: Any] = [
            "surface": "native process-tree helper with real time and cat; not rendered UI or request transport",
            "command": ["/usr/bin/time", "/bin/cat"], "verdict": "failed"
        ]
        if let cause = TamaRequestProcess.protectInputPipe(input.fileHandleForWriting) {
            throw ObservationFailure(description: cause)
        }
        try process.run()
        observation["rootPID"] = process.processIdentifier
        defer {
            // EOF ends cat even when the broken helper killed only its parent.
            do { try input.fileHandleForWriting.close() }
            catch {
                observation["inputCloseFailure"] = String(reflecting: error)
                XCTFail("The real fixture input could not close: \(error)")
            }
            process.waitUntilExit()
            observation["rootExitStatus"] = process.terminationStatus
            do {
                if let remaining = try output.fileHandleForReading.readToEnd() {
                    observation["stdoutAfterInputClose"] = remaining.base64EncodedString()
                }
                if let diagnostics = try errors.fileHandleForReading.readToEnd() {
                    observation["processStderr"] = String(decoding: diagnostics, as: UTF8.self)
                }
            } catch {
                observation["finalReadFailure"] = String(reflecting: error)
                XCTFail("The real fixture's final output could not be inspected: \(error)")
            }
            do {
                try JSONSerialization.data(withJSONObject: observation, options: [.prettyPrinted, .sortedKeys])
                    .write(to: root.appendingPathComponent("process-tree.json"))
            } catch {
                XCTFail("Cannot retain process-tree observation at \(root.path): \(error)")
            }
        }
        let first = Data((UUID().uuidString + "\n").utf8)
        let sent = writePacket(first, to: input.fileHandleForWriting)
        observation["initialWriteCount"] = sent.count
        observation["initialWriteErrno"] = sent.error
        guard sent.count == first.count else {
            throw ObservationFailure(description:
                "Initial consumer write returned \(sent.count) for \(first.count) bytes, errno \(sent.error)")
        }
        let echoed = try readPacket(output.fileHandleForReading, count: first.count)
        observation["initialPacket"] = first.base64EncodedString()
        observation["initialEcho"] = echoed.base64EncodedString()
        guard echoed == first else {
            throw ObservationFailure(description: "The actual child did not consume and echo its first complete UUID packet")
        }
        let measuredChildren = try children(of: process.processIdentifier)
        guard !measuredChildren.isEmpty else {
            throw ObservationFailure(description: "The live timing process has no measured utility child")
        }
        observation["measuredChildren"] = measuredChildren
        signalProcessTree(rootPID: process.processIdentifier, signal: SIGKILL)
        process.waitUntilExit()
        let probe = Data((UUID().uuidString + "\n").utf8)
        let written = writePacket(probe, to: input.fileHandleForWriting)
        observation["postStopPacket"] = probe.base64EncodedString()
        observation["postStopWriteCount"] = written.count
        observation["postStopWriteErrno"] = written.error
        guard written.count == probe.count || (written.count < .zero && written.error == EPIPE) else {
            throw ObservationFailure(description:
                "Post-stop write returned \(written.count) for \(probe.count) bytes, errno \(written.error)")
        }
        let after = try readPacket(output.fileHandleForReading, count: probe.count)
        observation["postStopEcho"] = after.base64EncodedString()
        observation["descendantStillConsumes"] = after == probe
        guard after.isEmpty else {
            throw ObservationFailure(description:
                "The root exited but its actual descendant still consumes input; received \(after.count) post-stop bytes")
        }
        observation["verdict"] = "passed"
    }
}
