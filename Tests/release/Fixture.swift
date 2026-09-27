import Foundation
import Testing

struct Fixture {
    let root: URL
    let release: URL
    let checkout: URL
    let sourceFile: URL
    private let tama: URL
    private let reports: URL
    private(set) var revision = ""

    init(declaredSource: String = "rust/crates/tama-hook-tools/src/bin/block/stop/guard.rs") throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        // The sealer is the tama program built from the hook checkout beside this one.
        tama = repository.deletingLastPathComponent()
            .appendingPathComponent("tama/rust/target/release/tama")
        root = repository.appendingPathComponent(".build/release-evidence", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        release = root.appendingPathComponent("release", isDirectory: true)
        checkout = root.appendingPathComponent("checkout", isDirectory: true)
        sourceFile = checkout.appendingPathComponent(declaredSource)
        reports = root.appendingPathComponent("reports", isDirectory: true)
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        let managed = release.appendingPathComponent("shared-hooks", isDirectory: true)
        try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let source = declaredSource.hasPrefix("shared-hooks/")
            ? Data("#!/bin/bash\n".utf8) : Data("//! real source input retained by the sealer test\n".utf8)
        try source.write(to: sourceFile)
        try Data("#!/bin/bash\n".utf8).write(to: managed.appendingPathComponent("pre_bash.sh"))
        try Data("{\"version\":\"fixture\"}\n".utf8).write(to: release.appendingPathComponent("package.json"))
        let registry: [String: Any] = [
            "adapters": ["codex": ["path": "$HOME/.codex/hooks.json"]],
            "catalogChecksum": "stale",
            "catalog": [
                "maintainedIn": "shared-hooks/registry.json",
                "version": Int("1")!,
                "updatedAt": "2026-09-08T00:00:00Z",
                "agentHooks": [["id": "guard", "source": declaredSource]]
            ]
        ]
        try JSONSerialization.data(withJSONObject: registry, options: [.sortedKeys])
            .write(to: managed.appendingPathComponent("registry.json"))
        _ = try git(["init", "--quiet"])
        _ = try git(["add", "."])
        _ = try git(["-c", "user.name=Tama Release Tests", "-c", "user.email=tama-tests@example.invalid",
                     "commit", "--quiet", "-m", "record isolated release source"])
        revision = try git(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let owner = try run("git", ["-C", repository.path, "rev-parse", "HEAD"])
        #expect(owner.status == .zero, "\(owner.error)")
        let identity: [String: Any] = [
            "sourceRevision": owner.output.trimmingCharacters(in: .whitespacesAndNewlines),
            "fixtureRevision": revision,
            "sealer": tama.path
        ]
        try JSONSerialization.data(withJSONObject: identity, options: [.sortedKeys, .prettyPrinted])
            .write(to: reports.appendingPathComponent("run.json"))
        print("Retained release evidence: \(reports.path)")
    }

    func run(_ program: String, _ arguments: [String], environment: [String: String] = [:]) throws
        -> (status: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [program] + arguments
        process.currentDirectoryURL = root
        var isolated = [
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
            "HOME": root.path,
            "GIT_CONFIG_GLOBAL": root.appendingPathComponent("gitconfig").path,
            "GIT_CONFIG_NOSYSTEM": "1"
        ]
        isolated.merge(environment) { _, replacement in replacement }
        process.environment = isolated
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let error = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let result = (status: process.terminationStatus,
                      output: String(decoding: output, as: UTF8.self),
                      error: String(decoding: error, as: UTF8.self))
        let report: [String: Any] = [
            "arguments": [program] + arguments, "cwd": root.path,
            "exitStatus": result.status, "terminationReason": process.terminationReason.rawValue,
            "stdout": result.output, "stderr": result.error
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
            .write(to: reports.appendingPathComponent("\(UUID().uuidString).json"))
        return result
    }

    func git(_ arguments: [String]) throws -> String {
        let result = try run("git", ["-C", checkout.path] + arguments)
        guard result.status == .zero else {
            throw NSError(domain: "TamaReleaseFixture", code: Int(result.status),
                          userInfo: [NSLocalizedDescriptionKey: result.error])
        }
        return result.output
    }

    func seal(sourceRoot: URL?, expectedRevision: String? = nil) throws
        -> (status: Int32, output: String, error: String) {
        var arguments = ["hooks", "seal"]
        if let sourceRoot { arguments += ["--source-root", sourceRoot.path] }
        arguments.append(release.path)
        let environment = expectedRevision.map { ["TAMA_HOOK_SOURCE_REVISION": $0] } ?? [:]
        return try run(tama.path, arguments, environment: environment)
    }

    func mappings() throws -> [String: String] {
        let data = try Data(contentsOf: release.appendingPathComponent("external-sources.json"))
        let document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try #require(document["mappings"] as? [[String: String]])
        return entries.reduce(into: [:]) { result, entry in
            if let prefix = entry["sourcePrefix"], let path = entry["releasePath"] {
                result[prefix] = path
            }
        }
    }

    func releaseDocument() throws -> [String: Any] {
        let data = try Data(contentsOf: release.appendingPathComponent("release.json"))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func sealedRegistry() throws -> [String: Any] {
        let data = try Data(contentsOf: release.appendingPathComponent("shared-hooks/registry.json"))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

/// A machine to install a release onto: a scratch home, and the real staged
/// release from the hook checkout beside this one.
///
/// Staging and sealing are the pipeline's own scripts, so what is installed
/// here is the same tree an operator installs, not a hand-built stand-in.
struct InstallFixture {
    let root: URL
    let home: URL
    let release: URL
    private let switchScript: URL
    private let hookCheckout: URL
    private let reports: URL

    var currentLink: URL {
        home.appendingPathComponent("Library/Application Support/Tama/hooks-runtime/current")
    }

    init() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        switchScript = repository.appendingPathComponent("Scripts/emergency_disable_hooks")
        hookCheckout = repository.deletingLastPathComponent()
            .appendingPathComponent("tama", isDirectory: true)
        root = repository.appendingPathComponent(".build/install-evidence", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        let output = root.appendingPathComponent("build", isDirectory: true)
        release = output.appendingPathComponent("stage/share/tama/hook-release", isDirectory: true)
        reports = root.appendingPathComponent("reports", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        #expect(FileManager.default.fileExists(atPath: hookCheckout.path),
                "the hook source checkout has to be beside this one: \(hookCheckout.path)")
        // Tama's own release build assembles, stages and seals the hook
        // release from the checkout's committed tree, the same way a fleet
        // build does; it builds with the machine's toolchain and writes only
        // into the output directory, so it runs with the machine's own home.
        let revision = try run("git", ["-C", hookCheckout.path, "rev-parse", "HEAD"])
        #expect(revision.status == .zero, "\(revision.error)")
        let built = try run("bash", [hookCheckout.appendingPathComponent("release/build.sh").path],
                            environment: [
                                "HOME": NSHomeDirectory(),
                                "WISENT_SOURCE_DIR": hookCheckout.path,
                                "WISENT_SOURCE_COMMIT": revision.output
                                    .trimmingCharacters(in: .whitespacesAndNewlines),
                                "WISENT_OUTPUT_DIR": output.path
                            ])
        #expect(built.status == .zero, "building the hook release failed: \(built.error)")
        print("Retained install evidence: \(reports.path)")
    }

    func releaseIdentity() throws -> String {
        let data = try Data(contentsOf: release.appendingPathComponent("release.json"))
        let document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(document["releaseId"] as? String)
    }

    func installer(arguments: [String]) throws -> (status: Int32, output: String, error: String) {
        try run(release.appendingPathComponent("bin/tama").path, ["hooks", "install-release"] + arguments)
    }

    /// The bundled switch, pointed at this release and this home: the route the
    /// product documents for installing a release on a machine.
    func switchRoute(action: String) throws -> (status: Int32, output: String, error: String) {
        try run("sh", [switchScript.path],
                environment: [
                    "TAMA_HOME": home.path,
                    "TAMA_EMERGENCY_ACTION": action,
                    "TAMA_SKIP_SESSION_RESTART": "1",
                    "TAMA_HOOK_RELEASE_ROOT": release.path,
                    "TAMA_HOOK_INSTALLER": release.appendingPathComponent("bin/tama").path
                ])
    }

    /// The sealed CLI reading this home's installed configs against the
    /// catalogue in the hook checkout.
    func validate() throws -> (status: Int32, output: String, error: String) {
        try run(release.appendingPathComponent("bin/tama").path, ["validate"],
                environment: ["HOME": home.path, "TAMA_ROOT": hookCheckout.path],
                directory: hookCheckout)
    }

    private func run(_ program: String, _ arguments: [String],
                     environment: [String: String] = [:],
                     directory: URL? = nil) throws
        -> (status: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [program] + arguments
        process.currentDirectoryURL = directory ?? root
        var isolated = [
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
            "HOME": home.path
        ]
        isolated.merge(environment) { _, replacement in replacement }
        process.environment = isolated
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let error = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let result = (status: process.terminationStatus,
                      output: String(decoding: output, as: UTF8.self),
                      error: String(decoding: error, as: UTF8.self))
        let report: [String: Any] = [
            "arguments": [program] + arguments, "home": home.path,
            "exitStatus": result.status, "stdout": result.output, "stderr": result.error
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
            .write(to: reports.appendingPathComponent("\(UUID().uuidString).json"))
        return result
    }
}
