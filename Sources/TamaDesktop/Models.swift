import Foundation

struct CatalogSnapshot: Sendable {
    let catalog: HookCatalog
    let validation: ValidationResult
    let loadedAt: Date
    let justifications: [JustificationCollection]
}

struct HookBuildIdentity: Decodable, Sendable {
    let releaseId: String
    let sourceDirty: Bool
    let sourceRevision: String
}

struct BuildIdentity: Decodable, Sendable {
    let architecture: String
    let builtAt: String
    let channel: String
    let hookRelease: HookBuildIdentity?
    let platform: String
    let productVersion: String
    let sourceDirty: Bool
    let sourceRevision: String

    static var current: BuildIdentity {
        guard
            let url = Bundle.main.url(forResource: "tama-build", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let identity = try? JSONDecoder().decode(BuildIdentity.self, from: data)
        else {
            return BuildIdentity(
                architecture: "unknown",
                builtAt: "unknown",
                channel: "development",
                hookRelease: nil,
                platform: "macOS",
                productVersion: Bundle.main.infoDictionary?["TamaProductVersion"] as? String
                    ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                    ?? "unknown",
                sourceDirty: true,
                sourceRevision: "unavailable"
            )
        }
        return identity
    }

    var displayedRevision: String {
        sourceDirty ? "\(sourceRevision) (dirty source)" : sourceRevision
    }
}

struct HookCatalog: Decodable, Sendable {
    let version: Int
    let generatedAt: String
    let hooks: [HookRecord]
    let orphanSources: [String]
    let repoGitHooks: [RepoGitHook]
}

struct HookRecord: Decodable, Identifiable, Sendable {
    let id: String
    let type: String
    let command: String
    let sourcePath: String?
    let category: String
    let status: String
    let description: String?
    let why: String?
    let sideEffects: String?
    let events: [HookEvent]
    let justificationRequirements: [JustificationRequirement]?

    var requirements: [JustificationRequirement] {
        justificationRequirements ?? []
    }

    var isBlocking: Bool {
        events.contains(where: \.blocking)
    }

    var eventNames: String {
        events.map(\.event).joined(separator: ", ")
    }
}

struct JustificationRequirement: Decodable, Hashable, Identifiable, Sendable {
    let kind: String
    let title: String
    let registryPath: String
    let field: String
    let minimumWords: Int
    let directUserQuoteField: String?

    var id: String {
        "\(kind):\(registryPath):\(field)"
    }
}

struct JustificationCollection: Identifiable, Sendable {
    let requirement: JustificationRequirement
    let entries: [JustificationEntry]
    let loadError: String?

    var id: String {
        requirement.id
    }
}

struct JustificationEntry: Identifiable, Sendable {
    let kind: String
    let registryKey: String
    let justification: String
    let wordCount: Int
    let directUserQuote: String?
    let expiresAt: Date?
    let targetExists: Bool
    let isExpired: Bool

    var id: String {
        "\(kind):\(registryKey)"
    }
}

struct HookEvent: Decodable, Identifiable, Sendable {
    let event: String
    let blocking: Bool
    let timeout: Int
    let statusMessage: String?

    var id: String {
        "\(event)-\(blocking)-\(timeout)"
    }
}

struct RepoGitHook: Decodable, Identifiable, Sendable {
    let project: String
    let event: String
    let sourcePath: String

    var id: String {
        "\(project)-\(event)-\(sourcePath)"
    }
}

struct ValidationResult: Decodable, Sendable {
    let ok: Bool
    let errors: [String]
    let warnings: [String]
    let hookCount: Int
    let orphanSourceCount: Int
}

struct PolicyBundleConflict: Decodable, Identifiable, Sendable {
    let path: String
    let reason: String
    let existingSha256: String?
    let incomingSha256: String?

    var id: String { path }
}

struct PolicyBundleImportResult: Decodable, Sendable {
    let status: String
    let sourcePath: String
    let sourceDigest: String?
    let storePath: String
    let bundlePath: String?
    let hookCount: Int
    let imported: Int
    let unchanged: Int
    let removed: Int
    let conflicting: Int
    let rejected: Int
    let conflicts: [PolicyBundleConflict]
    let rejections: [String]
    let ignoredPaths: [String]
    let activation: String
    let installedHooks: Int
    let enabledHooks: Int

    var accepted: Bool { status != "conflict" && status != "rejected" }

    var summary: String {
        switch status {
        case "unchanged":
            "Already current: \(unchanged) files unchanged. The bundle remains inactive."
        case "replaced":
            "Updated: \(imported) imported, \(unchanged) unchanged, \(removed) removed. Installed and enabled zero hooks."
        case "imported":
            "Imported: \(imported) files and \(hookCount) hooks. Installed and enabled zero hooks."
        case "rejected":
            "Rejected \(rejected) issue(s). No files changed and no hooks were enabled."
        default:
            "Found \(conflicting) conflict(s). No files changed and no hooks were enabled."
        }
    }
}

struct PolicyBundleSummary: Decodable, Identifiable, Sendable {
    let sourceKey: String
    let sourcePath: String
    let sourceDigest: String
    let bundlePath: String
    let importedAtUnix: UInt64
    let hookCount: Int
    let fileCount: Int
    let activation: String

    var id: String { sourceKey }
}

struct PolicyBundleList: Decodable, Sendable {
    let storePath: String
    let bundles: [PolicyBundleSummary]
}
