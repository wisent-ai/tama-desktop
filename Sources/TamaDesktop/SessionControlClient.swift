import Darwin
import Foundation

struct OMPSessionRecord: Decodable, Identifiable, Sendable {
    let schema: String
    let sessionId: String
    let controlKey: String
    let pid: Int32
    let cwd: String
    let globallyDisabled: Bool
    let disabledHookIds: [String]
    let enabledHookIds: [String]
    let updatedAt: String

    var id: String { sessionId }

    var displayName: String {
        let project = URL(fileURLWithPath: cwd).lastPathComponent
        return "\(project.isEmpty ? cwd : project) · \(sessionId.prefix(8))"
    }

    func isHookEnabled(_ hookId: String, globallyDisabled: Bool) -> Bool {
        globallyDisabled
            ? enabledHookIds.contains(hookId)
            : !disabledHookIds.contains(hookId)
    }
}

struct SessionControlClient: Sendable {
    private static let schema = "ai.wisent.tama.session-control.v1"

    func liveSessions() throws -> [OMPSessionRecord] {
        let manager = FileManager.default
        let root = try controlRoot(manager: manager)
        let urls = try manager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let decoder = JSONDecoder()
        var sessions: [OMPSessionRecord] = []
        sessions.reserveCapacity(urls.count)
        for url in urls where url.lastPathComponent.hasSuffix(".session.json") {
            guard
                let data = try? Data(contentsOf: url),
                let session = try? decoder.decode(OMPSessionRecord.self, from: data),
                session.schema == Self.schema,
                isSafeControlKey(session.controlKey)
            else {
                continue
            }
            if processIsAlive(session.pid) {
                sessions.append(session)
            } else {
                try? manager.removeItem(at: url)
            }
        }
        return sessions.sorted {
            if $0.cwd == $1.cwd { return $0.sessionId < $1.sessionId }
            return $0.cwd.localizedStandardCompare($1.cwd) == .orderedAscending
        }
    }

    func setHookEnabled(
        _ enabled: Bool,
        hookId: String,
        session: OMPSessionRecord
    ) async throws -> OMPSessionRecord {
        guard isSafeControlKey(session.controlKey) else {
            throw SessionControlError.invalidSession
        }
        let manager = FileManager.default
        let root = try controlRoot(manager: manager)
        let requestId = UUID().uuidString.lowercased()
        let prefix = "\(session.controlKey).\(requestId)"
        let requestURL = root.appendingPathComponent("\(prefix).request.json")
        let responseURL = root.appendingPathComponent("\(prefix).response.json")
        let request = SessionControlRequest(
            schema: Self.schema,
            requestId: requestId,
            sessionId: session.sessionId,
            controlKey: session.controlKey,
            hookId: hookId,
            enabled: enabled,
            confirmed: true,
            requestedAt: ISO8601DateFormatter().string(from: Date())
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(request).write(to: requestURL, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: requestURL.path)

        defer {
            try? manager.removeItem(at: requestURL)
            try? manager.removeItem(at: responseURL)
        }
        let decoder = JSONDecoder()
        for _ in 0..<80 {
            try Task.checkCancellation()
            if manager.fileExists(atPath: responseURL.path) {
                let response = try decoder.decode(
                    SessionControlResponse.self,
                    from: Data(contentsOf: responseURL)
                )
                guard response.schema == Self.schema, response.requestId == requestId else {
                    throw SessionControlError.invalidResponse
                }
                guard response.ok, let state = response.state else {
                    throw SessionControlError.rejected(response.error ?? "unknown error")
                }
                return state
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw SessionControlError.timedOut
    }

    private func controlRoot(manager: FileManager) throws -> URL {
        let support = try manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = support
            .appendingPathComponent("Tama", isDirectory: true)
            .appendingPathComponent("session-control", isDirectory: true)
        try manager.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        return root
    }

    private func processIsAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if Darwin.kill(pid_t(pid), 0) == 0 { return true }
        return errno == EPERM
    }

    private func isSafeControlKey(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy(\.isHexDigit)
    }
}

private struct SessionControlRequest: Encodable {
    let schema: String
    let requestId: String
    let sessionId: String
    let controlKey: String
    let hookId: String
    let enabled: Bool
    let confirmed: Bool
    let requestedAt: String
}

private struct SessionControlResponse: Decodable {
    let schema: String
    let requestId: String
    let ok: Bool
    let error: String?
    let state: OMPSessionRecord?
}

enum SessionControlError: LocalizedError {
    case invalidSession
    case invalidResponse
    case rejected(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .invalidSession:
            "Tama rejected an invalid OMP session control endpoint."
        case .invalidResponse:
            "The OMP session controller returned an invalid response."
        case let .rejected(reason):
            "The OMP session rejected the hook change: \(reason)"
        case .timedOut:
            "The OMP session did not acknowledge the hook change. It may have exited."
        }
    }
}
