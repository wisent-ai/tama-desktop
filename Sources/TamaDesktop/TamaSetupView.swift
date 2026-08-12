import SwiftUI

struct TamaSetupView: View {
    @ObservedObject var model: AppModel
    let complete: () -> Void

    @State private var isShowingAdvancedSetup = false
    @State private var isConfirmingRuntimeInstall = false
    @State private var isConfirmingBackendRegistration = false
    @State private var isConfirmingGlobalEnable = false
    @State private var isConfirmingSessionEnable = false

    private var runtimeInstalled: Bool {
        model.installedHookReleaseID != nil
    }

    private var hooksEnabled: Bool {
        runtimeInstalled && !model.areHooksDisabled
    }

    private var backendReady: Bool {
        model.systemPolicyServiceStatus == "Enabled"
    }

    private var bundledPolicyIsValid: Bool {
        model.snapshot?.validation.ok == true
    }

    private var statusTitle: String {
        if model.snapshot?.validation.ok == false {
            return "Hooks are unavailable"
        }
        if model.isSetupComplete {
            return "Hooks are on"
        }
        if hooksEnabled {
            return "Hooks need attention"
        }
        return "Hooks are off"
    }

    private var statusMessage: String {
        if model.snapshot?.validation.ok == false {
            return "This copy of Tama cannot verify its policy. Install a current build."
        }
        if model.isSetupComplete {
            return "Tama is protecting this Mac and the active coding-agent session."
        }
        if !runtimeInstalled {
            return "Turn hooks on to install Tama protection."
        }
        if model.areHooksDisabled {
            return "Protection is paused. Turn hooks on to restore it."
        }
        if !backendReady {
            return "Local hooks are running. Continue setup to allow system protection."
        }
        if model.agentSessions.isEmpty {
            return "System protection is ready. Open or resume a coding-agent session."
        }
        if !model.areAllHooksEnabledInSelectedSession {
            return "Select an active session and enable its protection."
        }
        return "Waiting for the selected session to report protected status."
    }

    private var statusSymbol: String {
        if model.snapshot?.validation.ok == false {
            return "xmark.shield.fill"
        }
        if model.isSetupComplete {
            return "checkmark.shield.fill"
        }
        if hooksEnabled {
            return "exclamationmark.shield.fill"
        }
        return "shield.slash.fill"
    }

    private var statusColor: Color {
        if model.snapshot?.validation.ok == false {
            return .red
        }
        if model.isSetupComplete {
            return .green
        }
        if hooksEnabled {
            return .orange
        }
        return .secondary
    }

    private var primaryActionTitle: String {
        if !runtimeInstalled || model.areHooksDisabled {
            return "Turn hooks on"
        }
        if !backendReady {
            return "Continue setup"
        }
        if model.agentSessions.isEmpty {
            return "Check for an active session"
        }
        if !model.areAllHooksEnabledInSelectedSession {
            return "Protect selected session"
        }
        return "Check again"
    }


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                masterControl


                DisclosureGroup(isExpanded: $isShowingAdvancedSetup) {
                    advancedSetup
                        .padding(.top, 12)
                } label: {
                    Label("Advanced setup and diagnostics", systemImage: "wrench.and.screwdriver")
                        .font(.headline)
                }
                .padding(16)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(32)
        }
        .navigationTitle("Hooks")
        .accessibilityIdentifier("tama.setup")
        .confirmationDialog(
            "Turn hooks on?",
            isPresented: $isConfirmingRuntimeInstall,
            titleVisibility: .visible
        ) {
            Button("Install and continue") {
                model.installLocalRuntime()
            }
            .disabled(model.isPolicyMutationInProgress)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Tama will install its verified local protection files while preserving unrelated settings."
            )
        }
        .confirmationDialog(
            "Allow system protection?",
            isPresented: $isConfirmingBackendRegistration,
            titleVisibility: .visible
        ) {
            Button("Continue") {
                Task { await model.installSystemPolicyService() }
            }
            .disabled(model.isPolicyMutationInProgress)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "macOS may ask you to approve Tama and Full Disk Access. Tama uses these permissions to enforce process and network policy."
            )
        }
        .confirmationDialog(
            "Resume Tama protection?",
            isPresented: $isConfirmingGlobalEnable,
            titleVisibility: .visible
        ) {
            Button("Turn hooks on") {
                model.setHooksDisabled(false)
            }
            .disabled(model.isPolicyMutationInProgress)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Tama will restore every managed hook dispatcher on this Mac.")
        }
        .confirmationDialog(
            "Protect the selected session?",
            isPresented: $isConfirmingSessionEnable,
            titleVisibility: .visible
        ) {
            Button("Enable protection") {
                model.enableAllHooksInSelectedSession()
            }
            .disabled(model.isPolicyMutationInProgress)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every registered Tama policy will be enabled for the selected session.")
        }
        .alert(
            "Tama couldn’t update protection",
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
        VStack(alignment: .leading, spacing: 6) {
            Label("Tama", systemImage: "shield.lefthalf.filled")
                .font(.title.bold())
            Text("Control how coding agents behave on this Mac.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var masterControl: some View {
        GroupBox {
            HStack(spacing: 20) {
                Image(systemName: statusSymbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 68, height: 68)
                    .background(statusColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(statusTitle)
                        .font(.title2.bold())
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)
                primaryControl
            }
            .padding(10)
        }
    }

    @ViewBuilder
    private var primaryControl: some View {
        if model.isPolicyMutationInProgress {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Updating Tama protection")
        } else if model.isSetupComplete {
            Button("Open Tama") {
                complete()
            }
            .buttonStyle(TamaPrimaryButtonStyle())
            .accessibilityIdentifier("tama.setup.finish")
        } else if model.snapshot?.validation.ok == false {
            Button("Check again") {
                Task { await model.refresh() }
            }
            .controlSize(.large)
        } else {
            Button(primaryActionTitle) {
                performPrimaryAction()
            }
            .buttonStyle(TamaPrimaryButtonStyle())
            .disabled(model.snapshot == nil)
        }
    }


    private var advancedSetup: some View {
        VStack(alignment: .leading, spacing: 18) {
            AdvancedSetupSection(title: "Local hooks", symbol: "shippingbox.fill") {
                SetupRequirement(
                    title: runtimeInstalled ? "Installed" : "Not installed",
                    satisfied: runtimeInstalled
                )
                if let releaseID = model.installedHookReleaseID {
                    LabeledContent("Release") {
                        Text(releaseID)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
                if let nodeVersion = model.installedNodeVersion {
                    LabeledContent("Node", value: nodeVersion)
                }
                if runtimeInstalled, model.areHooksDisabled {
                    Button("Turn hooks on") {
                        isConfirmingGlobalEnable = true
                    }
                    .disabled(model.isPolicyMutationInProgress)
                } else if !runtimeInstalled, bundledPolicyIsValid {
                    Button("Install local hooks") {
                        isConfirmingRuntimeInstall = true
                    }
                    .disabled(model.isPolicyMutationInProgress)
                }
            }

            Divider()

            AdvancedSetupSection(title: "System protection", symbol: "lock.shield.fill") {
                SetupStatusLabel(text: model.systemPolicyServiceStatus, isHealthy: backendReady)
                if !backendReady {
                    HStack {
                        Button("Allow system protection") {
                            isConfirmingBackendRegistration = true
                        }
                        .disabled(!runtimeInstalled || model.isPolicyMutationInProgress)
                        Button("Approval settings") {
                            model.openSystemPolicyApprovalSettings()
                        }
                        Button("Full Disk Access") {
                            model.openFullDiskAccessSettings()
                        }
                        Button("Refresh") {
                            Task { await model.refreshSystemPolicyStatus() }
                        }
                    }
                }
            }

            Divider()

            AdvancedSetupSection(title: "Active session", symbol: "terminal.fill") {
                if let sessionError = model.sessionErrorMessage {
                    Label(sessionError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                } else if model.agentSessions.isEmpty {
                    Text("No supervised coding-agent session is currently reporting.")
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
                        Button("Protect selected session") {
                            isConfirmingSessionEnable = true
                        }
                        .disabled(model.isPolicyMutationInProgress || model.snapshot == nil)
                    }
                }
                Button("Refresh sessions", systemImage: "arrow.clockwise") {
                    Task { await model.refreshAgentSessions() }
                }
            }

            Divider()

            AdvancedSetupSection(title: "Readiness", symbol: "checklist") {
                SetupRequirement(
                    title: "Bundled policy is valid",
                    satisfied: bundledPolicyIsValid
                )
                SetupRequirement(
                    title: "Local hooks are installed and enabled",
                    satisfied: hooksEnabled
                )
                SetupRequirement(
                    title: "System protection is enabled",
                    satisfied: backendReady
                )
                SetupRequirement(
                    title: "An active protected session is reporting",
                    satisfied: model.setupReadySession != nil
                )
            }
        }
    }

    private func performPrimaryAction() {
        if !runtimeInstalled {
            isConfirmingRuntimeInstall = true
        } else if model.areHooksDisabled {
            isConfirmingGlobalEnable = true
        } else if !backendReady {
            isConfirmingBackendRegistration = true
        } else if model.agentSessions.isEmpty {
            Task { await model.refreshAgentSessions() }
        } else if !model.areAllHooksEnabledInSelectedSession {
            isConfirmingSessionEnable = true
        } else {
            Task { await model.refreshAgentSessions() }
        }
    }
}

private struct AdvancedSetupSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TamaPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Color.accentColor.opacity(
                    isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.32
                ),
                in: RoundedRectangle(cornerRadius: 9)
            )
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
