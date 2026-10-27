import CryptoKit
import Foundation
import XCTest
@testable import TamaDesktop

/// Why a review-diagnostics journey refuses to start.
enum ReviewDiagnosticsPrerequisite: Error {
    case missingDeclaration(String)
    case unsafeReporting(String)
}

/// The isolated real-backend client every review-diagnostics journey runs
/// against, and where it keeps what it observed.
extension XCTestCase {
    private func declared(_ name: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
            throw ReviewDiagnosticsPrerequisite.missingDeclaration(name)
        }
        return value
    }

    private func requireIsolatedReporting(root: URL) throws {
        let build = root.deletingLastPathComponent().deletingLastPathComponent()
            .resolvingSymlinksInPath()
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
        let environment = ProcessInfo.processInfo.environment
        guard home.path.hasPrefix(build.path + "/"),
            environment["PROBIERZ_INTAKE_URL"] == nil,
            environment["PROBIERZ_INTAKE_TOKEN"] == nil,
            !FileManager.default.fileExists(
                atPath: home.appendingPathComponent(".probierz/intake-token").path)
        else {
            throw ReviewDiagnosticsPrerequisite.unsafeReporting(
                "Run with an isolated Foundation home below \(build.path), no intake environment "
                    + "and no intake token file; the operator's failure intake must not be changed."
            )
        }
    }

    /// The Git tree of the desktop source bytes this run compiled, written
    /// through a private index below the source's ignored build directory, so
    /// a run names exactly what it built: a candidate's tree when it runs on
    /// an extracted candidate, and the working tree (whatever it carries) when
    /// it runs in the checkout. An extracted candidate has no `.git`; its
    /// objects are read from the repository `TAMA_DESKTOP_GIT_DIR` names.
    private func observedSource(of directory: URL) throws -> (tree: String, head: String) {
        let marker = directory.appendingPathComponent(".git")
        let gitDir = FileManager.default.fileExists(atPath: marker.path)
            ? marker.path : try declared("TAMA_DESKTOP_GIT_DIR")
        let index = directory.appendingPathComponent(".build/review-diagnostics-\(UUID().uuidString).index")
        func git(_ arguments: [String]) throws -> String {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["--git-dir", gitDir, "--work-tree", directory.path] + arguments
            process.environment = ProcessInfo.processInfo.environment
                .merging(["GIT_INDEX_FILE": index.path]) { _, chosen in chosen }
            process.standardOutput = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == EXIT_SUCCESS else {
                throw ReviewDiagnosticsPrerequisite.missingDeclaration(
                    "git \(arguments.joined(separator: " ")) over \(directory.path) exited \(process.terminationStatus)")
            }
            return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        _ = try git(["add", "--all", "--", "."])
        addTeardownBlock { try FileManager.default.removeItem(at: index) }
        return (try git(["write-tree"]), try git(["rev-parse", "HEAD"]))
    }

    func fixture() throws -> (client: TamaClient, root: URL, provider: URL) {
        let executable = URL(fileURLWithPath: try declared("TAMA_TEST_EXECUTABLE")).resolvingSymlinksInPath()
        let checkout = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try observedSource(of: checkout)
        let root = checkout.appendingPathComponent(".build/review-diagnostics/\(UUID().uuidString)")
        try requireIsolatedReporting(root: root)
        let home = root.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        let provider = home.appendingPathComponent("provider.json")
        let client = TamaClient(command: TamaCommand(
            executable: executable, root: nil,
            environment: ["HOME": home.path, "TAMA_MODEL_PROVIDER_PATH": provider.path]
        ))
        // Observed, not declared: the Git tree of the desktop bytes compiled
        // and the backend by the digest of the bytes executed. A run qualifies
        // a candidate only when `desktopSourceTree` is that candidate's tree.
        let identity: [String: Any] = [
            "desktopSourceTree": source.tree,
            "desktopRepositoryHead": source.head,
            "backendExecutable": executable.path,
            "backendExecutableSha256": SHA256.hash(data: try Data(contentsOf: executable))
                .map { String(format: "%02x", $0) }.joined()
        ]
        try JSONSerialization.data(withJSONObject: identity, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("identity.json"))
        return (client, root, provider)
    }
}
