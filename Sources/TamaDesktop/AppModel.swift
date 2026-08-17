import AppKit
import Combine
import Foundation
import WisentAuth
import WisentDesignSystem

struct ControlAuthorization: Sendable {
    private static let acceptedRoles: Set<String> = [
        "owner",
        "admin",
        "member",
    ]

    init?(identity: WisentIdentity) {
        guard Self.acceptedRoles.contains(identity.organization.role) else {
            return nil
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: CatalogSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshedAt: Date?

    /// Two failures, never merged into one field again.
    ///
    /// The baseline used a single `errorMessage` for the catalog read and for
    /// every mutation, so a failed write erased a failed read and both arrived
    /// as the same modal alert. A catalog that will not load is the screen's
    /// subject; a write that was refused is an outcome of something the
    /// operator just did.
    @Published private(set) var catalogError: String?
    @Published private(set) var mutation: WisentMutationOutcome = .idle
    @Published private(set) var sessionError: String?

    @Published private(set) var areHooksDisabled = false
    @Published private(set) var installedHookReleaseID: String?
    @Published private(set) var installedNodeExecutable: String?
    @Published private(set) var installedNodeVersion: String?
    @Published private(set) var agentSessions: [AgentSessionRecord] = []
    @Published var selectedAgentSessionID: AgentSessionRecord.ID?
    @Published private(set) var systemPolicyServiceStatus = "Not registered"

    private let client = HookCatalogClient()
    private let emergencySwitch = HookEmergencySwitch()
    private let loadsLocalJustifications: Bool
    private let allowsControlAccess: Bool
    private var isControlMonitoring = false
    private var sessionPollingTask: Task<Void, Never>?

    var hooks: [HookRecord] { snapshot?.catalog.hooks ?? [] }

    var isPolicyMutationInProgress: Bool { mutation.isWorking }

    var setupReadySession: AgentSessionRecord? {
        guard let installedHookReleaseID else { return nil }
        return agentSessions.first { session in
            guard let runtime = session.runtime, let policy = session.systemPolicy else {
                return false
            }
            return runtime.installedReleaseId == installedHookReleaseID
                && runtime.loadedReleaseId == installedHookReleaseID
                && runtime.registryLoadError == nil
                && !runtime.reloadRequired
                && runtime.reloadPending != true
                && runtime.registeredHookCount > 0
                && runtime.loadedHookCount == runtime.registeredHookCount
                && runtime.unknownHookIds.isEmpty
                && !session.globallyDisabled
                && session.disabledHookIds.isEmpty
                && policy.ready
                && policy.mode == "kernel-gated"
                && policy.error == nil
        }
    }

    var isSetupComplete: Bool {
        snapshot?.validation.ok == true
            && installedHookReleaseID != nil
            && !areHooksDisabled
            && systemPolicyServiceStatus == "Enabled"
            && setupReadySession != nil
    }

    /// The question the baseline could not answer: why did my agent stop.
    ///
    /// `semanticRuntime.recentEvents` carries the decision, the hook that made
    /// it and the reason string, and the whole list was being reduced to one
    /// "Last event" label. The most recent blocking decision across live
    /// sessions is the headline of Posture.
    var lastBlockingDecision: (session: AgentSessionRecord, event: SemanticEventSummary)? {
        agentSessions
            .compactMap { session -> (AgentSessionRecord, SemanticEventSummary)? in
                guard
                    let blocked = session.semanticRuntime?.recentEvents
                        .last(where: { $0.decision != "allow" })
                else {
                    return nil
                }
                return (session, blocked)
            }
            .max { left, right in left.1.timestamp < right.1.timestamp }
            .map { (session: $0.0, event: $0.1) }
    }

    init(
        inspectionOnly: Bool = false,
        authorization: ControlAuthorization? = nil
    ) {
        loadsLocalJustifications = !inspectionOnly
        allowsControlAccess = authorization != nil
        Task { await refresh() }
    }

    deinit {
        sessionPollingTask?.cancel()
    }

    var allowsControl: Bool { allowsControlAccess }

    func startControlMonitoring() {
        guard allowsControlAccess, sessionPollingTask == nil else { return }
        isControlMonitoring = true
        refreshLocalPolicyState()
        Task { await refreshSystemPolicyStatus() }
        sessionPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAgentSessions()
                try? await Task.sleep(for: .seconds(Int("1")!))
            }
        }
    }

    func stopControlMonitoring() {
        isControlMonitoring = false
        sessionPollingTask?.cancel()
        sessionPollingTask = nil
        agentSessions = []
        selectedAgentSessionID = nil
        sessionError = nil
        systemPolicyServiceStatus = "Not registered"
        areHooksDisabled = false
        installedHookReleaseID = nil
        installedNodeExecutable = nil
        installedNodeVersion = nil
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        do {
            let loadsLocalJustifications = loadsLocalJustifications
            snapshot = try await Task.detached(priority: .userInitiated) {
                try HookCatalogClient().load(
                    includeLocalJustifications: loadsLocalJustifications
                )
            }.value
            catalogError = nil
            refreshedAt = Date()
        } catch {
            // The previous snapshot is deliberately kept: a failed re-read
            // banners itself above the catalog the operator was reading.
            catalogError = Self.sentence(error)
        }
        isRefreshing = false
    }

    func refreshSystemPolicyStatus() async {
        let status = await SystemPolicyServiceManager().status()
        guard isControlMonitoring else { return }
        systemPolicyServiceStatus = status
    }

    func refreshAgentSessions() async {
        guard isControlMonitoring else { return }
        do {
            let loaded = try await Task.detached(priority: .utility) {
                try SessionControlClient().liveSessions()
            }.value
            guard isControlMonitoring else { return }
            agentSessions = loaded
            sessionError = nil
            if !loaded.contains(where: { $0.id == selectedAgentSessionID }) {
                selectedAgentSessionID = loaded.first?.id
            }
        } catch {
            guard isControlMonitoring else { return }
            agentSessions = []
            selectedAgentSessionID = nil
            sessionError = Self.sentence(error)
        }
    }

    // MARK: - Local setup

    func installLocalRuntime() {
        mutate("Installing the integrity-checked hook runtime…") {
            try await Task.detached(priority: .userInitiated) {
                try HookEmergencySwitch().installSessionController()
            }.value
            self.refreshLocalPolicyState()
            await self.refreshAgentSessions()
            return "Installed hook release \(self.installedHookReleaseID ?? "unknown")."
        } recover: {
            self.refreshLocalPolicyState()
        }
    }

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

    // MARK: - Session control

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

    // MARK: - Revealing

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

    // MARK: - Plumbing

    /// One write path, so every mutation reports the backend's own sentence.
    private func mutate(
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

    private func merge(_ session: AgentSessionRecord) {
        if let index = agentSessions.firstIndex(where: { $0.id == session.id }) {
            agentSessions[index] = session
        } else {
            agentSessions.append(session)
        }
    }

    private func refreshLocalPolicyState() {
        let installedRuntime = emergencySwitch.installedRuntime
        areHooksDisabled = emergencySwitch.isDisabled
        installedHookReleaseID = installedRuntime?.releaseID
        installedNodeExecutable = installedRuntime?.nodeExecutable
        installedNodeVersion = installedRuntime?.nodeVersion
    }

    private static func sentence(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
