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
    /// Why the bundled `tama-build.json` could not be read, when it exists
    /// and cannot be read or decoded. It used to read as an unbuilt
    /// development build, which a release with a damaged record is not.
    var readFailure: String? = nil

    static var current: BuildIdentity {
        var readFailure: String?
        if let url = Bundle.main.url(forResource: "tama-build", withExtension: "json") {
            do {
                return try JSONDecoder().decode(BuildIdentity.self, from: Data(contentsOf: url))
            } catch {
                readFailure = "\(url.path(percentEncoded: false)) cannot be read: \(error)"
            }
        }
        // No readable record: a development build when none is bundled, or
        // a build whose bundled record failed, which says so. What only the
        // record states reads as not recorded; the architecture is the one
        // this binary was compiled for, and the version the bundle's own.
        let info = Bundle.main.infoDictionary
        var productVersion = "not recorded"
        if let version = info?["TamaProductVersion"] as? String {
            productVersion = version
        } else if let version = info?["CFBundleShortVersionString"] as? String {
            productVersion = version
        }
        var identity = BuildIdentity(
            architecture: compiledArchitecture,
            builtAt: "not recorded",
            channel: readFailure == nil ? "development" : "unreadable build record",
            hookRelease: nil,
            platform: "macOS",
            productVersion: productVersion,
            sourceDirty: true,
            sourceRevision: "not recorded"
        )
        identity.readFailure = readFailure
        return identity
    }

    /// The architecture this binary was compiled for.
    private static var compiledArchitecture: String {
        #if arch(arm64)
            return "arm64"
        #elseif arch(x86_64)
            return "x86_64"
        #else
            return "not recorded"
        #endif
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
    let statusMessage: String?

    var id: String {
        "\(event)-\(blocking)"
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

    /// The import statuses `tama policy import` answers with.
    enum ImportStatus: String {
        case unchanged
        case replaced
        case imported
        case rejected
        case conflict
    }

    /// An import is accepted when it changed or confirmed the bundle; a
    /// conflict, a rejection or a status this app does not know is not.
    var accepted: Bool {
        switch ImportStatus(rawValue: status) {
        case .unchanged?, .replaced?, .imported?: true
        case .rejected?, .conflict?, nil: false
        }
    }

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
