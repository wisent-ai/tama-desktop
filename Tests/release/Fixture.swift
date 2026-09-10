import Foundation
import Testing

struct Fixture {
    let root: URL
    let release: URL
    let checkout: URL
    let sourceFile: URL
    private let scripts: URL
    private let reports: URL
    private(set) var revision = ""

    init(declaredSource: String = "rust/crates/tama-hook-tools/src/bin/block/stop/guard.rs") throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        scripts = repository.appendingPathComponent("Scripts", isDirectory: true)
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
            "sealer": scripts.appendingPathComponent("seal_hook_release.py").path
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
        var arguments = [scripts.appendingPathComponent("seal_hook_release.py").path]
        if let sourceRoot { arguments += ["--source-root", sourceRoot.path] }
        arguments.append(release.path)
        let environment = expectedRevision.map { ["TAMA_HOOK_SOURCE_REVISION": $0] } ?? [:]
        return try run("python3", arguments, environment: environment)
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
