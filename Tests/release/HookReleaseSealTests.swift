import Foundation
import Testing

/// `Scripts/hook_release/seal_hook_release.py` driven the way the release pipeline drives it.
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

/// Installing a staged release on a machine, driven the way an operator drives
/// it.
///
/// On 2026-09-11 a release was staged, sealed and verified, and then could not
/// be installed: the installer answered `Full hook installation requires an
/// emergency manifest`, and nothing in the product produces one for a machine
/// that has never been in the bypass. The operator ran an invocation outside
/// the contract, then a generator that narrowed both provider configs, and
/// `tama validate` reported a hundred and forty uninstalled hook events on a
/// machine whose hooks were meant to be complete.
///
/// The route that works is the bundled switch pointed at the release. These
/// cases drive the real scripts into a scratch home and read the symlink, the
/// provider configs and the drift report, because the defect was in what the
/// install produced and never in what it printed.
struct HookReleaseInstallTests {
    @Test
    func aFullInstallWithoutAManifestRefusesAndNamesWhatItNeeds() throws {
        let machine = try InstallFixture()

        let refused = try machine.installer(arguments: ["--release", machine.release.path,
                                                        "--home", machine.home.path])

        #expect(refused.status != .zero, "a full install has no manifest to apply here")
        #expect(refused.error.contains("emergency manifest"),
                "the refusal has to name what is missing: \(refused.error)")
        #expect(!FileManager.default.fileExists(atPath: machine.currentLink.path),
                "a refused install installs nothing")
    }

    @Test
    func theSwitchInstallsTheStagedReleaseAndLeavesNoDrift() throws {
        let machine = try InstallFixture()
        let identity = try machine.releaseIdentity()

        let disabled = try machine.switchRoute(action: "disable")
        #expect(disabled.status == .zero, "disable failed: \(disabled.error)")
        let enabled = try machine.switchRoute(action: "enable")
        #expect(enabled.status == .zero, "enable failed: \(enabled.error)")

        let installed = try FileManager.default
            .destinationOfSymbolicLink(atPath: machine.currentLink.path)
        #expect(installed.hasSuffix(identity),
                "current has to point at the release that was staged: \(installed)")
        #expect(enabled.output.contains(String(identity.prefix(12))),
                "the switch names the release it enabled: \(enabled.output)")

        // What an operator reads the report for: every catalogued hook the
        // providers support is wired, so no material drift is left behind.
        let report = try machine.validate()
        let drift = (report.output + report.error)
            .split(separator: "\n")
            .filter { $0.hasPrefix("ERROR install drift") }
        #expect(drift.isEmpty, "an installed release leaves no drift: \(drift.joined(separator: "\n"))")

        for provider in [machine.home.appendingPathComponent(".codex/hooks.json"),
                         machine.home.appendingPathComponent(".claude/settings.json")] {
            let text = try String(contentsOf: provider, encoding: .utf8)
            #expect(text.contains("record-current-assignment"),
                    "\(provider.lastPathComponent) has to carry what the catalogue declares")
        }
    }
}
