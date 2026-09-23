import Darwin
import Foundation

struct SessionCapabilityGrant: Codable, Sendable, Equatable, Identifiable {
    let tool: String
    let actions: [String]?

    var id: String { tool }

    var actionList: String {
        guard let actions, !actions.isEmpty else { return "every action" }
        return actions.joined(separator: ", ")
    }
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
    let reloadPending: Bool?
    let registryLoadError: String?
}

struct SemanticEventSummary: Codable, Sendable, Equatable, Identifiable {
    let eventId: String
    let event: String
    let timestamp: String
    let decision: String
    let blockedHookId: String?
    let reason: String?

    var id: String { eventId }

    var isBlocking: Bool { decision != "allow" }
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

    func isHookEnabled(_ hookId: String) -> Bool {
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

}
