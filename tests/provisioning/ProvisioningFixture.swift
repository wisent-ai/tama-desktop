import CryptoKit
import Foundation

struct ProvisioningQualificationError: Error, CustomStringConvertible {
    let description: String
}

/// Real Stado commands and their retained nonsecret responses. No credential
/// value is read by the test; Stado and the owner vault keep that boundary.
final class ProvisioningFixture {
    let root: URL
    let evidence: URL
    let executable: URL
    let host: String
    let apiKeyItem: String
    let incompleteKeyItem: String
    let appBundle: String
    let extensionBundle: String
    let item = "tama-provisioning-qualification-\(UUID().uuidString.lowercased())"
    var report: [String: Any] = ["status": "running", "commands": []]

    static func required(_ name: String, evidence: URL? = nil) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
            let error = ProvisioningQualificationError(description: "\(name) is required for real provisioning qualification")
            if let evidence {
                do {
                    try JSONSerialization.data(withJSONObject: ["status": "blocked", "error": error.description],
                        options: [.prettyPrinted, .sortedKeys])
                        .write(to: evidence.appendingPathComponent("report.json"), options: .atomic)
                } catch let publication {
                    throw ProvisioningQualificationError(description:
                        "\(error.description)\npublishing blocked evidence at \(evidence.path) failed: \(String(reflecting: publication))")
                }
                print("blocked provisioning evidence: \(evidence.path)")
            }
            throw error
        }
        return value
    }

    init() throws {
        root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        evidence = root.appendingPathComponent(".build/provisioning-qualification/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        executable = URL(fileURLWithPath: try Self.required("TAMA_TEST_STADO_EXECUTABLE", evidence: evidence))
            .resolvingSymlinksInPath()
        host = try Self.required("TAMA_TEST_ISOLATED_VAULT_HOST", evidence: evidence)
        apiKeyItem = try Self.required("TAMA_TEST_PROVISIONING_API_KEY_ITEM", evidence: evidence)
        incompleteKeyItem = try Self.required("TAMA_TEST_INCOMPLETE_API_KEY_ITEM", evidence: evidence)
        appBundle = try Self.required("TAMA_TEST_ISOLATED_APP_BUNDLE_ID", evidence: evidence)
        extensionBundle = try Self.required("TAMA_TEST_ISOLATED_EXTENSION_BUNDLE_ID", evidence: evidence)
        report["started_at"] = ISO8601DateFormatter().string(from: Date())
        report["host"] = host
        report["item"] = item
        report["stado_executable"] = executable.path
        do {
            let expectedRevision = try Self.required("TAMA_TEST_SOURCE_REVISION")
            report["expected_source_revision"] = expectedRevision
            let expectedDigest = try Self.required("TAMA_TEST_STADO_SHA256")
            report["expected_stado_sha256"] = expectedDigest
            try persist()
            let digest = Self.digest(try Data(contentsOf: executable))
            report["stado_sha256"] = digest
            try persist()
            guard digest == expectedDigest else {
                throw ProvisioningQualificationError(description:
                    "Stado executable \(executable.path) has SHA-256 \(digest); TAMA_TEST_STADO_SHA256 requires \(expectedDigest)")
            }
            let revision = try git(["rev-parse", "HEAD"])
            report["source_revision"] = revision
            try persist()
            guard revision == expectedRevision else {
                throw ProvisioningQualificationError(description:
                    "checkout \(root.path) has revision \(revision); TAMA_TEST_SOURCE_REVISION requires \(expectedRevision)")
            }
            let files = ["tests/provisioning/Package.swift", ".wisent-release.json",
                "tests/provisioning/ProvisioningFixture.swift", "tests/provisioning/ProvisioningTests.swift"]
            _ = try git(["ls-files", "--error-unmatch", "--"] + files)
            _ = try git(["diff", "--exit-code", "HEAD", "--"] + files)
            report["source_sha256"] = try Dictionary(uniqueKeysWithValues: files.map { file in
                (file, Self.digest(try Data(contentsOf: root.appendingPathComponent(file))))
            })
            try persist()
        } catch {
            report["status"] = "blocked"
            report["error"] = String(reflecting: error)
            print("blocked provisioning evidence: \(evidence.path)")
            try persist(preserving: [error])
            throw error
        }
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func git(_ arguments: [String]) throws -> String {
        let result = try execute(URL(fileURLWithPath: "/usr/bin/git"), arguments)
        guard result.status == EXIT_SUCCESS else {
            throw ProvisioningQualificationError(description:
                "git \(arguments) exited \(result.status)\nstdout:\n\(result.output)\nstderr:\n\(result.error)\nevidence: \(evidence.path)")
        }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    struct Result {
        let status: Int32
        let output: String
        let error: String
    }

    func execute(_ program: URL, _ arguments: [String]) throws -> Result {
        let identifier = UUID().uuidString
        let stdout = evidence.appendingPathComponent("\(identifier).stdout")
        let stderr = evidence.appendingPathComponent("\(identifier).stderr")
        var record: [String: Any] = ["executable": program.path, "arguments": arguments,
            "stdout": stdout.path, "stderr": stderr.path, "state": "preparing",
            "started_at": ISO8601DateFormatter().string(from: Date())]
        var commands = report["commands"] as? [[String: Any]] ?? []
        let index = commands.endIndex
        commands.append(record)
        func retain() throws {
            commands[index] = record
            report["commands"] = commands
            try persist()
        }
        try retain()
        let output: FileHandle
        let errors: FileHandle
        do {
            try Data().write(to: stdout)
            try Data().write(to: stderr)
            output = try FileHandle(forWritingTo: stdout)
            do { errors = try FileHandle(forWritingTo: stderr) }
            catch {
                do { try output.close() }
                catch { record["stdout_close_error"] = String(reflecting: error) }
                throw error
            }
        } catch {
            record["state"] = "preparation_failed"
            record["preparation_error"] = String(reflecting: error)
            commands[index] = record
            report["commands"] = commands
            try persist(preserving: [error])
            throw error
        }
        let process = Process()
        process.executableURL = program
        process.arguments = arguments
        process.currentDirectoryURL = root
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors
        var problems: [String] = []
        var launched = false
        do {
            try process.run()
            launched = true
            record["pid"] = process.processIdentifier
            record["state"] = "running"
            do { try retain() }
            catch {
                let cause = "publishing in-flight evidence failed: \(String(reflecting: error))"
                problems.append(cause)
                record["publication_error"] = cause
                FileHandle.standardError.write(Data("provisioning command \(record): \(cause)\n".utf8))
            }
            process.waitUntilExit()
            record["state"] = "terminated"
            record["exit_status"] = process.terminationStatus
            record["termination_reason"] = process.terminationReason.rawValue
            if process.terminationReason != .exit {
                problems.append("\(program.path) terminated by signal: \(process.terminationStatus)")
            }
        } catch {
            record["state"] = "launch_failed"
            record["launch_error"] = String(reflecting: error)
            problems.append("\(program.path) did not launch: \(String(reflecting: error))")
        }
        for (channel, handle) in [("stdout", output), ("stderr", errors)] {
            do { try handle.close() }
            catch {
                let cause = "\(channel) closure failed: \(String(reflecting: error))"
                record["\(channel)_close_error"] = cause
                problems.append(cause)
            }
        }
        var result: Result?
        if launched {
            do {
                result = Result(status: process.terminationStatus,
                    output: String(decoding: try Data(contentsOf: stdout), as: UTF8.self),
                    error: String(decoding: try Data(contentsOf: stderr), as: UTF8.self))
            } catch {
                record["output_read_error"] = String(reflecting: error)
                problems.append("reading command output failed: \(String(reflecting: error))")
            }
        }
        record["finished_at"] = ISO8601DateFormatter().string(from: Date())
        do { try retain() }
        catch { problems.append("publishing terminal evidence failed: \(String(reflecting: error))") }
        if !problems.isEmpty {
            var detail = "provisioning command observed state: \(record)\n" + problems.joined(separator: "\n")
            if let result { detail += "\nstdout: \(result.output)\nstderr: \(result.error)" }
            throw ProvisioningQualificationError(description: detail)
        }
        guard let result else {
            throw ProvisioningQualificationError(description: "command produced no readable result: \(record)")
        }
        return result
    }

    func command(_ arguments: [String]) throws -> [String: Any] {
        let result = try execute(executable, arguments)
        guard result.status == EXIT_SUCCESS else {
            throw ProvisioningQualificationError(description: "Stado \(arguments) failed: \(result.error)\n\(result.output)")
        }
        guard let value = try JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any] else {
            throw ProvisioningQualificationError(description: "Stado returned no JSON object: \(result.output)")
        }
        return value
    }

    func persist() throws {
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: evidence.appendingPathComponent("report.json"), options: .atomic)
    }

    func persist(preserving failures: [Error]) throws {
        var causes = failures.map { String(reflecting: $0) }
        do { try persist() }
        catch {
            causes.append("publishing evidence at \(evidence.path) failed: \(String(reflecting: error)); observed report: \(report)")
        }
        if !causes.isEmpty {
            throw ProvisioningQualificationError(description: causes.joined(separator: "\n"))
        }
    }
}
