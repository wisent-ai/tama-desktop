import Darwin
import Foundation

enum TamaBackendError: LocalizedError {
    case backendMissing(String)
    case startFailed(String)
    /// The request process ended without printing its answer: it was killed,
    /// or crashed, and its own stderr says why.
    case endedWithoutAnswer(Int32, String)
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
        case let .endedWithoutAnswer(status, detail):
            detail.isEmpty
                ? "The Tama backend ended with status \(status) before it answered."
                : "The Tama backend ended with status \(status) before it answered: \(detail)"
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
    /// A pipe is read 64 KiB at a time.
    private static let readChunkBytes = 64 * 1024

    private(set) var data = Data()
    private(set) var wasTruncated = false
    private(set) var readError: String?

    func drain(_ handle: FileHandle, retaining limit: Int) {
        let chunkSize = Self.readChunkBytes
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
