import Darwin
import Foundation

struct SessionControlClient: Sendable {
    /// A heartbeat TTL is honoured between five seconds and an hour, whatever the record claims.
    private static let minimumHeartbeatTTLSeconds = 5
    private static let maximumHeartbeatTTLSeconds = 3_600
    /// An agent id is a short lowercase word; a control key is a 256-bit hex string.
    private static let maximumAgentIdLength = 32
    private static let controlKeyHexLength = 64

    private static let schema = "ai.wisent.tama.session-control.v2"
    private static let legacySchema = "ai.wisent.tama.session-control.v1"
    private static let responsePollInterval = TimeInterval("0.05")!
    private static let responseTimeout = TimeInterval("10")!
    private static let privateFilePermissions = NSNumber(value: S_IRUSR | S_IWUSR)
    private static let privateDirectoryPermissions = NSNumber(
        value: S_IRUSR | S_IWUSR | S_IXUSR
    )
    private let rootOverride: URL?

    init(root: URL? = nil) {
        rootOverride = root
    }

    func liveSessions(now: Date = Date()) throws -> [AgentSessionRecord] {
        let manager = FileManager.default
        let root = try controlRoot(manager: manager, create: false)
        guard manager.fileExists(atPath: root.path) else { return [] }
        let urls = try manager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let decoder = JSONDecoder()
        var sessions: [AgentSessionRecord] = []
        var hasLegacySession = false
        sessions.reserveCapacity(urls.count)
        for url in urls where url.lastPathComponent.hasSuffix(".session.json") {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let envelope = try? decoder.decode(SessionControlSchemaEnvelope.self, from: data),
               envelope.schema == Self.legacySchema {
                hasLegacySession = true
                continue
            }
            guard
                let session = try? decoder.decode(AgentSessionRecord.self, from: data),
                session.schema == Self.schema,
                isSafeAgentId(session.agentId),
                isSafeControlKey(session.controlKey)
            else {
                continue
            }
            if sessionIsLive(session, now: now) {
                sessions.append(session)
            }
        }
        if sessions.isEmpty, hasLegacySession {
            throw SessionControlError.legacySessionRecords
        }
        return sessions.sorted {
            if $0.agentId != $1.agentId {
                return $0.agentId.localizedStandardCompare($1.agentId) == .orderedAscending
            }
            if $0.cwd == $1.cwd { return $0.sessionId < $1.sessionId }
            return $0.cwd.localizedStandardCompare($1.cwd) == .orderedAscending
        }
    }

    func enableHook(
        _ hookId: String,
        session: AgentSessionRecord
    ) throws -> AgentSessionRecord {
        guard
            isSafeControlKey(session.controlKey),
            isSafeAgentId(session.agentId),
            !hookId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw SessionControlError.invalidSession
        }
        return try performRequest(
            session: session,
            operation: "set-hook",
            hookId: hookId,
            enabled: true
        )
    }

    func setAllHooksEnabled(session: AgentSessionRecord) throws -> AgentSessionRecord {
        guard
            isSafeControlKey(session.controlKey),
            isSafeAgentId(session.agentId)
        else {
            throw SessionControlError.invalidSession
        }
        return try performRequest(session: session, operation: "enable-all")
    }

    private func performRequest(
        session: AgentSessionRecord,
        operation: String,
        hookId: String? = nil,
        enabled: Bool? = nil
    ) throws -> AgentSessionRecord {
        let manager = FileManager.default
        let root = try controlRoot(manager: manager, create: true)
        let requestID = UUID().uuidString.lowercased()
        let requestURL = root.appendingPathComponent(
            "\(session.controlKey).\(requestID).request.json"
        )
        let responseURL = root.appendingPathComponent(
            "\(session.controlKey).\(requestID).response.json"
        )
        defer {
            try? manager.removeItem(at: requestURL)
            try? manager.removeItem(at: responseURL)
        }
        let request = SessionControlRequest(
            schema: Self.schema,
            sessionId: session.sessionId,
            controlKey: session.controlKey,
            requestId: requestID,
            confirmed: true,
            operation: operation,
            hookId: hookId,
            enabled: enabled
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(request).write(to: requestURL, options: .atomic)
        try manager.setAttributes(
            [.posixPermissions: Self.privateFilePermissions],
            ofItemAtPath: requestURL.path
        )

        let decoder = JSONDecoder()
        let deadline = Date().addingTimeInterval(Self.responseTimeout)
        repeat {
            if manager.fileExists(atPath: responseURL.path) {
                let response: SessionControlResponse
                do {
                    response = try decoder.decode(
                        SessionControlResponse.self,
                        from: Data(contentsOf: responseURL)
                    )
                } catch {
                    throw SessionControlError.invalidResponse
                }
                guard
                    response.schema == Self.schema,
                    response.requestId == requestID
                else {
                    throw SessionControlError.invalidResponse
                }
                guard response.ok else {
                    throw SessionControlError.requestRejected(
                        response.error ?? "unknown-runtime-error"
                    )
                }
                guard
                    let state = response.state,
                    state.schema == Self.schema,
                    state.agentId == session.agentId,
                    state.sessionId == session.sessionId,
                    state.controlKey == session.controlKey,
                    isSafeAgentId(state.agentId),
                    isSafeControlKey(state.controlKey),
                    sessionIsLive(state, now: Date())
                else {
                    throw SessionControlError.invalidResponse
                }
                return state
            }
            guard sessionIsLive(session, now: Date()) else {
                throw SessionControlError.sessionEnded
            }
            Thread.sleep(forTimeInterval: Self.responsePollInterval)
        } while Date() < deadline
        throw SessionControlError.requestTimedOut
    }

    private func controlRoot(manager: FileManager, create: Bool) throws -> URL {
        let root: URL
        if let rootOverride {
            root = rootOverride
        } else {
            let support = try manager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: create
            )
            root = support
                .appendingPathComponent("Tama", isDirectory: true)
                .appendingPathComponent("session-control", isDirectory: true)
        }
        if create {
            try manager.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: Self.privateDirectoryPermissions]
            )
            try manager.setAttributes(
                [.posixPermissions: Self.privateDirectoryPermissions],
                ofItemAtPath: root.path
            )
        }
        return root
    }

    private func sessionIsLive(_ session: AgentSessionRecord, now: Date) -> Bool {
        switch session.livenessMode {
        case "process":
            return processIsAlive(session.pid)
        case "heartbeat":
            guard let updated = Self.date(from: session.updatedAt) else { return false }
            let ttl = min(max(session.heartbeatTTLSeconds, Self.minimumHeartbeatTTLSeconds), Self.maximumHeartbeatTTLSeconds)
            return updated.addingTimeInterval(TimeInterval(ttl)) >= now
        default:
            return false
        }
    }

    private static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func processIsAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if Darwin.kill(pid_t(pid), 0) == 0 { return true }
        return errno == EPERM
    }

    private func isSafeAgentId(_ value: String) -> Bool {
        guard let first = value.first, first.isASCII, first.isLetter, value.count <= Self.maximumAgentIdLength else {
            return false
        }
        return value.allSatisfy { character in
            character.isASCII && (character.isLowercase || character.isNumber || character == "-")
        }
    }

    private func isSafeControlKey(_ value: String) -> Bool {
        value.count == Self.controlKeyHexLength && value.allSatisfy(\.isHexDigit)
    }
}

struct SessionControlSchemaEnvelope: Decodable {
    let schema: String
}

struct SessionControlRequest: Encodable {
    let schema: String
    let sessionId: String
    let controlKey: String
    let requestId: String
    let confirmed: Bool
    let operation: String
    let hookId: String?
    let enabled: Bool?
}

struct SessionControlResponse: Decodable {
    let schema: String
    let requestId: String
    let ok: Bool
    let error: String?
    let state: AgentSessionRecord?
}
