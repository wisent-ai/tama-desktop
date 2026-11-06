import Foundation
import XCTest

/// Real journeys of the bundled `Scripts/emergency_disable_hooks`, run as the
/// desktop runs it, against a home of the run's own under
/// `.build/emergency-switch/<run>` (`TAMA_HOME`), so the operator's switch is
/// never read or written:
///   - a disable without who, why or how long is refused, exit 2, before
///     anything is written;
///   - a switch written by hand, which set nothing aside, is lifted by an
///     enable, which removes it and says so;
///   - an enable with no switch and no manifest is refused;
///   - the expiry pass (`TAMA_EMERGENCY_TRIGGER=expiry`) leaves a switch that
///     has not expired alone and lifts one that has;
///   - with `TAMA_TEST_HOOK_RELEASE_ROOT` naming a staged release, a full
///     disable records setBy, reason, changedAt and expiresAt and schedules its
///     own lifting, and the expiry pass after the end restores every hook.
/// Run: `swift test --package-path tests/emergency-switch`. Each run's
/// commands, exit statuses and output land in `report.json` beside its home.
final class EmergencySwitchTests: XCTestCase {
    static let schema = "ai.wisent.tama.hook-emergency-state.v1"
    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let script = repository.appendingPathComponent("Scripts/emergency_disable_hooks")

    var run: URL!
    var home: URL!
    var commands: [[String: Any]] = []

    var tama: URL { home.appendingPathComponent("Library/Application Support/Tama") }
    var switchFile: URL { tama.appendingPathComponent("hook-emergency-state.json") }

    override func setUpWithError() throws {
        run = Self.repository.appendingPathComponent(".build/emergency-switch/\(UUID().uuidString)")
        home = run.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: tama, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        let report: [String: Any] = [
            "test": name,
            "sourceRevision": ProcessInfo.processInfo.environment["TAMA_TEST_SOURCE_REVISION"] as Any,
            "commands": commands,
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: run.appendingPathComponent("report.json"), options: .atomic)
        print("emergency switch evidence: \(run.path)")
    }

    /// Run the script with `environment` on the run's home.
    func script(_ environment: [String: String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [Self.script.path]
        var merged = ProcessInfo.processInfo.environment
        for name in ["TAMA_EMERGENCY_SET_BY", "TAMA_EMERGENCY_REASON", "TAMA_EMERGENCY_MINUTES", "TAMA_EMERGENCY_TRIGGER"] {
            merged.removeValue(forKey: name)
        }
        merged["TAMA_HOME"] = home.path
        merged.merge(environment) { _, given in given }
        process.environment = merged
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        commands.append(["environment": environment, "status": process.terminationStatus, "output": output])
        return (process.terminationStatus, output)
    }

    func writeSwitch(_ fields: [String: Any]) throws {
        var state: [String: Any] = ["schema": Self.schema, "disabled": true]
        state.merge(fields) { _, given in given }
        try JSONSerialization.data(withJSONObject: state).write(to: switchFile)
    }

    func readSwitch() throws -> [String: Any] {
        let value = try JSONSerialization.jsonObject(with: Data(contentsOf: switchFile))
        return try XCTUnwrap(value as? [String: Any], "the switch file holds no JSON object")
    }

    func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    func testADisableWithoutItsTermsIsRefusedBeforeAnythingIsWritten() throws {
        let terms = ["TAMA_EMERGENCY_SET_BY": "operator", "TAMA_EMERGENCY_REASON": "a gate wedged every edit",
                     "TAMA_EMERGENCY_MINUTES": "30"]
        for missing in terms.keys.sorted() {
            var given = terms
            given.removeValue(forKey: missing)
            given["TAMA_EMERGENCY_ACTION"] = "disable"
            let answer = try script(given)
            XCTAssertEqual(answer.status, 2, answer.output)
            XCTAssertTrue(answer.output.contains("Tama will not disable its hooks without \(missing)"), answer.output)
        }
        var zero = terms
        zero["TAMA_EMERGENCY_MINUTES"] = "0"
        let answer = try script(zero)
        XCTAssertEqual(answer.status, 2, answer.output)
        XCTAssertTrue(answer.output.contains("it must be a whole number of minutes above zero"), answer.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: switchFile.path), "a refused disable wrote the switch")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tama.appendingPathComponent("emergency-backup/manifest.json").path),
                       "a refused disable wrote a manifest")
    }

    func testAnEnableLiftsAHandWrittenSwitchThatSetNothingAside() throws {
        try writeSwitch(["changedAt": "Sun Nov  1 17:06:03 UTC 2026"])
        let answer = try script(["TAMA_EMERGENCY_ACTION": "enable"])
        XCTAssertEqual(answer.status, 0, answer.output)
        XCTAssertTrue(answer.output.contains("Lifted an emergency switch that set nothing aside"), answer.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: switchFile.path), "the lifted switch is still on disk")

        let again = try script(["TAMA_EMERGENCY_ACTION": "enable"])
        XCTAssertNotEqual(again.status, 0, again.output)
        XCTAssertTrue(again.output.contains("Tama has no emergency switch set and no emergency backup manifest to restore."),
                      again.output)
    }

    func testTheExpiryPassWaitsForTheEndAndThenLifts() throws {
        try writeSwitch(["setBy": "operator", "reason": "a gate wedged every edit",
                         "changedAt": iso(Date()), "expiresAt": iso(Date().addingTimeInterval(3600))])
        let early = try script(["TAMA_EMERGENCY_ACTION": "enable", "TAMA_EMERGENCY_TRIGGER": "expiry"])
        XCTAssertEqual(early.status, 0, early.output)
        XCTAssertEqual(try readSwitch()["reason"] as? String, "a gate wedged every edit",
                       "the expiry pass touched a switch before its end")

        try writeSwitch(["setBy": "operator", "reason": "a gate wedged every edit",
                         "changedAt": iso(Date().addingTimeInterval(-7200)), "expiresAt": iso(Date().addingTimeInterval(-60))])
        let late = try script(["TAMA_EMERGENCY_ACTION": "enable", "TAMA_EMERGENCY_TRIGGER": "expiry"])
        XCTAssertEqual(late.status, 0, late.output)
        XCTAssertTrue(late.output.contains("The emergency switch expired at"), late.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: switchFile.path), "an expired switch was not lifted")
    }

    func testAFullDisableRecordsItsTermsAndLiftsItselfAfterTheEnd() throws {
        guard let release = ProcessInfo.processInfo.environment["TAMA_TEST_HOOK_RELEASE_ROOT"] else {
            throw XCTSkip("TAMA_TEST_HOOK_RELEASE_ROOT names no staged hook release, so a full disable cannot run: blocked, not passed")
        }
        let answer = try script(["TAMA_EMERGENCY_ACTION": "disable", "TAMA_HOOK_RELEASE_ROOT": release,
                                 "TAMA_EMERGENCY_SET_BY": "operator", "TAMA_EMERGENCY_REASON": "a gate wedged every edit",
                                 "TAMA_EMERGENCY_MINUTES": "15"])
        XCTAssertEqual(answer.status, 0, answer.output)
        XCTAssertTrue(answer.output.contains("Disabled hooks for 15 minutes."), answer.output)
        let state = try readSwitch()
        XCTAssertEqual(state["setBy"] as? String, "operator")
        XCTAssertEqual(state["reason"] as? String, "a gate wedged every edit")
        let changed = try XCTUnwrap(ISO8601DateFormatter.fractional(state["changedAt"] as? String))
        let ends = try XCTUnwrap(ISO8601DateFormatter.fractional(state["expiresAt"] as? String))
        XCTAssertEqual(ends.timeIntervalSince(changed), 15 * 60, accuracy: 1)
        let agents = try FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent("Library/LaunchAgents").path)
        XCTAssertTrue(agents.contains { $0.hasPrefix("ai.wisent.tama.emergency-expiry.") }, "no expiry agent was scheduled: \(agents)")

        var expired = state
        expired["expiresAt"] = iso(Date().addingTimeInterval(-1))
        try JSONSerialization.data(withJSONObject: expired).write(to: switchFile)
        let lifted = try script(["TAMA_EMERGENCY_ACTION": "enable", "TAMA_EMERGENCY_TRIGGER": "expiry",
                                 "TAMA_HOOK_RELEASE_ROOT": release])
        XCTAssertEqual(lifted.status, 0, lifted.output)
        XCTAssertTrue(lifted.output.contains("Enabled approved hook release"), lifted.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: switchFile.path), "the expired switch was not removed")
        let left = try FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent("Library/LaunchAgents").path)
        XCTAssertFalse(left.contains { $0.hasPrefix("ai.wisent.tama.emergency-expiry.") }, "the expiry agent outlived the switch")
    }
}

extension ISO8601DateFormatter {
    /// A date the script writes (`…T…[.ffffff]Z`), or nil.
    static func fractional(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
