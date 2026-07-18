import Foundation
import Testing
@testable import TamaDesktop

struct JustificationRegistryTests {
    @Test
    func loadsFileAndTestRequirementsSeparately() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sharedHooks = home.appendingPathComponent(".shared-hooks", isDirectory: true)
        try FileManager.default.createDirectory(at: sharedHooks, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let existingFile = home.appendingPathComponent("Sources/Feature.swift")
        try FileManager.default.createDirectory(
            at: existingFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: existingFile)
        let missingTest = home.appendingPathComponent("Tests/FeatureTests.swift")

        try writeRegistry(
            [
                existingFile.path: [
                    "justification": longJustification,
                    "expires_at": "2027-07-16T00:00:00Z",
                ],
            ],
            to: sharedHooks.appendingPathComponent("file_justifications.json")
        )
        try writeRegistry(
            [
                missingTest.path: [
                    "justification": "This entry is intentionally too short.",
                ],
            ],
            to: sharedHooks.appendingPathComponent("test_justifications.json")
        )

        let collections = HookCatalogClient().loadJustifications(
            for: try catalog(),
            homeDirectory: home,
            now: try #require(ISO8601DateFormatter().date(from: "2026-07-16T00:00:00Z"))
        )

        #expect(collections.map(\.requirement.kind) == ["file", "test"])
        let file = try #require(collections.first(where: { $0.requirement.kind == "file" }))
        let fileEntry = try #require(file.entries.first)
        #expect(file.loadError == nil)
        #expect(fileEntry.targetExists)
        #expect(fileEntry.wordCount >= file.requirement.minimumWords)
        #expect(!fileEntry.isExpired)

        let test = try #require(collections.first(where: { $0.requirement.kind == "test" }))
        let testEntry = try #require(test.entries.first)
        #expect(test.loadError == nil)
        #expect(!testEntry.targetExists)
        #expect(testEntry.wordCount < test.requirement.minimumWords)
        #expect(testEntry.kind == "test")
    }

    private var longJustification: String {
        "This file exists to verify the observable loading contract for a declared justification requirement. The registry entry contains enough words to satisfy the configured minimum, points at a real target, and carries a future expiration timestamp. The test checks those resulting states without depending on any production registry, user setting, network service, or mutable application support directory."
    }

    private func catalog() throws -> HookCatalog {
        let requirement: [[String: Any]] = [
            [
                "kind": "file",
                "title": "File justification",
                "registryPath": "~/.shared-hooks/file_justifications.json",
                "field": "justification",
                "minimumWords": 50,
            ],
            [
                "kind": "test",
                "title": "Test justification",
                "registryPath": "~/.shared-hooks/test_justifications.json",
                "field": "justification",
                "minimumWords": 50,
            ],
        ]
        let value: [String: Any] = [
            "version": 1,
            "generatedAt": "2026-07-16T00:00:00Z",
            "hooks": [
                [
                    "id": "pre-write-edit",
                    "type": "requires_justification",
                    "command": "/hook",
                    "sourcePath": "shared-hooks/pre_write_edit.sh",
                    "category": "edit safety",
                    "status": "active",
                    "events": [],
                    "justificationRequirements": requirement,
                ],
            ],
            "orphanSources": [],
            "repoGitHooks": [],
        ]
        return try JSONDecoder().decode(
            HookCatalog.self,
            from: JSONSerialization.data(withJSONObject: value)
        )
    }

    private func writeRegistry(_ value: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: value).write(to: url)
    }
}
