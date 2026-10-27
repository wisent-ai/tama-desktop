import Darwin
import Foundation

enum TamaBackendError: LocalizedError {
    case backendMissing(String)
    case startFailed(String)
    /// The request process ended without printing its answer: it was killed,
    /// or crashed, and its own stderr says why.
    case endedWithoutAnswer(Int32, String)
    case inputFailed(Int32, String)
    case unexpectedExit(String)
    case refused(String)
    /// Output-read or event-protocol failure already reported by the transport.
    case outputFailed(String, String)
    case unreadableOutput(String, String)
    case cancelled(String)

    var errorDescription: String? {
        switch self {
        case .backendMissing(let path):
            "The Tama backend is missing from this build at \(path). Rebuild with Scripts/build-app.sh."
        case .startFailed(let detail):
            detail.isEmpty
                ? "The Tama backend did not start."
                : "The Tama backend did not start: \(detail)"
        case .endedWithoutAnswer(let status, let detail):
            detail.isEmpty
                ? "The Tama backend ended with status \(status) before it answered."
                : "The Tama backend ended with status \(status) before it answered: \(detail)"
        case .inputFailed(_, let detail):
            "The Tama request input failed: \(detail)"
        case .unexpectedExit(let detail):
            "The Tama request process exit disagrees with its answer: \(detail)"
        case .refused(let message):
            message
        case .outputFailed(let operation, let reason):
            "\(operation) request output failed: \(reason)"
        case .unreadableOutput(let operation, let reason):
            "\(operation) produced an answer Tama could not parse: \(reason)"
        case .cancelled(let operation):
            "\(operation) was cancelled."
        }
    }
}

final class DataBox: @unchecked Sendable {
    private(set) var data = Data()
    private(set) var readError: String?

    /// Reads `handle` until its writer closes it and keeps everything it
    /// wrote; `readError` says why the read failed.
    func drain(_ handle: FileHandle) {
        do {
            if let all = try handle.readToEnd() {
                data = all
            }
        } catch {
            readError = error.localizedDescription
        }
    }
}

func signalProcessTree(rootPID: pid_t, signal: Int32) {
    var descendants: [pid_t] = []
    var seen = Set<pid_t>()

    // libproc's proc_listchildpids answers a count of PIDs (it divides the
    // kernel's byte count by sizeof(int)), both when sizing with no buffer and
    // when filling one; the buffer size it takes is in bytes.
    func collectChildren(of parent: pid_t) {
        let available = proc_listchildpids(parent, nil, .zero)
        guard available > .zero else { return }
        var children = [pid_t](repeating: pid_t(), count: Int(available))
        let listed = children.withUnsafeMutableBytes { buffer in
            proc_listchildpids(parent, buffer.baseAddress, Int32(buffer.count))
        }
        guard listed > .zero else { return }
        for child in children.prefix(min(children.count, Int(listed)))
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
