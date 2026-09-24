import Foundation
import XCTest
@testable import TamaDesktop

final class ConsentTests: XCTestCase {
    @MainActor
    func testRealConsentPersistsRefusesExpansionAndRemoves() async throws {
        let environment = ProcessInfo.processInfo.environment
        func required(_ key: String) throws -> String {
            guard let value = environment[key], !value.isEmpty else {
                throw XCTSkip("\(key) is required for the real consent flow")
            }
            return value
        }
        let binary = try required("TAMA_TEST_CLI")
        let session = try required("TAMA_TEST_CUA_SESSION")
        let app = try required("TAMA_TEST_CUA_APP")
        let quoteMatch = try required("TAMA_TEST_CUA_MATCH")
        let actions = try required("TAMA_TEST_CUA_ACTIONS").split(separator: ",").map(String.init)
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let evidence = repo.appendingPathComponent(".build/consent-evidence/\(UUID().uuidString)")
        let home = evidence.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let revision = Process()
        let revisionOutput = Pipe()
        revision.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        revision.arguments = ["rev-parse", "HEAD"]
        revision.currentDirectoryURL = repo
        revision.standardOutput = revisionOutput
        try revision.run()
        let revisionData = revisionOutput.fileHandleForReading.readDataToEndOfFile()
        revision.waitUntilExit()
        XCTAssertEqual(revision.terminationStatus, .zero)
        try revisionData.write(to: evidence.appendingPathComponent("revision.txt"))
        var requestEnvironment = environment
        requestEnvironment["HOME"] = home.path
        requestEnvironment["TAMA_OMP_SESSION_ROOT"] = environment["TAMA_OMP_SESSION_ROOT"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".omp/agent/sessions").path
        defer { print("Native consent evidence: \(evidence.path)") }
        // Every call below is one `tama request` process, the way the
        // window runs them: nothing is started before the first call and
        // nothing is left running after the last.
        let client = CUAConsentClient(command: TamaCommand(
            executable: URL(fileURLWithPath: binary),
            root: nil,
            environment: requestEnvironment
        ))
        let recorded = try await client.record(session: session, app: app, actions: actions,
            quote: quoteMatch, match: true)
        let registry = home.appendingPathComponent(".shared-hooks/cua_justifications.json")
        let before = try Data(contentsOf: registry)
        try before.write(to: evidence.appendingPathComponent("recorded-state.json"))
        let listing = try await client.list()
        XCTAssertTrue(listing.authorizations.contains { $0.userRequestQuote == recorded.authorization.userRequestQuote })
        do {
            _ = try await client.record(session: session, app: app, actions: ["never_authorized_action"],
                quote: quoteMatch, match: true)
            XCTFail("An action not named by the user was accepted")
        } catch {
            try Data(error.localizedDescription.utf8).write(to: evidence.appendingPathComponent("refusal.txt"))
        }
        XCTAssertEqual(try Data(contentsOf: registry), before)
        _ = try await client.remove(quote: recorded.authorization.userRequestQuote)
        let after = try Data(contentsOf: registry)
        let persisted = try XCTUnwrap(JSONSerialization.jsonObject(with: after) as? [String: Any])
        XCTAssertEqual((persisted["authorizations"] as? [Any])?.count, .zero)
        let finalListing = try await client.list()
        XCTAssertTrue(finalListing.authorizations.isEmpty)
        try after.write(to: evidence.appendingPathComponent("final-state.json"))
    }
}
