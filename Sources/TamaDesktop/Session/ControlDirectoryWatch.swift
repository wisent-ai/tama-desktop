import Darwin
import Foundation

/// Wakes when the session-control directory is written to, or when one of the
/// watched agent processes exits: the two events that can change a session
/// list or a pending request's answer. A caller blocks for the next event, and
/// every event is counted, so a change between arming and blocking is not lost.
final class ControlDirectoryWatch: @unchecked Sendable {
    private let changed = DispatchSemaphore(value: 0)
    private let queue = DispatchQueue(label: "ai.wisent.tama.session-control.watch")
    private let directorySource: DispatchSourceFileSystemObject
    private var processSources: [DispatchSourceProcess] = []

    init(directory: URL, processes: [Int32] = []) throws {
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw SessionControlError.directoryUnwatchable(
                directory.path,
                String(cString: strerror(errno))
            )
        }
        directorySource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: queue
        )
        directorySource.setEventHandler { [changed] in changed.signal() }
        directorySource.setCancelHandler { close(descriptor) }
        directorySource.resume()
        for pid in processes where pid > 0 {
            let source = DispatchSource.makeProcessSource(
                identifier: pid_t(pid),
                eventMask: .exit,
                queue: queue
            )
            source.setEventHandler { [changed] in changed.signal() }
            source.resume()
            processSources.append(source)
        }
    }

    /// Blocks until the next directory write or watched process exit.
    func next() {
        changed.wait()
    }

    /// Releases a blocked `next()` without an event, so its owner can stop.
    func interrupt() {
        changed.signal()
    }

    deinit {
        directorySource.cancel()
        processSources.forEach { $0.cancel() }
    }
}
