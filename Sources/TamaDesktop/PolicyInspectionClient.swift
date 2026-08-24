import Foundation

struct ProviderCoverageMapping: Decodable, Identifiable, Sendable {
    let provider: String
    let event: String
    let runtimeEvent: String
    let hookId: String

    var id: String { "\(provider)|\(event)|\(runtimeEvent)|\(hookId)" }
}

struct ProviderCoverage: Decodable, Identifiable, Sendable {
    let provider: String
    let coverageKind: String
    let mappingCount: Int
    let hookCount: Int
    let eventCount: Int
    let adapterPath: String?
    let requiredLiveCoverage: Bool?
    let evidence: String
    let note: String?
    let mappings: [ProviderCoverageMapping]

    var id: String { provider }

    /// A provider the registry declares but maps to nothing is the minority
    /// state on this screen, and the only one that earns a chip.
    var isUncovered: Bool { mappingCount == .zero }
}

struct InstallPlanField: Identifiable, Sendable {
    let label: String
    let value: String

    var id: String { label }
}

struct InstallPlanLevel: Identifiable, Sendable {
    let key: String
    let level: String
    let activeByArchiveAlone: Bool
    let fields: [InstallPlanField]
    let notes: [String]

    var id: String { key }
}

struct InstallPlan: Sendable {
    let archiveRoot: String
    let levels: [InstallPlanLevel]
}

/// The read-only half of the Tama backend: coverage the registry declares,
/// the install plan, and the MCP snippet.
///
/// These three reads exist in the core and had no surface at all, so the
/// operator had to leave the application to answer "which provider is covered"
/// and "where would an install write". Nothing here mutates: every read is a
/// GET, and each failure carries the backend's own sentence back to the screen.
struct PolicyInspectionClient: Sendable {
    private static let coverageOperation = "The provider coverage read"
    private static let planOperation = "The install plan read"
    private static let mcpOperation = "The MCP snippet read"

    func providerCoverage() async throws -> [ProviderCoverage] {
        try await client().get(
            "coverage",
            as: [ProviderCoverage].self,
            operation: Self.coverageOperation
        )
    }

    func installPlan() async throws -> InstallPlan {
        let document = try await client().getDocument(
            "install-plan",
            operation: Self.planOperation
        )
        return try Self.decodePlan(document)
    }

    func mcpConfiguration() async throws -> String {
        try await client().getPrettyText("mcp-config", operation: Self.mcpOperation)
    }

    private func client() async throws -> TamaClient {
        TamaClient(baseURL: try await TamaBackend.shared.endpoint())
    }

    /// The plan's levels do not share a shape: one carries seven runtime
    /// targets, another a single note, a third a Git config command. Decoding
    /// it into one rigid type would either drop fields or invent them, so the
    /// document is walked and rendered as the label/value rows it already is.
    static func decodePlan(_ data: Data) throws -> InstallPlan {
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw TamaBackendError.unreadableOutput(planOperation, error.localizedDescription)
        }
        guard
            let root = parsed as? [String: Any],
            let archiveRoot = root["archiveRoot"] as? String,
            let levels = root["levels"] as? [String: Any]
        else {
            throw TamaBackendError.unreadableOutput(
                planOperation,
                "the plan document carries no archiveRoot string and levels object"
            )
        }
        let ordered = ["agent-app", "editor", "mcp", "user-global-git", "repo-project", "os-level"]
        let keys = levels.keys.sorted { left, right in
            let leftRank = ordered.firstIndex(of: left) ?? ordered.count
            let rightRank = ordered.firstIndex(of: right) ?? ordered.count
            return leftRank == rightRank ? left < right : leftRank < rightRank
        }
        return InstallPlan(
            archiveRoot: archiveRoot,
            levels: keys.compactMap { key in
                guard let body = levels[key] as? [String: Any] else { return nil }
                return level(key: key, body: body)
            }
        )
    }

    private static func level(key: String, body: [String: Any]) -> InstallPlanLevel {
        var fields: [InstallPlanField] = []
        var notes: [String] = []
        for name in body.keys.sorted() {
            let value = body[name]
            switch name {
            case "level", "activeByArchiveAlone":
                continue
            case "note":
                if let note = value as? String { notes.append(note) }
            case "unsupportedTargets":
                guard let targets = value as? [String: Any] else { continue }
                for target in targets.keys.sorted() {
                    guard let sentence = targets[target] as? String else { continue }
                    notes.append("\(target): \(sentence)")
                }
            default:
                fields.append(contentsOf: flatten(name: name, value: value))
            }
        }
        return InstallPlanLevel(
            key: key,
            level: body["level"] as? String ?? key,
            activeByArchiveAlone: body["activeByArchiveAlone"] as? Bool ?? false,
            fields: fields,
            notes: notes
        )
    }

    private static func flatten(name: String, value: Any?) -> [InstallPlanField] {
        switch value {
        case let text as String:
            return [InstallPlanField(label: humanized(name), value: text)]
        case is NSNull, .none:
            // A target the plan reports as null is unconfigured, and saying so
            // is the fact; omitting the row would hide it.
            return [InstallPlanField(label: humanized(name), value: "Not configured")]
        case let number as NSNumber:
            // A boolean and a number share one Objective-C type, and the Swift
            // bridge reads any non-zero number as `true`, so the encoded type
            // is checked rather than the cast.
            return [
                InstallPlanField(
                    label: humanized(name),
                    value: CFGetTypeID(number) == CFBooleanGetTypeID()
                        ? (number.boolValue ? "yes" : "no")
                        : number.stringValue
                )
            ]
        case let list as [Any]:
            let joined = list.compactMap { $0 as? String }.joined(separator: ", ")
            guard !joined.isEmpty else { return [] }
            return [InstallPlanField(label: humanized(name), value: joined)]
        case let nested as [String: Any]:
            return nested.keys.sorted().flatMap { key in
                flatten(name: key, value: nested[key])
            }
        default:
            return []
        }
    }

    /// `codexSettings` reads as CODEX SETTINGS in a field label; the plan's own
    /// camel case would read as a variable name the operator never typed.
    private static func humanized(_ name: String) -> String {
        var words: [String] = []
        var current = ""
        for character in name {
            if character.isUppercase, !current.isEmpty {
                words.append(current)
                current = String(character)
            } else if character == "-" || character == "_" {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words.joined(separator: " ")
    }
}
