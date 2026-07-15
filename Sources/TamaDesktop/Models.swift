import Foundation

struct CatalogSnapshot: Sendable {
    let catalog: HookCatalog
    let validation: ValidationResult
    let loadedAt: Date
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

    var isBlocking: Bool {
        events.contains(where: \.blocking)
    }

    var eventNames: String {
        events.map(\.event).joined(separator: ", ")
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

enum SidebarSelection: Hashable {
    case overview
    case hooks
    case validation
    case repositories
}

enum HookFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case blocking = "Blocking"
    case nonblocking = "Non-blocking"

    var id: Self { self }
}
