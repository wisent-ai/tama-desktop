import Darwin
import Foundation

struct SessionCapabilityGrant: Codable, Sendable, Equatable {
    let tool: String
    let actions: [String]?
}

struct SessionCapability: Codable, Sendable, Equatable {
    let schemaVersion: Int
    let issuedBy: String
    let nonce: String
    let sessionId: String
    let controlKey: String
    let releaseId: String
    let catalogChecksum: String
    let lifetime: String
    let expiresAt: String?
    let remainingUses: Int?
    let grants: [SessionCapabilityGrant]
}

struct HookRuntimeStatus: Codable, Sendable, Equatable {
    let installedReleaseId: String?
    let loadedReleaseId: String
    let catalogChecksum: String?
    let registeredHookCount: Int
    let loadedHookCount: Int
    let disabledHookIds: [String]
    let enabledHookIds: [String]
    let unknownHookIds: [String]
    let reloadRequired: Bool
    let registryLoadError: String?
}


struct AgentSessionRecord: Decodable, Identifiable, Sendable {
    let schema: String
    let provider: String
    let sessionId: String
    let controlKey: String
    let pid: Int32
    let cwd: String
    let livenessMode: String
    let heartbeatTTLSeconds: Int
    let globallyDisabled: Bool
    let disabledHookIds: [String]
    let enabledHookIds: [String]
    let capability: SessionCapability?
    let runtime: HookRuntimeStatus?
    let updatedAt: String

    var id: String { "\(provider):\(sessionId)" }

    var providerDisplayName: String {
        switch provider {
        case "omp": "OMP"
        case "claude": "Claude"
        case "codex": "Codex"
        default: provider.capitalized
        }
    }

    var displayName: String {
        let project = URL(fileURLWithPath: cwd).lastPathComponent
        return "\(providerDisplayName) · \(project.isEmpty ? cwd : project) · \(sessionId.prefix(8))"
    }

    func isHookEnabled(_ hookId: String, globallyDisabled: Bool) -> Bool {
        globallyDisabled
            ? enabledHookIds.contains(hookId)
            : !disabledHookIds.contains(hookId)
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case provider
        case sessionId
        case controlKey
        case pid
        case cwd
        case livenessMode
        case heartbeatTTLSeconds
        case globallyDisabled
        case disabledHookIds
        case enabledHookIds
        case capability
        case runtime
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schema = try values.decode(String.self, forKey: .schema)
        provider = try values.decodeIfPresent(String.self, forKey: .provider) ?? "omp"
        sessionId = try values.decode(String.self, forKey: .sessionId)
        controlKey = try values.decode(String.self, forKey: .controlKey)
        pid = try values.decode(Int32.self, forKey: .pid)
        cwd = try values.decode(String.self, forKey: .cwd)
        livenessMode = try values.decodeIfPresent(String.self, forKey: .livenessMode) ?? "process"
        heartbeatTTLSeconds = try values.decodeIfPresent(Int.self, forKey: .heartbeatTTLSeconds) ?? 900
        globallyDisabled = try values.decode(Bool.self, forKey: .globallyDisabled)
        disabledHookIds = try values.decode([String].self, forKey: .disabledHookIds)
        enabledHookIds = try values.decode([String].self, forKey: .enabledHookIds)
        capability = try values.decodeIfPresent(SessionCapability.self, forKey: .capability)
        runtime = try values.decodeIfPresent(HookRuntimeStatus.self, forKey: .runtime)
        updatedAt = try values.decode(String.self, forKey: .updatedAt)
    }

    private init(
        replacing session: AgentSessionRecord,
        globallyDisabled: Bool,
        disabledHookIds: [String],
        enabledHookIds: [String],
        updatedAt: String
    ) {
        schema = session.schema
        provider = session.provider
        sessionId = session.sessionId
        controlKey = session.controlKey
        pid = session.pid
        cwd = session.cwd
        livenessMode = session.livenessMode
        heartbeatTTLSeconds = session.heartbeatTTLSeconds
        self.globallyDisabled = globallyDisabled
        self.disabledHookIds = disabledHookIds
        self.enabledHookIds = enabledHookIds
        capability = session.capability
        runtime = session.runtime
        self.updatedAt = updatedAt
    }

    func replacingOverrides(
        globallyDisabled: Bool,
        disabledHookIds: [String],
        enabledHookIds: [String],
        updatedAt: String
    ) -> AgentSessionRecord {
        AgentSessionRecord(
            replacing: self,
            globallyDisabled: globallyDisabled,
            disabledHookIds: disabledHookIds,
            enabledHookIds: enabledHookIds,
            updatedAt: updatedAt
        )
    }
}

struct SessionControlClient: Sendable {
    private static let schema = "ai.wisent.tama.session-control.v1"
    private let rootOverride: URL?

    init(root: URL? = nil) {
        rootOverride = root
    }

    func liveSessions(now: Date = Date()) throws -> [AgentSessionRecord] {
        let manager = FileManager.default
        let root = try controlRoot(manager: manager)
        let urls = try manager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let decoder = JSONDecoder()
        var sessions: [AgentSessionRecord] = []
        sessions.reserveCapacity(urls.count)
        for url in urls where url.lastPathComponent.hasSuffix(".session.json") {
            guard
                let data = try? Data(contentsOf: url),
                let session = try? decoder.decode(AgentSessionRecord.self, from: data),
                session.schema == Self.schema,
                isSafeProvider(session.provider),
                isSafeControlKey(session.controlKey)
            else {
                continue
            }
            if sessionIsLive(session, now: now) {
                sessions.append(session)
            } else {
                try? manager.removeItem(at: url)
            }
        }
        return sessions.sorted {
            if $0.provider != $1.provider {
                return $0.provider.localizedStandardCompare($1.provider) == .orderedAscending
            }
            if $0.cwd == $1.cwd { return $0.sessionId < $1.sessionId }
            return $0.cwd.localizedStandardCompare($1.cwd) == .orderedAscending
        }
    }

    func setHookEnabled(
        _ enabled: Bool,
        hookId: String,
        session: AgentSessionRecord,
        globallyDisabled: Bool
    ) throws -> AgentSessionRecord {
        guard
            isSafeControlKey(session.controlKey),
            isSafeProvider(session.provider),
            !hookId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw SessionControlError.invalidSession
        }
        let manager = FileManager.default
        let root = try controlRoot(manager: manager)
        if session.provider == "omp" {
            return try performRequest(
                operation: "set-hook",
                session: session,
                manager: manager,
                root: root,
                hookId: hookId,
                enabled: enabled
            )
        }
        let overrideURL = root.appendingPathComponent("\(session.controlKey).override.json")
        let decoder = JSONDecoder()
        let existing = (try? Data(contentsOf: overrideURL))
            .flatMap { try? decoder.decode(SessionControlOverride.self, from: $0) }
        let matching = existing?.matches(session: session) == true ? existing : nil
        var disabledHookIds = Set(matching?.disabledHookIds ?? session.disabledHookIds)
        var enabledHookIds = Set(matching?.enabledHookIds ?? session.enabledHookIds)
        if globallyDisabled {
            if enabled {
                enabledHookIds.insert(hookId)
            } else {
                enabledHookIds.remove(hookId)
            }
        } else if enabled {
            disabledHookIds.remove(hookId)
        } else {
            disabledHookIds.insert(hookId)
        }
        return try writeOverride(
            disabledHookIds: disabledHookIds,
            enabledHookIds: enabledHookIds,
            session: session,
            globallyDisabled: globallyDisabled,
            capability: matching?.capability ?? session.capability,
            manager: manager,
            overrideURL: overrideURL
        )
    }

    func setAllHooksEnabled(
        _ hookIds: [String],
        session: AgentSessionRecord,
        globallyDisabled: Bool
    ) throws -> AgentSessionRecord {
        guard
            isSafeControlKey(session.controlKey),
            isSafeProvider(session.provider),
            !hookIds.isEmpty,
            hookIds.allSatisfy({
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        else {
            throw SessionControlError.invalidSession
        }
        let manager = FileManager.default
        let root = try controlRoot(manager: manager)
        if session.provider == "omp" {
            return try performRequest(
                operation: "enable-all",
                session: session,
                manager: manager,
                root: root
            )
        }
        let overrideURL = root.appendingPathComponent("\(session.controlKey).override.json")
        let decoder = JSONDecoder()
        let existing = (try? Data(contentsOf: overrideURL))
            .flatMap { try? decoder.decode(SessionControlOverride.self, from: $0) }
        let matching = existing?.matches(session: session) == true ? existing : nil
        return try writeOverride(
            disabledHookIds: [],
            enabledHookIds: globallyDisabled ? Set(hookIds) : [],
            session: session,
            globallyDisabled: globallyDisabled,
            capability: matching?.capability ?? session.capability,
            manager: manager,
            overrideURL: overrideURL
        )
    }

    private func writeOverride(
        disabledHookIds: Set<String>,
        enabledHookIds: Set<String>,
        session: AgentSessionRecord,
        globallyDisabled: Bool,
        capability: SessionCapability?,
        manager: FileManager,
        overrideURL: URL
    ) throws -> AgentSessionRecord {
        let updatedAt = ISO8601DateFormatter().string(from: Date())
        let disabled = disabledHookIds.sorted()
        let enabled = enabledHookIds.sorted()
        let value = SessionControlOverride(
            schema: Self.schema,
            provider: session.provider,
            sessionId: session.sessionId,
            controlKey: session.controlKey,
            releaseId: session.runtime?.loadedReleaseId,
            catalogChecksum: session.runtime?.catalogChecksum,
            disabledHookIds: disabled,
            enabledHookIds: enabled,
            capability: capability,
            updatedAt: updatedAt
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: overrideURL, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: overrideURL.path)
        return session.replacingOverrides(
            globallyDisabled: globallyDisabled,
            disabledHookIds: disabled,
            enabledHookIds: enabled,
            updatedAt: updatedAt
        )
    }

    private func performRequest(
        operation: String,
        session: AgentSessionRecord,
        manager: FileManager,
        root: URL,
        hookId: String? = nil,
        enabled: Bool? = nil
    ) throws -> AgentSessionRecord {
        let requestId = UUID().uuidString.lowercased()
        let requestURL = root.appendingPathComponent(
            "\(session.controlKey).\(requestId).request.json"
        )
        let responseURL = root.appendingPathComponent(
            "\(session.controlKey).\(requestId).response.json"
        )
        let request = SessionControlRequest(
            schema: Self.schema,
            sessionId: session.sessionId,
            controlKey: session.controlKey,
            requestId: requestId,
            operation: operation,
            hookId: hookId,
            enabled: enabled,
            confirmed: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(request).write(to: requestURL, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: requestURL.path)
        defer {
            try? manager.removeItem(at: requestURL)
            try? manager.removeItem(at: responseURL)
        }
        let deadline = Date().addingTimeInterval(10)
        let decoder = JSONDecoder()
        while Date() < deadline {
            if let data = try? Data(contentsOf: responseURL),
               let response = try? decoder.decode(SessionControlResponse.self, from: data) {
                guard response.ok, let state = response.state else {
                    throw SessionControlError.runtimeRejected(
                        response.error ?? "Tama runtime rejected the operation."
                    )
                }
                return state
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw SessionControlError.runtimeTimeout
    }


    private func controlRoot(manager: FileManager) throws -> URL {
        let root: URL
        if let rootOverride {
            root = rootOverride
        } else {
            let support = try manager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            root = support
                .appendingPathComponent("Tama", isDirectory: true)
                .appendingPathComponent("session-control", isDirectory: true)
        }
        try manager.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        return root
    }

    private func sessionIsLive(_ session: AgentSessionRecord, now: Date) -> Bool {
        switch session.livenessMode {
        case "process":
            return processIsAlive(session.pid)
        case "heartbeat":
            guard let updated = Self.date(from: session.updatedAt) else { return false }
            let ttl = min(max(session.heartbeatTTLSeconds, 5), 3_600)
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

    private func isSafeProvider(_ value: String) -> Bool {
        guard let first = value.first, first.isASCII, first.isLetter, value.count <= 32 else {
            return false
        }
        return value.allSatisfy { character in
            character.isASCII && (character.isLowercase || character.isNumber || character == "-")
        }
    }

    private func isSafeControlKey(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy(\.isHexDigit)
    }
}

private struct SessionControlOverride: Codable {
    let schema: String
    let provider: String
    let sessionId: String
    let controlKey: String
    let releaseId: String?
    let catalogChecksum: String?
    let disabledHookIds: [String]
    let enabledHookIds: [String]
    let capability: SessionCapability?
    let updatedAt: String

    func matches(session: AgentSessionRecord) -> Bool {
        schema == session.schema
            && provider == session.provider
            && sessionId == session.sessionId
            && controlKey == session.controlKey
    }
}

private struct SessionControlRequest: Encodable {
    let schema: String
    let sessionId: String
    let controlKey: String
    let requestId: String
    let operation: String
    let hookId: String?
    let enabled: Bool?
    let confirmed: Bool
}

private struct SessionControlResponse: Decodable {
    let ok: Bool
    let error: String?
    let state: AgentSessionRecord?
}


enum SessionControlError: LocalizedError {
    case invalidSession
    case runtimeRejected(String)
    case runtimeTimeout

    var errorDescription: String? {
        switch self {
        case .invalidSession:
            "Tama rejected an invalid agent session control endpoint."
        case .runtimeRejected(let reason):
            reason
        case .runtimeTimeout:
            "The active OMP session did not acknowledge the Tama control request."
        }
    }
}
