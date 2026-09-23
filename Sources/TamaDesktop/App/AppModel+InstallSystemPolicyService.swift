import AppKit
import Combine
import Foundation
import WisentAuth
import WisentDesignSystem

extension AppModel {
    func installSystemPolicyService() {
        mutate("Registering the privileged macOS policy backend…") {
            let status = try await SystemPolicyServiceManager().register()
            self.systemPolicyServiceStatus = status
            return status
        } recover: {
            self.systemPolicyServiceStatus = await SystemPolicyServiceManager().status()
        }
    }
    func deactivateLocalSetup() {
        mutate("Deactivating the local policy setup…") {
            try await Task.detached(priority: .userInitiated) {
                try HookEmergencySwitch().setDisabled(true)
            }.value
            self.refreshLocalPolicyState()
            let status = try await SystemPolicyServiceManager().unregister()
            self.systemPolicyServiceStatus = status
            return "Managed dispatchers disabled. Privileged backend: \(status)."
        } recover: {
            self.refreshLocalPolicyState()
            self.systemPolicyServiceStatus = await SystemPolicyServiceManager().status()
        }
    }
    func setHooksDisabled(_ disabled: Bool) {
        let verb = disabled
            ? "Disabling every managed hook dispatcher…"
            : "Verifying the bundled release and restoring every managed dispatcher…"
        mutate(verb) {
            try await Task.detached(priority: .userInitiated) {
                try HookEmergencySwitch().setDisabled(disabled)
            }.value
            self.refreshLocalPolicyState()
            guard self.areHooksDisabled == disabled else {
                throw HookEmergencyError.stateDidNotPersist
            }
            return disabled
                ? "All Tama-managed hooks are bypassed on this machine."
                : "Every managed hook dispatcher is active again."
        } recover: {
            self.refreshLocalPolicyState()
        }
    }
    func openSystemPolicyApprovalSettings() {
        SystemPolicyServiceManager().openApprovalSettings()
    }
    func openFullDiskAccessSettings() {
        SystemPolicyServiceManager().openFullDiskAccessSettings()
    }
    var selectedAgentSession: AgentSessionRecord? {
        guard let selectedAgentSessionID else { return agentSessions.first }
        return agentSessions.first(where: { $0.id == selectedAgentSessionID })
    }
    func areAllHooksEnabled(in session: AgentSessionRecord?) -> Bool {
        guard let session, !hooks.isEmpty else { return false }
        return hooks.allSatisfy { session.isHookEnabled($0.id) }
    }
    func enableHook(_ hookId: String, in session: AgentSessionRecord) {
        mutate("Enabling \(hookId) in session \(session.sessionId)…") {
            let updated = try await Task.detached(priority: .userInitiated) {
                try SessionControlClient().enableHook(hookId, session: session)
            }.value
            self.merge(updated)
            return "\(hookId) is enabled in \(session.agentDisplayName) session \(session.sessionId)."
        } recover: {
            await self.refreshAgentSessions()
        }
    }
    func enableAllHooks(in session: AgentSessionRecord) {
        guard !hooks.isEmpty else { return }
        mutate("Enabling every registered hook in session \(session.sessionId)…") {
            let updated = try await Task.detached(priority: .userInitiated) {
                try SessionControlClient().setAllHooksEnabled(session: session)
            }.value
            self.merge(updated)
            let loaded = updated.runtime?.loadedHookCount ?? self.hooks.count
            return "\(counted(loaded, "hook")) enabled in \(session.agentDisplayName) session \(session.sessionId)."
        } recover: {
            await self.refreshAgentSessions()
        }
    }
    func clearMutation() {
        mutation = .idle
    }
    func revealSource(for hook: HookRecord) {
        guard let sourcePath = hook.sourcePath else { return }
        do {
            let root = try client.hookReleaseRoot()
            NSWorkspace.shared.activateFileViewerSelecting([
                root.appendingPathComponent(sourcePath)
            ])
        } catch {
            mutation = .failed(Self.sentence(error))
        }
    }
    func revealHookRelease() {
        do {
            NSWorkspace.shared.activateFileViewerSelecting([try client.hookReleaseRoot()])
        } catch {
            mutation = .failed(Self.sentence(error))
        }
    }
    /// One write path, so every mutation reports the backend's own sentence.
    func mutate(
        _ working: String,
        _ perform: @escaping () async throws -> String,
        recover: @escaping () async -> Void = {}
    ) {
        guard allowsControlAccess, !mutation.isWorking else { return }
        mutation = .working(working)
        Task {
            do {
                mutation = .succeeded(try await perform())
            } catch {
                await recover()
                mutation = .failed(Self.sentence(error))
            }
        }
    }
    func merge(_ session: AgentSessionRecord) {
        if let index = agentSessions.firstIndex(where: { $0.id == session.id }) {
            agentSessions[index] = session
        } else {
            agentSessions.append(session)
        }
    }
    func refreshLocalPolicyState() {
        let installedRuntime = emergencySwitch.installedRuntime
        areHooksDisabled = emergencySwitch.isDisabled
        installedHookReleaseID = installedRuntime?.releaseID
        installedNodeExecutable = installedRuntime?.nodeExecutable
        installedNodeVersion = installedRuntime?.nodeVersion
    }
    static func sentence(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
