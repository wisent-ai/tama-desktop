import Foundation

struct HookCatalogClient: Sendable {
    private var manager: FileManager { .default }

    func load() throws -> CatalogSnapshot {
        guard let catalogURL = Bundle.main.url(
            forResource: "tama-catalog",
            withExtension: "json"
        ) else {
            throw ClientError.bundledCatalogMissing
        }
        let catalog = try JSONDecoder().decode(
            HookCatalog.self,
            from: Data(contentsOf: catalogURL)
        )
        return CatalogSnapshot(
            catalog: catalog,
            validation: validateSnapshot(catalog),
            loadedAt: Date()
        )
    }

    func repositoryRoot() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["TAMA_REPOSITORY_ROOT"], !override.isEmpty {
            let root = URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
            guard manager.fileExists(atPath: root.path) else {
                throw ClientError.invalidRepositoryRoot(root.path)
            }
            return root
        }

        let root = manager.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/CodingProjects/Wisent/hooks-rotator", isDirectory: true)
            .standardizedFileURL
        guard manager.fileExists(atPath: root.path) else {
            throw ClientError.repositoryNotFound
        }
        return root
    }

    private func validateSnapshot(_ catalog: HookCatalog) -> ValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        var seenIDs: Set<String> = []
        for hook in catalog.hooks {
            if !seenIDs.insert(hook.id).inserted {
                errors.append("duplicate hook id: \(hook.id)")
            }
            if hook.sourcePath == nil {
                warnings.append("\(hook.id): source path could not be mapped from command")
            }
            if hook.events.isEmpty {
                errors.append("\(hook.id): no events")
            }
        }
        warnings.append(
            "Bundled snapshot only: high-entropy and live runtime drift checks are not run in Tama."
        )
        return ValidationResult(
            ok: errors.isEmpty,
            errors: errors,
            warnings: warnings,
            hookCount: catalog.hooks.count,
            orphanSourceCount: catalog.orphanSources.count
        )
    }
}


enum ClientError: LocalizedError {
    case repositoryNotFound
    case invalidRepositoryRoot(String)
    case bundledCatalogMissing

    var errorDescription: String? {
        switch self {
        case .repositoryNotFound:
            "The hooks-rotator repository could not be located."
        case let .invalidRepositoryRoot(path):
            "TAMA_REPOSITORY_ROOT does not exist: \(path)"
        case .bundledCatalogMissing:
            "The Tama bundle does not contain its catalog snapshot. Rebuild with Scripts/build-app.sh."
        }
    }
}
