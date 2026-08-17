import Darwin
import Foundation

struct HookEmergencySwitch: @unchecked Sendable {
    private static let schema = "ai.wisent.tama.hook-emergency-state.v1"
    private let manager = FileManager.default

    var isDisabled: Bool {
        guard
            manager.fileExists(atPath: manifestURL.path),
            let data = try? Data(contentsOf: stateURL),
            let state = try? JSONDecoder().decode(State.self, from: data)
        else {
            return false
        }
        return state.schema == Self.schema && state.disabled
    }

    var installedRuntime: (
        releaseID: String,
        nodeExecutable: String?,
        nodeVersion: String?
    )? {
        guard
            let data = try? Data(contentsOf: installedReleaseURL),
            let release = try? JSONDecoder().decode(InstalledRelease.self, from: data)
        else {
            return nil
        }
        return (release.releaseId, release.nodeExecutable, release.nodeVersion)
    }

    func setDisabled(_ disabled: Bool) throws {
        guard let scriptURL = Bundle.main.url(
            forResource: "emergency_disable_hooks",
            withExtension: nil
        ) else {
            throw HookEmergencyError.scriptMissing
        }

        var environment = ProcessInfo.processInfo.environment
        environment["TAMA_EMERGENCY_ACTION"] = disabled ? "disable" : "enable"
        try runCommand(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [scriptURL.path],
            environment: environment
        )
    }
    func installSessionController() throws {
        guard
            let installerURL = Bundle.main.url(
                forResource: "install_hook_release",
                withExtension: "py"
            ),
            let resourcesURL = Bundle.main.resourceURL
        else {
            throw HookEmergencyError.controllerInstallerMissing
        }
        let releaseURL = resourcesURL.appendingPathComponent(
            "hooks-release",
            isDirectory: true
        )
        guard manager.fileExists(atPath: releaseURL.appendingPathComponent("release.json").path) else {
            throw HookEmergencyError.controllerReleaseMissing
        }

        try runCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: [
                installerURL.path,
                "--release", releaseURL.path,
                "--home", NSHomeDirectory(),
                "--session-control-only",
            ],
            environment: ProcessInfo.processInfo.environment
        )
    }

    private func runCommand(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]
    ) throws {
        let process = Process()
        let output = Pipe()
        let outputBox = DataBox()
        let drainGroup = DispatchGroup()
        let completed = DispatchSemaphore(value: .zero)
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = output
        process.standardError = output
        process.terminationHandler = { _ in completed.signal() }
        try process.run()

        drainGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outputBox.drain(
                output.fileHandleForReading,
                retaining: Int("65536")!
            )
            drainGroup.leave()
        }

        let deadline = DispatchTime.now() + .seconds(Int("300")!)
        let pollInterval = DispatchTimeInterval.milliseconds(Int("100")!)
        while completed.wait(timeout: .now() + pollInterval) == .timedOut {
            guard DispatchTime.now() < deadline else {
                signalProcessTree(
                    rootPID: process.processIdentifier,
                    signal: SIGTERM
                )
                if completed.wait(
                    timeout: .now() + .seconds(Int("5")!)
                ) == .timedOut {
                    signalProcessTree(
                        rootPID: process.processIdentifier,
                        signal: SIGKILL
                    )
                    completed.wait()
                }
                if drainGroup.wait(
                    timeout: .now() + .seconds(Int("5")!)
                ) == .timedOut {
                    try? output.fileHandleForReading.close()
                }
                throw HookEmergencyError.commandTimedOut
            }
        }
        if drainGroup.wait(
            timeout: .now() + .seconds(Int("5")!)
        ) == .timedOut {
            try? output.fileHandleForReading.close()
            throw HookEmergencyError.commandOutputReadFailed(
                "output pipe did not close after the command exited"
            )
        }
        if let readError = outputBox.readError {
            throw HookEmergencyError.commandOutputReadFailed(readError)
        }
        guard !outputBox.wasTruncated else {
            throw HookEmergencyError.commandOutputExceeded
        }
        let message = String(
            data: outputBox.data,
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == .zero else {
            throw HookEmergencyError.commandFailed(message)
        }
    }

    private var supportURL: URL {
        manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tama", isDirectory: true)
    }

    private var stateURL: URL {
        supportURL.appendingPathComponent("hook-emergency-state.json")
    }

    private var manifestURL: URL {
        supportURL
            .appendingPathComponent("emergency-backup", isDirectory: true)
            .appendingPathComponent("manifest.json")
    }

    private var installedReleaseURL: URL {
        supportURL
            .appendingPathComponent("hooks-runtime", isDirectory: true)
            .appendingPathComponent("installed.json")
    }

    private struct State: Codable {
        let schema: String
        let disabled: Bool
        let changedAt: String
    }

    private struct InstalledRelease: Decodable {
        let releaseId: String
        let nodeExecutable: String?
        let nodeVersion: String?
    }
}

enum HookEmergencyError: LocalizedError {
    case stateDidNotPersist
    case scriptMissing
    case controllerInstallerMissing
    case controllerReleaseMissing
    case commandFailed(String)
    case commandTimedOut
    case commandOutputExceeded
    case commandOutputReadFailed(String)

    var errorDescription: String? {
        switch self {
        case .stateDidNotPersist:
            "Tama could not persist the emergency hook state."
        case .scriptMissing:
            "The Tama bundle does not contain the emergency hook controller."
        case .controllerInstallerMissing:
            "The Tama bundle does not contain the agent session-controller installer."
        case .controllerReleaseMissing:
            "The Tama bundle does not contain an approved hook release for agent session control."
        case let .commandFailed(message):
            message.isEmpty
                ? "Tama could not update the installed hook configuration."
                : message
        case .commandTimedOut:
            "The local policy command exceeded its bounded runtime and was terminated. Inspect local policy state before retrying."
        case .commandOutputExceeded:
            "The local policy command exceeded Tama's bounded output limit. Inspect local policy state before retrying."
        case let .commandOutputReadFailed(message):
            "Tama could not read bounded local policy output: \(message)"
        }
    }
}
