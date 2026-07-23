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

struct SemanticEventSummary: Codable, Sendable, Equatable {
    let eventId: String
    let event: String
    let timestamp: String
    let decision: String
    let blockedHookId: String?
    let reason: String?
}

struct SemanticRuntimeStatus: Codable, Sendable, Equatable {
    let observationSchema: String
    let semanticEventSchema: String
    let eventSequence: Int
    let recentEvents: [SemanticEventSummary]
}


struct SystemPolicyStatus: Codable, Sendable, Equatable {
    let schema: String
    let configured: Bool
    let required: Bool?
    let ready: Bool
    let backend: String?
    let capabilities: [String]
    let error: String?
    let mode: String
    let supportPullRequestURL: String?
}

struct AgentSessionRecord: Decodable, Identifiable, Sendable {
    let schema: String
    let agentId: String
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
    let semanticRuntime: SemanticRuntimeStatus?
    let systemPolicy: SystemPolicyStatus?
    let updatedAt: String

    var id: String { "\(agentId):\(sessionId)" }

    var agentDisplayName: String {
        agentId
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    var displayName: String {
        let project = URL(fileURLWithPath: cwd).lastPathComponent
        return "\(agentDisplayName) · \(project.isEmpty ? cwd : project) · \(sessionId.prefix(8))"
    }

    func isHookEnabled(_ hookId: String, globallyDisabled: Bool) -> Bool {
        globallyDisabled
            ? enabledHookIds.contains(hookId)
            : !disabledHookIds.contains(hookId)
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case agentId
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
        case semanticRuntime
        case systemPolicy
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schema = try values.decode(String.self, forKey: .schema)
        agentId = try values.decode(String.self, forKey: .agentId)
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
        semanticRuntime = try values.decodeIfPresent(SemanticRuntimeStatus.self, forKey: .semanticRuntime)
        systemPolicy = try values.decodeIfPresent(SystemPolicyStatus.self, forKey: .systemPolicy)
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
        agentId = session.agentId
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
        semanticRuntime = session.semanticRuntime
        systemPolicy = session.systemPolicy
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
    private static let schema = "ai.wisent.tama.session-control.v2"
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
                isSafeAgentId(session.agentId),
                isSafeControlKey(session.controlKey)
            else {
                try? manager.removeItem(at: url)
                continue
            }
            if sessionIsLive(session, now: now) {
                sessions.append(session)
            } else {
                try? manager.removeItem(at: url)
            }
        }
        return sessions.sorted {
            if $0.agentId != $1.agentId {
                return $0.agentId.localizedStandardCompare($1.agentId) == .orderedAscending
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
            isSafeAgentId(session.agentId),
            !hookId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw SessionControlError.invalidSession
        }
        let manager = FileManager.default
        let root = try controlRoot(manager: manager)
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
            isSafeAgentId(session.agentId),
            !hookIds.isEmpty,
            hookIds.allSatisfy({
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        else {
            throw SessionControlError.invalidSession
        }
        let manager = FileManager.default
        let root = try controlRoot(manager: manager)
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
            agentId: session.agentId,
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

    private func isSafeAgentId(_ value: String) -> Bool {
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
    let agentId: String
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
            && agentId == session.agentId
            && sessionId == session.sessionId
            && controlKey == session.controlKey
    }
}



enum SessionControlError: LocalizedError {
    case invalidSession

    var errorDescription: String? {
        "Tama rejected an invalid agent session control endpoint."
    }
}
