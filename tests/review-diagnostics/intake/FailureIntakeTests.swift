import CryptoKit
import Foundation
import Network
import WisentAuth
import WisentErrors
import XCTest
@testable import TamaDesktop

/// Why the intake journey refuses to start or could not observe its intake.
enum FailureIntakePrerequisite: Error {
    case missingDeclaration(String)
    case observation(String)
}

/// Failures the violations screen shows reach the operator's failure intake
/// once per failed operation. The intake is the installed Probierz, listening
/// on a port the system chose and keeping every accepted envelope in its own
/// failures directory; the backend is the declared Tama; the screen is the
/// production `ViolationsModel`, given the fixture's command instead of the
/// sealed release a signed app carries. The authorization the screen requires
/// is constructed with the member role; sign-in is not what this qualifies.
///
/// Every issued report is awaited with `TamaFailureReporting.settle` before
/// the journal is read, so the stored records are final. A stored detail is
/// compared with the screen's sentence as the pinned reporter builds it
/// (`Failure.detail` trims surrounding whitespace); the raw sentence and the
/// raw journal are kept beside the verdict.
final class FailureIntakeTests: XCTestCase, @unchecked Sendable {
    /// A cleanup the backend refuses because another run already holds the
    /// repository's lock ends `locked` with a failing status before any model
    /// is asked, and is stored once.
    @MainActor
    func testRefusedCleanupReachesTheIntakeOnce() async throws {
        let run = try await intakeRun()
        let repository = try freshRepository(in: run.root)
        let lock = run.state.appendingPathComponent("clean-locks", isDirectory: true)
            .appendingPathComponent(lockName(for: repository.path), isDirectory: true)
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: true)
        run.model.select(repository: repository.path)
        await run.model.clean()
        guard case .failed(let sentence) = run.model.cleanState else {
            return XCTFail("A locked cleanup did not end failed: \(run.model.cleanState)")
        }
        let stored = try await settled(run, keeping: ["screenSentence": sentence, "heldLock": lock.path])
        XCTAssertEqual(details(stored, at: "tama.violations.clean"), [canonical(sentence, at: "tama.violations.clean")])
        XCTAssertEqual(details(stored, at: "tama.violations.scan"), [])
    }

    /// A directory that is no repository fails the cleanup and its final
    /// rescan, each refused by the screen's own validation; each operation is
    /// stored once with its own cause, and the directory is left as it was.
    @MainActor
    func testCleanupAndFinalRescanFailuresAreEachStoredOnce() async throws {
        let run = try await intakeRun()
        let directory = run.root.appendingPathComponent("not-a-repository", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        run.model.select(repository: directory.resolvingSymlinksInPath().path)
        await run.model.clean()
        guard case .failed(let combined) = run.model.cleanState,
            case .failed(let rescan) = run.model.scanState
        else {
            return XCTFail("The cleanup and its rescan did not both fail: \(run.model.cleanState) \(run.model.scanState)")
        }
        let joint = " Final rescan failed: \(rescan)"
        guard combined.hasSuffix(joint) else {
            return XCTFail("The screen does not join the rescan cause to the cleanup's: \(combined)")
        }
        let cleanup = String(combined.dropLast(joint.count))
        let stored = try await settled(run, keeping: ["screenSentence": combined, "rescanSentence": rescan])
        XCTAssertEqual(details(stored, at: "tama.violations.clean"), [canonical(cleanup, at: "tama.violations.clean")])
        XCTAssertEqual(details(stored, at: "tama.violations.scan"), [canonical(rescan, at: "tama.violations.scan")])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    private struct IntakeRun {
        let root: URL
        let state: URL
        let journal: URL
        let intake: Process
        let model: ViolationsModel
    }

    @MainActor
    private func intakeRun() async throws -> IntakeRun {
        let (client, root, _) = try fixture()
        guard let base = client.command else {
            throw FailureIntakePrerequisite.observation("the fixture client carries no command")
        }
        let failures = root.appendingPathComponent("failures", isDirectory: true)
        let state = root.appendingPathComponent("clean-state", isDirectory: true)
        try FileManager.default.createDirectory(at: failures, withIntermediateDirectories: true)
        let intake = try await startIntake(root: root, failures: failures)
        addTeardownBlock {
            intake.process.terminate()
            intake.process.waitUntilExit()
        }
        try export("PROBIERZ_INTAKE_URL", intake.url)
        try export("PROBIERZ_INTAKE_TOKEN", intake.token)
        addTeardownBlock {
            unsetenv("PROBIERZ_INTAKE_URL")
            unsetenv("PROBIERZ_INTAKE_TOKEN")
        }
        var environment = base.environment
        environment["TAMA_CLEAN_STATE_DIR"] = state.path
        let identity = WisentIdentity(
            userID: "intake-journey", email: "intake-journey@example.invalid",
            organization: WisentOrganization(
                id: "intake-journey", slug: "intake-journey", name: "Intake journey", role: "member"),
            accessToken: "")
        guard let authorization = ControlAuthorization(identity: identity) else {
            throw FailureIntakePrerequisite.observation("a member identity was not authorized")
        }
        let model = ViolationsModel(
            authorization: authorization,
            command: TamaCommand(executable: base.executable, root: nil, environment: environment))
        // The round budget is the caller's to declare, as `--max-rounds` is.
        model.repairRounds = try declared("TAMA_TEST_CLEAN_MAX_ROUNDS")
        return IntakeRun(
            root: root, state: state, journal: failures.appendingPathComponent("tama.jsonl"),
            intake: intake.process, model: model)
    }

    /// Await every issued report, then keep and return the stored records;
    /// an intake that ended or a journal ending inside a record fails here.
    private func settled(_ run: IntakeRun, keeping screen: [String: String]) async throws -> [[String: Any]] {
        await TamaFailureReporting.settle()
        let stored = try records(in: run.journal)
        var observed: [String: Any] = screen
        observed["intakePID"] = Int(run.intake.processIdentifier)
        observed["intakeRunning"] = run.intake.isRunning
        observed["storedRecords"] = stored.records.map { [$0["failure_point"], $0["detail"]] }
        observed["incompleteTail"] = stored.tail
        try JSONSerialization.data(withJSONObject: observed, options: [.prettyPrinted, .sortedKeys])
            .write(to: run.root.appendingPathComponent("intake-cardinality.json"))
        if FileManager.default.fileExists(atPath: run.journal.path) {
            try FileManager.default.copyItem(at: run.journal, to: run.root.appendingPathComponent("intake-journal.jsonl"))
        }
        XCTAssertTrue(run.intake.isRunning, "The intake ended before the reports settled: \(observed)")
        XCTAssertTrue(stored.tail.isEmpty, "The journal ends inside a record: \(observed)")
        return stored.records
    }

    private func details(_ records: [[String: Any]], at point: String) -> [String?] {
        records.filter { $0["failure_point"] as? String == point }.map { $0["detail"] as? String }
    }

    /// The detail the pinned reporter builds from `sentence` at `point`.
    private func canonical(_ sentence: String, at point: String) -> String? {
        Failure.orFallback(failurePoint: point, code: .unknown, service: TamaFailureReporting.service)
            .detail(sentence).detail
    }

    private func declared(_ name: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
            throw FailureIntakePrerequisite.missingDeclaration(name)
        }
        return value
    }

    private func export(_ name: String, _ value: String) throws {
        guard putenv(strdup("\(name)=\(value)")) == .zero else {
            throw FailureIntakePrerequisite.observation("putenv \(name) failed: errno \(errno)")
        }
    }

    /// The lock directory the backend names for `repo`: the leading 64-bit
    /// word of the SHA-256 of the path it was sent, in lowercase hex.
    private func lockName(for repo: String) -> String {
        SHA256.hash(data: Data(repo.utf8)).prefix(MemoryLayout<UInt64>.size)
            .map { String(format: "%02x", $0) }.joined()
    }

    /// A repository of its own with one commit, so a cleanup that was not
    /// refused could not touch a checkout anyone works in.
    private func freshRepository(in root: URL) throws -> URL {
        let repository = root.appendingPathComponent("repository", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try Data("intake journey\n".utf8).write(to: repository.appendingPathComponent("README.md"))
        for arguments in [
            ["init", "--quiet"], ["add", "README.md"],
            ["-c", "user.name=Journey", "-c", "user.email=journey@example.invalid",
             "commit", "--quiet", "-m", "One file"],
        ] {
            let git = Process()
            git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            git.arguments = ["-C", repository.path] + arguments
            var environment = ProcessInfo.processInfo.environment
            environment.removeValue(forKey: "GIT_INDEX_FILE")
            git.environment = environment
            try git.run()
            git.waitUntilExit()
            guard git.terminationStatus == EXIT_SUCCESS else {
                throw FailureIntakePrerequisite.observation("git \(arguments) exited \(git.terminationStatus)")
            }
        }
        return repository.resolvingSymlinksInPath().standardizedFileURL
    }

    /// The installed intake on a port the system just handed out, its own
    /// home and token, ready once it says where it listens; an intake that
    /// ends first is refused with its exit status and everything it said.
    private func startIntake(root: URL, failures: URL) async throws
        -> (process: Process, url: String, token: String)
    {
        let executable = try declared("PROBIERZ_TEST_EXECUTABLE")
        let port = try await freePort()
        let home = root.appendingPathComponent("intake-home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let token = UUID().uuidString
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["intake", "serve", "--bind", "localhost:\(port)"]
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "XPC_SERVICE_NAME")
        environment["HOME"] = home.path
        environment["PROBIERZ_INTAKE_TOKEN"] = token
        environment["PROBIERZ_FAILURES_DIR"] = failures.path
        process.environment = environment
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        var said: [String] = []
        for try await line in errors.fileHandleForReading.bytes.lines {
            said.append(line)
            if line.contains("listening on") {
                return (process, "http://localhost:\(port)", token)
            }
        }
        process.waitUntilExit()
        throw FailureIntakePrerequisite.observation(
            "the intake exited \(process.terminationStatus) before listening: \(said)")
    }

    private func freePort() async throws -> UInt16 {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { $0.cancel() }
        defer { listener.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    guard let port = listener.port else {
                        return continuation.resume(throwing: FailureIntakePrerequisite.observation(
                            "the ready listener has no port"))
                    }
                    continuation.resume(returning: port.rawValue)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: DispatchQueue(label: "intake-journey.port"))
        }
    }

    /// The complete records the intake stored, each ended by its newline, and
    /// whatever follows the last newline; no journal means nothing was stored.
    private func records(in journal: URL) throws -> (records: [[String: Any]], tail: String) {
        guard FileManager.default.fileExists(atPath: journal.path) else { return ([], "") }
        var lines = String(decoding: try Data(contentsOf: journal), as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false)
        let tail = String(lines.removeLast())
        let records = try lines.map { line in
            guard let record = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            else {
                throw FailureIntakePrerequisite.observation("a stored line is no object: \(line)")
            }
            return record
        }
        return (records, tail)
    }
}
