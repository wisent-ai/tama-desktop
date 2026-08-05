import SwiftUI

struct TamaSetupView: View {
    @ObservedObject var model: AppModel
    let complete: () -> Void

    @State private var isConfirmingRuntimeInstall = false
    @State private var isConfirmingBackendRegistration = false
    @State private var isConfirmingGlobalEnable = false
    @State private var isConfirmingSessionEnable = false

    private var runtimeInstalled: Bool {
        model.installedHookReleaseID != nil
    }

    private var backendReady: Bool {
        model.systemPolicyServiceStatus == "Enabled"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CGFloat(Int("16")!)) {
                header
                runtimeStep
                backendStep
                sessionStep
                completion
            }
            .padding()
        }
        .navigationTitle("Set up Tama")
        .accessibilityIdentifier("tama.setup")
        .confirmationDialog(
            "Install the local Tama runtime?",
            isPresented: $isConfirmingRuntimeInstall,
            titleVisibility: .visible
        ) {
            Button("Install runtime") {
                model.installLocalRuntime()
            }
            .disabled(model.isPolicyMutationInProgress)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Tama will verify its bundled hook release, then update managed files "
                    + "under Application Support and the documented per-user agent paths. "
                    + "Existing unrelated settings are preserved."
            )
        }
        .confirmationDialog(
            "Register privileged macOS policy components?",
            isPresented: $isConfirmingBackendRegistration,
            titleVisibility: .visible
        ) {
            Button("Register backend") {
                Task { await model.installSystemPolicyService() }
            }
            .disabled(model.isPolicyMutationInProgress)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "macOS will request approval for Tama's daemon, System Extension, "
                    + "Network filter, and Full Disk Access where required."
            )
        }
        .confirmationDialog(
            "Re-enable every managed hook?",
            isPresented: $isConfirmingGlobalEnable,
            titleVisibility: .visible
        ) {
            Button("Install approved release and re-enable") {
                model.setHooksDisabled(false)
            }
            .disabled(model.isPolicyMutationInProgress)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Tama will integrity-check and install its bundled release, restore managed "
                    + "dispatchers, then resume supervised sessions."
            )
        }
        .confirmationDialog(
            "Enable all hooks in the selected session?",
            isPresented: $isConfirmingSessionEnable,
            titleVisibility: .visible
        ) {
            Button("Enable all hooks and reload") {
                model.enableAllHooksInSelectedSession()
            }
            .disabled(model.isPolicyMutationInProgress)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "The session override will enable every registered hook and request a runtime reload."
            )
        }
        .alert(
            "Tama couldn’t complete setup",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) {
                model.clearError()
            }
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }

    private var header: some View {
        VStack(alignment: .leading) {
            Label("Set up enforcement", systemImage: "checkmark.shield.fill")
                .font(.largeTitle.bold())
            Text("You are signed in. Tama will now guide each local change separately.")
                .font(.title3)
            Text(
                "Setup finishes only after the sealed runtime is installed, macOS reports "
                    + "the privileged backend as ready, and a live agent session proves that "
                    + "the same hook release is loaded under kernel-gated policy."
            )
            .foregroundStyle(.secondary)
        }
    }

    private var runtimeStep: some View {
        SetupStep(
            title: "Install the sealed runtime",
            explanation: "Verifies the bundled release before writing managed hook files.",
            symbol: "shippingbox.fill",
            status: runtimeInstalled ? "Installed" : "Required",
            isHealthy: runtimeInstalled
        ) {
            if model.isInstallingLocalRuntime {
                ProgressView("Installing integrity-checked runtime…")
            } else if let releaseID = model.installedHookReleaseID {
                LabeledContent("Installed release") {
                    Text(releaseID)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(Int("1")!)
                }
                if let nodeVersion = model.installedNodeVersion {
                    LabeledContent("Node", value: nodeVersion)
                }
            } else if let snapshot = model.snapshot {
                if snapshot.validation.ok {
                    Button("Install local runtime") {
                        isConfirmingRuntimeInstall = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isPolicyMutationInProgress)
                } else {
                    Label(
                        "The bundled policy failed integrity validation. Reinstall Tama before continuing.",
                        systemImage: "xmark.shield.fill"
                    )
                    .foregroundStyle(.red)
                }
            } else if model.isRefreshing {
                ProgressView("Validating the bundled policy…")
            }

            if runtimeInstalled, model.areHooksDisabled {
                Divider()
                Label("Managed hooks are globally disabled.", systemImage: "exclamationmark.octagon.fill")
                    .foregroundStyle(.red)
                Button("Re-enable managed hooks") {
                    isConfirmingGlobalEnable = true
                }
                .disabled(model.isPolicyMutationInProgress)
            }
        }
    }

    private var backendStep: some View {
        SetupStep(
            title: "Approve the privileged backend",
            explanation: "Registers the daemon, System Extension, network filter, and required macOS approvals.",
            symbol: "lock.shield.fill",
            status: model.systemPolicyServiceStatus,
            isHealthy: backendReady
        ) {
            if model.isRegisteringSystemPolicyService {
                ProgressView("Registering privileged backend…")
            } else if !backendReady {
                Button("Register privileged backend") {
                    isConfirmingBackendRegistration = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(!runtimeInstalled || model.isPolicyMutationInProgress)
                HStack {
                    Button("Open approval settings") {
                        model.openSystemPolicyApprovalSettings()
                    }
                    Button("Open Full Disk Access") {
                        model.openFullDiskAccessSettings()
                    }
                    Button("Refresh backend status") {
                        Task { await model.refreshSystemPolicyStatus() }
                    }
                }
            } else {
                Label("The local policy backend is enabled.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private var sessionStep: some View {
        SetupStep(
            title: "Verify one supervised session",
            explanation: "Start or resume an agent normally, then confirm its loaded release and kernel policy.",
            symbol: "terminal.fill",
            status: model.setupReadySession == nil ? "Waiting" : "Verified",
            isHealthy: model.setupReadySession != nil
        ) {
            if let sessionError = model.sessionErrorMessage {
                Label(sessionError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if model.agentSessions.isEmpty {
                Text(
                    "No live supervised session is reporting yet. Start or resume a supported "
                        + "coding-agent session after the runtime and backend are ready."
                )
                .foregroundStyle(.secondary)
            } else {
                Picker("Session", selection: $model.selectedAgentSessionID) {
                    ForEach(model.agentSessions) { session in
                        Text(session.displayName)
                            .tag(Optional(session.id))
                    }
                }
                if let session = model.selectedAgentSession {
                    SessionSetupStatus(
                        session: session,
                        installedReleaseID: model.installedHookReleaseID
                    )
                }
                if !model.areAllHooksEnabledInSelectedSession {
                    Button("Enable all hooks in selected session") {
                        isConfirmingSessionEnable = true
                    }
                    .disabled(model.isPolicyMutationInProgress || model.snapshot == nil)
                }
            }

            Button("Refresh sessions", systemImage: "arrow.clockwise") {
                Task { await model.refreshAgentSessions() }
            }
        }
    }

    private var completion: some View {
        GroupBox("Completion") {
            VStack(alignment: .leading) {
                SetupRequirement(
                    title: "Bundled policy is valid",
                    satisfied: model.snapshot?.validation.ok == true
                )
                SetupRequirement(
                    title: "Local runtime is installed and enabled",
                    satisfied: runtimeInstalled && !model.areHooksDisabled
                )
                SetupRequirement(
                    title: "Privileged backend is enabled",
                    satisfied: backendReady
                )
                SetupRequirement(
                    title: "A matching kernel-gated session is live",
                    satisfied: model.setupReadySession != nil
                )
                Divider()
                HStack {
                    Text(
                        model.isSetupComplete
                            ? "Setup evidence is complete."
                            : "Complete every requirement before entering policy controls."
                    )
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("Finish setup and open Tama") {
                        complete()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.isSetupComplete)
                    .accessibilityIdentifier("tama.setup.finish")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SetupStep<Content: View>: View {
    let title: String
    let explanation: String
    let symbol: String
    let status: String
    let isHealthy: Bool
    @ViewBuilder let content: Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading) {
                HStack {
                    Label(title, systemImage: symbol)
                        .font(.headline)
                    Spacer()
                    SetupStatusLabel(text: status, isHealthy: isHealthy)
                }
                Text(explanation)
                    .foregroundStyle(.secondary)
                Divider()
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SetupRequirement: View {
    let title: String
    let satisfied: Bool

    var body: some View {
        Label(
            title,
            systemImage: satisfied ? "checkmark.circle.fill" : "circle"
        )
        .foregroundStyle(satisfied ? .green : .secondary)
    }
}

private struct SessionSetupStatus: View {
    let session: AgentSessionRecord
    let installedReleaseID: String?

    private var runtimeMatches: Bool {
        guard let installedReleaseID, let runtime = session.runtime else { return false }
        return runtime.installedReleaseId == installedReleaseID
            && runtime.loadedReleaseId == installedReleaseID
            && runtime.registryLoadError == nil
            && !runtime.reloadRequired
            && runtime.reloadPending != true
    }

    private var hooksLoaded: Bool {
        guard let runtime = session.runtime else { return false }
        return runtime.registeredHookCount > Int("0")!
            && runtime.loadedHookCount == runtime.registeredHookCount
            && runtime.unknownHookIds.isEmpty
            && !session.globallyDisabled
            && session.disabledHookIds.isEmpty
    }

    private var kernelGated: Bool {
        guard let policy = session.systemPolicy else { return false }
        return policy.ready && policy.mode == "kernel-gated" && policy.error == nil
    }

    var body: some View {
        VStack(alignment: .leading) {
            SetupRequirement(title: "Installed and loaded release identities match", satisfied: runtimeMatches)
            SetupRequirement(title: "Every registered hook is loaded and enabled", satisfied: hooksLoaded)
            SetupRequirement(title: "System policy is kernel-gated", satisfied: kernelGated)
        }
    }
}

private struct SetupStatusLabel: View {
    let text: String
    let isHealthy: Bool

    var body: some View {
        Label(
            text,
            systemImage: isHealthy ? "checkmark.circle.fill" : "circle.dashed"
        )
        .font(.caption)
        .foregroundStyle(isHealthy ? .green : .secondary)
    }
}
