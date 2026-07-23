import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: CatalogSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published var selection: SidebarSelection? = .overview
    @Published var selectedHookID: HookRecord.ID?
    @Published var searchText = ""
    @Published var hookFilter: HookFilter = .all
    @Published private(set) var areHooksDisabled = false
    @Published private(set) var isChangingHookState = false
    @Published private(set) var installedHookReleaseID: String?
    @Published private(set) var agentSessions: [AgentSessionRecord] = []
    @Published var selectedAgentSessionID: AgentSessionRecord.ID?
    @Published private(set) var isChangingSessionHook = false
    @Published private(set) var systemPolicyServiceStatus = "Checking"

    private let client = HookCatalogClient()
    private let emergencySwitch = HookEmergencySwitch()
    private var sessionPollingTask: Task<Void, Never>?

    var filteredHooks: [HookRecord] {
        guard let hooks = snapshot?.catalog.hooks else { return [] }
        return hooks.filter { hook in
            let matchesFilter = switch hookFilter {
            case .all: true
            case .blocking: hook.isBlocking
            case .nonblocking: !hook.isBlocking
            }
            guard matchesFilter else { return false }
            guard !searchText.isEmpty else { return true }
            return hook.id.localizedStandardContains(searchText)
                || hook.category.localizedStandardContains(searchText)
                || hook.eventNames.localizedStandardContains(searchText)
                || (hook.description?.localizedStandardContains(searchText) ?? false)
        }
    }

    var selectedHook: HookRecord? {
        guard let selectedHookID else { return filteredHooks.first }
        return snapshot?.catalog.hooks.first(where: { $0.id == selectedHookID })
    }

    init() {
        areHooksDisabled = emergencySwitch.isDisabled
        installedHookReleaseID = emergencySwitch.installedReleaseID
        Task {
            await installSystemPolicyService()
            await refresh()
            do {
                try await Task.detached(priority: .utility) {
                    try HookEmergencySwitch().installSessionController()
                }.value
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
        sessionPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAgentSessions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    deinit {
        sessionPollingTask?.cancel()
    }

    func installSystemPolicyService() async {
        do {
            systemPolicyServiceStatus = try await SystemPolicyServiceManager().register()
        } catch {
            systemPolicyServiceStatus = "Registration failed: \(error.localizedDescription)"
        }
    }

    func openSystemPolicyApprovalSettings() {
        SystemPolicyServiceManager().openApprovalSettings()
    }

    func openFullDiskAccessSettings() {
        SystemPolicyServiceManager().openFullDiskAccessSettings()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        areHooksDisabled = emergencySwitch.isDisabled
        installedHookReleaseID = emergencySwitch.installedReleaseID
        isRefreshing = true
        errorMessage = nil
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try HookCatalogClient().load()
            }.value
            snapshot = loaded
            if selectedHookID == nil {
                selectedHookID = loaded.catalog.hooks.first?.id
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isRefreshing = false
    }
    func setHooksDisabled(_ disabled: Bool) {
        guard !isChangingHookState else { return }
        isChangingHookState = true
        let emergencySwitch = emergencySwitch
        Task {
            defer { isChangingHookState = false }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try emergencySwitch.setDisabled(disabled)
                }.value
                areHooksDisabled = emergencySwitch.isDisabled
                installedHookReleaseID = emergencySwitch.installedReleaseID
                guard areHooksDisabled == disabled else {
                    throw HookEmergencyError.stateDidNotPersist
                }
                errorMessage = nil
            } catch {
                areHooksDisabled = emergencySwitch.isDisabled
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }

    var selectedAgentSession: AgentSessionRecord? {
        guard let selectedAgentSessionID else { return agentSessions.first }
        return agentSessions.first(where: { $0.id == selectedAgentSessionID })
    }

    func isHookEnabledInSelectedSession(_ hookId: String) -> Bool? {
        selectedAgentSession?.isHookEnabled(hookId, globallyDisabled: areHooksDisabled)
    }

    var areAllHooksEnabledInSelectedSession: Bool {
        guard
            let session = selectedAgentSession,
            let hooks = snapshot?.catalog.hooks,
            !hooks.isEmpty
        else {
            return false
        }
        return hooks.allSatisfy {
            session.isHookEnabled($0.id, globallyDisabled: areHooksDisabled)
        }
    }

    func refreshAgentSessions() async {
        do {
            let loaded = try await Task.detached(priority: .utility) {
                try SessionControlClient().liveSessions()
            }.value
            agentSessions = loaded
            if !loaded.contains(where: { $0.id == selectedAgentSessionID }) {
                selectedAgentSessionID = loaded.first?.id
            }
        } catch {
            agentSessions = []
            selectedAgentSessionID = nil
        }
    }

    func setSelectedSessionHook(_ hookId: String, enabled: Bool) {
        guard !isChangingSessionHook, let session = selectedAgentSession else { return }
        isChangingSessionHook = true
        Task {
            defer { isChangingSessionHook = false }
            do {
                let globallyDisabled = areHooksDisabled
                let updated = try await Task.detached(priority: .userInitiated) {
                    try SessionControlClient().setHookEnabled(
                        enabled,
                        hookId: hookId,
                        session: session,
                        globallyDisabled: globallyDisabled
                    )
                }.value
                if let index = agentSessions.firstIndex(where: { $0.id == updated.id }) {
                    agentSessions[index] = updated
                } else {
                    agentSessions.append(updated)
                }
                errorMessage = nil
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                await refreshAgentSessions()
            }
        }
    }

    func enableAllHooksInSelectedSession() {
        guard
            !isChangingSessionHook,
            let session = selectedAgentSession,
            let hookIds = snapshot?.catalog.hooks.map(\.id),
            !hookIds.isEmpty
        else {
            return
        }
        isChangingSessionHook = true
        Task {
            defer { isChangingSessionHook = false }
            do {
                let globallyDisabled = areHooksDisabled
                let updated = try await Task.detached(priority: .userInitiated) {
                    try SessionControlClient().setAllHooksEnabled(
                        hookIds,
                        session: session,
                        globallyDisabled: globallyDisabled
                    )
                }.value
                if let index = agentSessions.firstIndex(where: { $0.id == updated.id }) {
                    agentSessions[index] = updated
                } else {
                    agentSessions.append(updated)
                }
                errorMessage = nil
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                await refreshAgentSessions()
            }
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func revealSelectedSource() {
        guard let sourcePath = selectedHook?.sourcePath else { return }
        do {
            let root = try client.repositoryRoot()
            let source = root.appendingPathComponent(sourcePath)
            NSWorkspace.shared.activateFileViewerSelecting([source])
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func revealRepository() {
        do {
            NSWorkspace.shared.activateFileViewerSelecting([try client.repositoryRoot()])
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct HookEmergencySwitch: @unchecked Sendable {
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

    var installedReleaseID: String? {
        guard
            let data = try? Data(contentsOf: installedReleaseURL),
            let release = try? JSONDecoder().decode(InstalledRelease.self, from: data)
        else {
            return nil
        }
        return release.releaseId
    }

    func setDisabled(_ disabled: Bool) throws {
        guard let scriptURL = Bundle.main.url(
            forResource: "emergency_disable_hooks",
            withExtension: nil
        ) else {
            throw HookEmergencyError.scriptMissing
        }

        let process = Process()
        let output = Pipe()
        var environment = ProcessInfo.processInfo.environment
        environment["TAMA_EMERGENCY_ACTION"] = disabled ? "disable" : "enable"
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path]
        process.environment = environment
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        let message = String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            throw HookEmergencyError.commandFailed(message)
        }
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

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            installerURL.path,
            "--release", releaseURL.path,
            "--home", NSHomeDirectory(),
            "--session-control-only",
        ]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        let message = String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
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
    }
}

private enum HookEmergencyError: LocalizedError {
    case stateDidNotPersist
    case scriptMissing
    case controllerInstallerMissing
    case controllerReleaseMissing
    case commandFailed(String)

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
        }
    }
}
