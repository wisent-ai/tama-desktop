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
    /// How many declared mappings the provider's own config really installs.
    /// `nil` for providers whose config Tama does not write.
    let installedMappingCount: Int?
    let requiredLiveCoverage: Bool?
    let evidence: String
    let note: String?
    let mappings: [ProviderCoverageMapping]

    var id: String { provider }

    /// A provider the registry declares but maps to nothing is the minority
    /// state on this screen, and the only one that earns a chip.
    var isUncovered: Bool { mappingCount == .zero }

    /// The registry claims mappings this provider's config does not install:
    /// declared policy that never runs, which the declared counts alone
    /// cannot show.
    var isPartlyWired: Bool {
        guard let installedMappingCount else { return false }
        return installedMappingCount < mappingCount
    }

    var wiringSummary: String? {
        guard let installedMappingCount else { return nil }
        return
            "\(installedMappingCount.formatted(.number)) of \(mappingCount.formatted(.number)) installed"
    }
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
/// the install plan, the MCP snippet, and the model service Tama asks.
///
/// These reads exist in the core and had no surface at all, so the
/// operator had to leave the application to answer "which provider is covered"
/// and "where would an install write". Nothing here mutates: every read is a
/// request with an empty body, and each failure carries the backend's own
/// sentence back to the screen.
struct PolicyInspectionClient: Sendable {
    private static let coverageOperation = "The provider coverage read"
    private static let planOperation = "The install plan read"
    private static let mcpOperation = "The MCP snippet read"
    private static let modelServiceOperation = "The model service read"

    func providerCoverage() async throws -> [ProviderCoverage] {
        try await client().request(
            "coverage",
            as: [ProviderCoverage].self,
            describing: Self.coverageOperation
        )
    }

    func installPlan() async throws -> InstallPlan {
        let document = try await client().document(
            "install-plan",
            describing: Self.planOperation
        )
        return try Self.decodePlan(document)
    }

    func mcpConfiguration() async throws -> String {
        try await client().prettyText("mcp-config", describing: Self.mcpOperation)
    }

    /// Which model service Tama asks and whether it accepts this machine's
    /// credential: `tama model-provider show` and `check` as one read, shaped
    /// as the label/value rows the install levels already render.
    func modelService() async throws -> InstallPlanLevel {
        let document = try await client().document(
            "model-provider",
            describing: Self.modelServiceOperation
        )
        return try Self.decodeModelService(document)
    }

    static func decodeModelService(_ data: Data) throws -> InstallPlanLevel {
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw TamaBackendError.unreadableOutput(
                modelServiceOperation, error.localizedDescription)
        }
        guard
            let root = parsed as? [String: Any],
            let choice = root["choice"] as? [String: Any],
            var check = root["check"] as? [String: Any]
        else {
            throw TamaBackendError.unreadableOutput(
                modelServiceOperation,
                "the answer carries no choice and check objects"
            )
        }
        if let refusal = check["error"] as? String {
            return InstallPlanLevel(
                key: "model-service",
                level: "Model service",
                activeByArchiveAlone: false,
                fields: flatten(name: "service", value: choice),
                notes: ["The check could not run: \(refusal)"]
            )
        }
        guard let verdict = check.removeValue(forKey: "verdict") as? String else {
            throw TamaBackendError.unreadableOutput(
                modelServiceOperation,
                "the check carries no verdict sentence"
            )
        }
        return InstallPlanLevel(
            key: "model-service",
            level: "Model service",
            activeByArchiveAlone: check["accepted"] as? Bool == true
                && check["endpoint_allowed"] as? Bool == true,
            fields: flatten(name: "service", value: choice)
                + flatten(name: "check", value: check),
            notes: [verdict]
        )
    }

    private func client() -> TamaClient {
        TamaClient()
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
            case "dispatcherStates":
                // One row per managed Git hook, carrying the sentence the CLI
                // prints for it: a dispatcher held aside or a foreign hook in
                // its place means the push-time formatting gate does not run.
                guard let states = value as? [[String: Any]] else { continue }
                for state in states {
                    guard
                        let hook = state["hook"] as? String,
                        let description = state["description"] as? String
                    else { continue }
                    fields.append(InstallPlanField(label: "Git hook \(hook)", value: description))
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
