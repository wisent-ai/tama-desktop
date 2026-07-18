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
        let justifications = loadJustifications(for: catalog)
        return CatalogSnapshot(
            catalog: catalog,
            validation: validateSnapshot(catalog),
            loadedAt: Date(),
            justifications: justifications
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

    func loadJustifications(
        for catalog: HookCatalog,
        homeDirectory: URL? = nil,
        now: Date = Date()
    ) -> [JustificationCollection] {
        let home = homeDirectory ?? manager.homeDirectoryForCurrentUser
        var seen: Set<JustificationRequirement.ID> = []
        let requirements = catalog.hooks
            .filter { $0.type == "requires_justification" }
            .flatMap(\.requirements)
            .filter { seen.insert($0.id).inserted }

        return requirements.map { requirement in
            do {
                let registryURL = resolvedURL(requirement.registryPath, homeDirectory: home)
                let data = try Data(contentsOf: registryURL)
                guard let registry = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw JustificationRegistryError.invalidRoot(registryURL.path)
                }
                let entries = registry.keys.sorted().map { key in
                    let fields = registry[key] as? [String: Any]
                    let justification = fields?[requirement.field] as? String ?? ""
                    let expiresAt = parseDate(fields?["expires_at"] as? String)
                    let directUserQuote = requirement.directUserQuoteField
                        .flatMap { fields?[$0] as? String }
                    let targetURL = resolvedURL(key, homeDirectory: home)
                    return JustificationEntry(
                        kind: requirement.kind,
                        registryKey: key,
                        justification: justification,
                        wordCount: justification.split(whereSeparator: \.isWhitespace).count,
                        directUserQuote: directUserQuote,
                        expiresAt: expiresAt,
                        targetExists: manager.fileExists(atPath: targetURL.path),
                        isExpired: expiresAt.map { $0 <= now } ?? false
                    )
                }
                return JustificationCollection(
                    requirement: requirement,
                    entries: entries,
                    loadError: nil
                )
            } catch {
                return JustificationCollection(
                    requirement: requirement,
                    entries: [],
                    loadError: error.localizedDescription
                )
            }
        }
    }

    private func resolvedURL(_ path: String, homeDirectory: URL) -> URL {
        if path == "~" {
            return homeDirectory
        }
        if path.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(path.dropFirst(2)))
        }
        return URL(fileURLWithPath: path)
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = fractional.date(from: value) {
            return parsed
        }
        return ISO8601DateFormatter().date(from: value)
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


private enum JustificationRegistryError: LocalizedError {
    case invalidRoot(String)

    var errorDescription: String? {
        switch self {
        case let .invalidRoot(path):
            "Justification registry must contain a JSON object: \(path)"
        }
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
