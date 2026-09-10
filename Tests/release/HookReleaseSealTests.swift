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

        let result = try fixture.seal(sourceRoot: fixture.checkout)

        #expect(result.status == .zero, "sealing failed: \(result.error)")
        let mappings = try fixture.mappings()
        // The installer matches this prefix against the value the registry
        // declares. Recording the absolute path it resolved to here left every
        // installed hook with no source at all.
        #expect(mappings.values.contains("external-hooks/guard/guard.rs"))
        #expect(mappings.keys.contains { $0.hasSuffix("block/stop/guard.rs") })
        let staged = fixture.release.appendingPathComponent("external-hooks/guard/guard.rs")
        #expect(try Data(contentsOf: staged) == Data(contentsOf: fixture.sourceFile))
        let release = try fixture.releaseDocument()
        #expect(release["sourceRevision"] as? String == fixture.revision)
        #expect(release["sourceDirty"] as? Bool == false)
    }

    @Test
    func sealStatesTheCheckoutSoTheInstallerCannotDoubleTheHome() throws {
        let fixture = try Fixture()

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
    }

    @Test
    func sealRefusesFromTheWrongRootAndNamesTheRootItUsed() throws {
        let fixture = try Fixture()

        let result = try fixture.seal(sourceRoot: nil)

        #expect(result.status != .zero, "sealing should refuse when the root is wrong")
        #expect(result.error.contains(fixture.root.path))
        #expect(result.error.contains("Git checkout root"))
        #expect(!FileManager.default.fileExists(
            atPath: fixture.release.appendingPathComponent("release.json").path
        ))
    }

    @Test
    func sealLeavesManagedHookDirectoriesOutOfTheExternalManifest() throws {
        let fixture = try Fixture(declaredSource: "shared-hooks/pre_bash.sh")

        let result = try fixture.seal(sourceRoot: fixture.checkout)

        #expect(result.status == .zero, "sealing failed: \(result.error)")
        // A hook shipped inside the release needs no external copy; packaging
        // one would install a second source of the same hook.
        #expect(try fixture.mappings().isEmpty)
    }

    @Test
    func sealRecordsDirtySourceWithoutAnEnvironmentOverride() throws {
        let fixture = try Fixture()
        try Data("//! changed source input\n".utf8).write(to: fixture.sourceFile)
        let result = try fixture.seal(sourceRoot: fixture.checkout)
        #expect(result.status == .zero, "\(result.error)")
        let release = try fixture.releaseDocument()
        #expect(release["sourceRevision"] as? String == fixture.revision)
        #expect(release["sourceDirty"] as? Bool == true)
    }

    @Test
    func sealRefusesARevisionThatDisagreesWithGit() throws {
        let fixture = try Fixture()
        let result = try fixture.seal(sourceRoot: fixture.checkout, expectedRevision: "not-the-checkout-revision")
        #expect(result.status != .zero)
        #expect(result.error.contains("TAMA_HOOK_SOURCE_REVISION"))
        #expect(result.error.contains(fixture.revision))
        #expect(!FileManager.default.fileExists(atPath: fixture.release.appendingPathComponent("release.json").path))
    }

    @Test
    func sealRefusesNativeMetadataWithoutCapturedSourceIdentity() throws {
        let fixture = try Fixture()
        let manifest = fixture.release.appendingPathComponent("native-hook-binaries.json")
        try Data("{\"schema\":\"ai.wisent.tama.native-hook-binaries.v1\",\"hooks\":[],\"additionalExecutables\":[]}".utf8)
            .write(to: manifest)
        let result = try fixture.seal(sourceRoot: fixture.checkout)
        #expect(result.status != .zero)
        #expect(result.error.contains(manifest.path))
        #expect(result.error.contains("restage"))
        #expect(!FileManager.default.fileExists(atPath: fixture.release.appendingPathComponent("release.json").path))
    }
}
