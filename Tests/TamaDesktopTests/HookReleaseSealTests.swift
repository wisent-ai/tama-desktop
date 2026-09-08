import Foundation
import Testing

/// `Scripts/seal_hook_release.py` driven the way the release pipeline drives it.
///
/// On 2026-09-08 no hook release could be sealed at all, and the one that was
/// finally installed wrote thirty-nine hook commands with the home directory
/// doubled — paths that do not exist, so those hooks stop running and nothing
/// says so. Three defects, one shape: the registry declares its checkout in
/// one field, three consumers read it, and nothing checked what they produced.
///
/// These cases run the real script over a real fixture tree and read the files
/// it writes, because every one of those defects was in what the script
/// resolved and recorded, never in what it printed.
struct HookReleaseSealTests {
    @Test
    func sealRecordsTheDeclaredSourceSoTheInstallerCanMatchIt() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let result = try fixture.seal(sourceRoot: fixture.checkout)

        #expect(result.status == .zero, "sealing failed: \(result.error)")
        let mappings = try fixture.mappings()
        // The installer matches this prefix against the value the registry
        // declares. Recording the absolute path it resolved to here left every
        // installed hook with no source at all.
        #expect(mappings.values.contains("external-hooks/guard/guard.rs"))
        #expect(mappings.keys.contains { $0.hasSuffix("block/stop/guard.rs") })
        #expect(FileManager.default.fileExists(
            atPath: fixture.release.appendingPathComponent("external-hooks/guard/guard.rs").path
        ))
        let release = try fixture.releaseDocument()
        #expect(release["sourceRevision"] as? String == "fixture-revision")
        #expect(release["sourceDirty"] as? Bool == false)
    }

    @Test
    func sealStatesTheCheckoutSoTheInstallerCannotDoubleTheHome() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let result = try fixture.seal(sourceRoot: fixture.checkout)
        #expect(result.status == .zero, "sealing failed: \(result.error)")

        let registry = try fixture.sealedRegistry()
        let catalog = registry["catalog"] as? [String: Any] ?? [:]
        let maintained = catalog["maintainedIn"] as? String ?? ""
        // A relative value collapses the installer's rewrite prefix to ".",
        // which then matches inside every $HOME-prefixed hook command.
        #expect(maintained.hasPrefix("$HOME/") || maintained.hasPrefix("/"))
        #expect(maintained.hasSuffix("/shared-hooks/registry.json"))
        let hooks = catalog["agentHooks"] as? [[String: Any]] ?? []
        let source = hooks.first?["source"] as? String ?? ""
        #expect(source.hasPrefix("$HOME/") || source.hasPrefix("/"),
                "a source the installer can map into the release tree")
        #expect(registry["catalogChecksum"] as? String != "stale",
                "the checksum is recomputed after the restatement")
    }

    @Test
    func sealRefusesFromTheWrongRootAndNamesTheRootItUsed() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let result = try fixture.seal(sourceRoot: nil)

        #expect(result.status != .zero, "sealing should refuse when the root is wrong")
        #expect(result.error.contains("External hook source is missing"))
        // The refusal has to carry the root, because the path on its own reads
        // like a deleted file and sent an operator looking for one.
        #expect(result.error.contains("resolved against source root"))
        #expect(result.error.contains("tama-reconcile-registry-sources"))
        #expect(!FileManager.default.fileExists(
            atPath: fixture.release.appendingPathComponent("release.json").path
        ))
    }

    @Test
    func sealLeavesManagedHookDirectoriesOutOfTheExternalManifest() throws {
        let fixture = try Fixture(declaredSource: "shared-hooks/pre_bash.sh")
        defer { fixture.remove() }

        let result = try fixture.seal(sourceRoot: fixture.checkout)

        #expect(result.status == .zero, "sealing failed: \(result.error)")
        // A hook shipped inside the release needs no external copy; packaging
        // one would install a second source of the same hook.
        #expect(try fixture.mappings().isEmpty)
    }
}

/// A release directory and the checkout its registry was sealed from.
private struct Fixture {
    let root: URL
    let release: URL
    let checkout: URL
    private let scripts: URL

    init(declaredSource: String = "rust/crates/tama-hook-tools/src/bin/block/stop/guard.rs") throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        release = root.appendingPathComponent("release", isDirectory: true)
        checkout = root.appendingPathComponent("checkout", isDirectory: true)
        scripts = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Scripts", isDirectory: true)

        let managed = release.appendingPathComponent("shared-hooks", isDirectory: true)
        try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: true)
        try Data("#!/bin/bash\n".utf8).write(to: managed.appendingPathComponent("pre_bash.sh"))
        try Data("{\"version\": \"fixture\"}\n".utf8)
            .write(to: release.appendingPathComponent("package.json"))

        let source = checkout.appendingPathComponent(declaredSource)
        try FileManager.default.createDirectory(
            at: source.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("//! fixture hook source\n".utf8).write(to: source)

        let catalog: [String: Any] = [
            "maintainedIn": "shared-hooks/registry.json",
            "version": Int("1")!,
            "updatedAt": "2026-09-08T00:00:00Z",
            "agentHooks": [["id": "guard", "source": declaredSource]]
        ]
        let registry: [String: Any] = [
            "adapters": ["codex": ["path": "$HOME/.codex/hooks.json"]],
            "catalogChecksum": "stale",
            "catalog": catalog
        ]
        try JSONSerialization.data(withJSONObject: registry, options: [.sortedKeys])
            .write(to: managed.appendingPathComponent("registry.json"))
    }

    func seal(sourceRoot: URL?) throws -> (status: Int32, error: String) {
        var arguments = [scripts.appendingPathComponent("seal_hook_release.py").path]
        if let sourceRoot {
            arguments += ["--source-root", sourceRoot.path]
        }
        arguments.append(release.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3"] + arguments
        // With no stated root the script resolves against its working
        // directory, and this one holds none of the declared sources.
        process.currentDirectoryURL = root
        process.environment = [
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
            "HOME": root.path,
            "TAMA_HOOK_SOURCE_REVISION": "fixture-revision",
            "TAMA_HOOK_SOURCE_DIRTY": "false"
        ]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()
        try process.run()
        let data = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func mappings() throws -> [String: String] {
        let data = try Data(contentsOf: release.appendingPathComponent("external-sources.json"))
        let document = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let entries = document["mappings"] as? [[String: String]] ?? []
        return entries.reduce(into: [:]) { result, entry in
            if let prefix = entry["sourcePrefix"], let path = entry["releasePath"] {
                result[prefix] = path
            }
        }
    }

    func releaseDocument() throws -> [String: Any] {
        let data = try Data(contentsOf: release.appendingPathComponent("release.json"))
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    func sealedRegistry() throws -> [String: Any] {
        let data = try Data(contentsOf: release.appendingPathComponent("shared-hooks/registry.json"))
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
