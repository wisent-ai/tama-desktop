import AppKit
import Combine
import Foundation
import WisentAuth
import WisentDesignSystem

@MainActor
final class AppModel: ObservableObject {
    @Published var snapshot: CatalogSnapshot?
    @Published var isRefreshing = false
    @Published var refreshedAt: Date?

    /// Two failures, never merged into one field again.
    ///
    /// The baseline used a single `errorMessage` for the catalog read and for
    /// every mutation, so a failed write erased a failed read and both arrived
    /// as the same modal alert. A catalog that will not load is the screen's
    /// subject; a write that was refused is an outcome of something the
    /// operator just did.
    @Published var catalogError: String?
    @Published var mutation: WisentMutationOutcome = .idle
    @Published var sessionError: String?
    @Published var policyBundleMutation: WisentMutationOutcome = .idle
    @Published var policyBundleImport: PolicyBundleImportResult?
    @Published var policyBundles: PolicyBundleList?
    @Published var isImportingPolicyBundle = false

    @Published var areHooksDisabled = false
    @Published var installedHookReleaseID: String?
    @Published var installedNodeExecutable: String?
    @Published var installedNodeVersion: String?
    @Published var agentSessions: [AgentSessionRecord] = []
    @Published var selectedAgentSessionID: AgentSessionRecord.ID?
    @Published var systemPolicyServiceStatus = "Not registered"

    let client = HookCatalogClient()
    let emergencySwitch = HookEmergencySwitch()
    let loadsLocalJustifications: Bool
    let allowsControlAccess: Bool
    var isControlMonitoring = false
    var sessionPollingTask: Task<Void, Never>?

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

    // MARK: - Existing policy bundles

    @discardableResult
    func importPolicyBundle(from source: URL, replace: Bool = false) async -> Bool {
        guard allowsControlAccess, !isImportingPolicyBundle else { return false }
        isImportingPolicyBundle = true
        policyBundleImport = nil
        policyBundleMutation = .working("Validating the complete policy bundle before writing…")
        defer { isImportingPolicyBundle = false }
        do {
            let result = try await TamaClient().request(
                "policy-bundles/import",
                body: [
                    "sourcePath": source.standardizedFileURL.path,
                    "replace": replace,
                ],
                as: PolicyBundleImportResult.self,
                describing: "import policy bundle"
            )
            policyBundleImport = result
            if result.accepted {
                policyBundleMutation = .succeeded(result.summary)
                await refreshPolicyBundles()
                return true
            }
            policyBundleMutation = .failed(result.summary)
            return false
        } catch {
            policyBundleMutation = .failed(Self.sentence(error))
            return false
        }
    }

    func refreshPolicyBundles() async {
        do {
            policyBundles = try await TamaClient().request(
                "policy-bundles",
                as: PolicyBundleList.self,
                describing: "list policy bundles"
            )
        } catch {
            policyBundles = nil
        }
    }

    func clearPolicyBundleMutation() {
        policyBundleMutation = .idle
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






    // MARK: - Session control






    // MARK: - Revealing



    // MARK: - Plumbing




}
