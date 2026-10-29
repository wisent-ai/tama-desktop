import Darwin
import Foundation

struct SessionControlClient: Sendable {
    /// An agent id is a short lowercase word; a control key is a 256-bit hex string.
    static let maximumAgentIdLength = 32
    static let controlKeyHexLength = 64

    private static let schema = "ai.wisent.tama.session-control.v2"
    private static let legacySchema = "ai.wisent.tama.session-control.v1"
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
        var unreadable: [String] = []
        sessions.reserveCapacity(urls.count)
        for url in urls where url.lastPathComponent.hasSuffix(".session.json") {
            // A record removed since the listing is a session that ended; one
            // that exists but cannot be read is a session Tama cannot show.
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch CocoaError.fileReadNoSuchFile {
                continue
            } catch {
                unreadable.append("\(url.path): \(error.localizedDescription)")
                continue
            }
            // A record that is not JSON with a schema, or that declares this
            // schema and does not decode, is named like one that cannot be
            // read, rather than a session that silently is not there. A record
            // of another schema is not this client's to show.
            let envelope: SessionControlSchemaEnvelope
            do {
                envelope = try decoder.decode(SessionControlSchemaEnvelope.self, from: data)
            } catch {
                unreadable.append("\(url.path): \(error)")
                continue
            }
            if envelope.schema == Self.legacySchema {
                hasLegacySession = true
                continue
            }
            guard envelope.schema == Self.schema else { continue }
            let session: AgentSessionRecord
            do {
                session = try decoder.decode(AgentSessionRecord.self, from: data)
            } catch {
                unreadable.append("\(url.path): \(error)")
                continue
            }
            // A record whose agent id or control key Tama will not address is
            // named with the value it refused, never dropped: dropping it made
            // a running session vanish from the Session screen.
            guard isSafeAgentId(session.agentId) else {
                unreadable.append(
                    "\(url.path): agent id \(session.agentId.debugDescription) is not a lowercase word of at most \(Self.maximumAgentIdLength) characters"
                )
                continue
            }
            guard isSafeControlKey(session.controlKey) else {
                unreadable.append(
                    "\(url.path): control key is not \(Self.controlKeyHexLength) hexadecimal characters"
                )
                continue
            }
            // A record whose liveness cannot be told is listed with its reason
            // rather than dropped, so a launcher that states neither an owner
            // process nor a heartbeat is visible.
            if sessionIsLive(session, now: now) || session.livenessMode == "unknown" {
                sessions.append(session)
            }
        }
        if !unreadable.isEmpty {
            throw SessionControlError.recordsUnreadable(unreadable)
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

    func reloadAdapter(session: AgentSessionRecord) throws -> AgentSessionRecord {
        guard session.agentId == "omp", isSafeControlKey(session.controlKey) else {
            throw SessionControlError.invalidSession
        }
        guard session.runtime?.adapterReloadSupported == true else {
            throw SessionControlError.requestRejected(
                "The loaded adapter does not support remote reload. Use tama_reload_hook_runtime in that existing OMP terminal and inspect its loaded adapter digest."
            )
        }
        let updated = try performRequest(session: session, operation: "reload-adapter")
        guard updated.pid == session.pid else {
            throw SessionControlError.invalidResponse(
                "the reloaded session answers from \(Self.processLabel(updated.pid)), not \(Self.processLabel(session.pid))"
            )
        }
        guard let digest = updated.runtime?.adapterDigest, !digest.isEmpty else {
            throw SessionControlError.invalidResponse(
                "the reloaded session reports no loaded adapter digest")
        }
        return updated
    }

    func inspectRuntime(session: AgentSessionRecord) throws -> AgentSessionRecord {
        guard isSafeControlKey(session.controlKey), isSafeAgentId(session.agentId) else {
            throw SessionControlError.invalidSession
        }
        return try performRequest(session: session, operation: "runtime-status")
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
        // Armed before the request is written, so the runtime's answer cannot
        // land between writing and watching.
        let watch = try ControlDirectoryWatch(
            directory: root,
            processes: session.livenessMode == "process" ? [session.pid].compactMap { $0 } : []
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(request).write(to: requestURL, options: .atomic)
        try manager.setAttributes(
            [.posixPermissions: Self.privateFilePermissions],
            ofItemAtPath: requestURL.path
        )

        let decoder = JSONDecoder()
        while true {
            if manager.fileExists(atPath: responseURL.path) {
                let response: SessionControlResponse
                do {
                    response = try decoder.decode(
                        SessionControlResponse.self,
                        from: Data(contentsOf: responseURL)
                    )
                } catch {
                    throw SessionControlError.invalidResponse(
                        "\(responseURL.path) cannot be read as a response: \(error)")
                }
                guard response.schema == Self.schema, response.requestId == requestID else {
                    throw SessionControlError.invalidResponse(
                        "\(responseURL.path) answers request \(response.requestId) of schema \(response.schema), not request \(requestID) of schema \(Self.schema)"
                    )
                }
                guard response.ok else {
                    guard let reason = response.error else {
                        throw SessionControlError.invalidResponse(
                            "\(responseURL.path) refuses the request without stating why")
                    }
                    throw SessionControlError.requestRejected(reason)
                }
                guard let state = response.state else {
                    throw SessionControlError.invalidResponse(
                        "\(responseURL.path) accepts the request without the session's state")
                }
                guard
                    state.schema == Self.schema,
                    state.agentId == session.agentId,
                    state.sessionId == session.sessionId,
                    state.controlKey == session.controlKey
                else {
                    throw SessionControlError.invalidResponse(
                        "\(responseURL.path) answers with \(state.agentId) session \(state.sessionId) of schema \(state.schema), not \(session.agentId) session \(session.sessionId)"
                    )
                }
                guard sessionIsLive(state, now: Date()) else {
                    throw SessionControlError.sessionEnded
                }
                return state
            }
            guard sessionIsLive(session, now: Date()) else {
                throw SessionControlError.sessionEnded
            }
            watch.next()
        }
    }

    /// The directory session records live in, for a caller that watches it.
    func sessionDirectory() throws -> URL {
        try controlRoot(manager: FileManager.default, create: true)
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
            root =
                support
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
}
