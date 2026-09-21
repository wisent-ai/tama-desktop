import Foundation
import Testing
@testable import TamaDesktop

/// The Hooks screen's warm panel, against the real backend it calls.
///
/// A hook binary that has never run pays the operating system's first-run
/// assessment inside the next live event, and the whole turn waits for it:
/// on 2026-09-20 a freshly installed `tama-block-delegating-own-work` spent
/// 147 seconds there while the binary itself answers in four milliseconds.
/// The terminal pays that with `tama hooks warm`; the
/// window has the same button, and it is worth nothing unless the route it
/// calls answers the document the panel reads.
///
/// So this starts the real `tama-cli serve`, calls the real route through the
/// desktop's own client, and reads the report and the refusal.
struct HookWarmBackendTests {
    /// The checkout that holds this file's sibling repositories.
    private static var workspace: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// The CLI this machine builds, then the one it installs.
    private static func backendExecutable() -> URL? {
        let candidates = [
            workspace.appendingPathComponent("tama/rust/target/release/tama-cli"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/tama-cli"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Start the backend and return its base URL, or nil when this machine
    /// holds no built CLI and no checkout to serve.
    private static func startBackend() throws -> (Process, URL)? {
        guard let executable = backendExecutable() else { return nil }
        let checkout = workspace.appendingPathComponent("tama")
        guard FileManager.default.fileExists(
            atPath: checkout.appendingPathComponent("shared-hooks/registry.json").path
        ) else { return nil }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["serve", "--port", "0", "--root", checkout.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let handle = output.fileHandleForReading
        var buffer = Data()
        while !buffer.contains(UInt8(ascii: "\n")) {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
        }
        let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) ?? buffer.endIndex
        let line = Data(buffer[buffer.startIndex..<newline])
        guard
            let ready = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let port = (ready["port"] as? NSNumber)?.intValue,
            let url = URL(string: "http://127.0.0.1:\(port)")
        else {
            process.terminate()
            Issue.record("the backend announced no port: \(String(decoding: buffer, as: UTF8.self))")
            return nil
        }
        return (process, url)
    }

    @Test
    func theWindowReadsAMeasuredWarmReportFromTheRealBackend() async throws {
        guard let (process, baseURL) = try Self.startBackend() else { return }
        defer { process.terminate() }
        let client = TamaClient(baseURL: baseURL)

        let report = try await client.post(
            "hooks/warm",
            body: ["only": ["block-delegating-own-work"]],
            as: HookWarmReport.self,
            operation: "warm the machine's hook binaries"
        )

        let row = try #require(report.hooks.first)
        #expect(report.hooks.count == report.warmed + report.unusable)
        #expect(row.id == "block-delegating-own-work")
        // Either the binary is installed and was measured, or it is not on
        // this machine and the panel has to say so rather than claim a run.
        if FileManager.default.isExecutableFile(atPath: row.path) {
            #expect(row.isUsable)
            #expect(report.slowest == row.id)
            #expect(report.slowestMs == row.elapsedMs)
        } else {
            #expect(!row.isUsable)
            #expect(report.unusable == report.hooks.count)
            #expect(report.slowest == nil)
        }
    }

    @Test
    func anUnknownHookIsRefusedWithTheBackendsOwnSentence() async throws {
        guard let (process, baseURL) = try Self.startBackend() else { return }
        defer { process.terminate() }
        let client = TamaClient(baseURL: baseURL)

        await #expect(throws: TamaBackendError.self) {
            _ = try await client.post(
                "hooks/warm",
                body: ["only": ["block-nothing-at-all"]],
                as: HookWarmReport.self,
                operation: "warm the machine's hook binaries"
            )
        }
    }
}
