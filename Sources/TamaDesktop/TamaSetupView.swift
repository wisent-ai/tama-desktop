import SwiftUI
import WisentDesignSystem

struct TamaSetupView: View {
    @ObservedObject var model: AppModel
    let complete: () -> Void

    @State private var isShowingAdvancedSetup = false
    @State private var isConfirmingRuntimeInstall = false
    @State private var isConfirmingBackendRegistration = false
    @State private var isConfirmingGlobalEnable = false
    @State private var isConfirmingSessionEnable = false

    private var runtimeInstalled: Bool { model.installedHookReleaseID != nil }
    private var hooksEnabled: Bool { runtimeInstalled && !model.areHooksDisabled }
    private var backendReady: Bool { model.systemPolicyServiceStatus == "Enabled" }
    private var bundledPolicyIsValid: Bool { model.snapshot?.validation.ok == true }

    private var statusTitle: String {
        if model.snapshot?.validation.ok == false { return "Hooks are unavailable" }
        if model.isSetupComplete { return "Hooks are on" }
        if hooksEnabled { return "Hooks need attention" }
        return "Hooks are off"
    }

    private var statusMessage: String {
        if model.snapshot?.validation.ok == false { return "This copy of Tama cannot verify its policy. Install a current build." }
        if model.isSetupComplete { return "Tama is protecting this Mac and the active coding-agent session." }
        if !runtimeInstalled { return "Turn hooks on to install Tama protection." }
        if model.areHooksDisabled { return "Protection is paused. Turn hooks on to restore it." }
        if !backendReady { return "Local hooks are running. Continue setup to allow system protection." }
        if model.agentSessions.isEmpty { return "System protection is ready. Open or resume a coding-agent session." }
        if !model.areAllHooksEnabledInSelectedSession { return "Select an active session and enable its protection." }
        return "Waiting for the selected session to report protected status."
    }

    private var statusSymbol: String {
        if model.snapshot?.validation.ok == false { return "xmark.shield.fill" }
        if model.isSetupComplete { return "checkmark.shield.fill" }
        if hooksEnabled { return "exclamationmark.shield.fill" }
        return "shield.slash.fill"
    }

    private var statusTone: WisentTone {
        if model.snapshot?.validation.ok == false { return .danger }
        if model.isSetupComplete { return .success }
        if hooksEnabled { return .warning }
        return .neutral
    }

    private var primaryActionTitle: String {
        if !runtimeInstalled || model.areHooksDisabled { return "Turn hooks on" }
        if !backendReady { return "Continue setup" }
        if model.agentSessions.isEmpty { return "Check for an active session" }
        if !model.areAllHooksEnabledInSelectedSession { return "Protect selected session" }
        return "Check again"
    }

    var body: some View {
        ZStack {
            WisentCanvasBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x6) {
                    WisentPageHeader(
                        eyebrow: "Local enforcement",
                        title: "Set up Tama",
                        detail: "Install verified policy, approve the macOS backend, and confirm protection in a live coding-agent session.",
                        symbol: "shield.lefthalf.filled",
                        tone: statusTone
                    )
                    masterControl
                    DisclosureGroup(isExpanded: $isShowingAdvancedSetup) {
                        advancedSetup.padding(.top, WisentDesign.Space.x4)
                    } label: {
                        Label("Advanced setup and diagnostics", systemImage: "wrench.and.screwdriver")
                            .font(WisentTypography.bodyMedium(13))
                            .foregroundStyle(WisentDesign.ink)
                    }
                    .padding(WisentDesign.Space.x4)
                    .background(WisentDesign.surface, in: RoundedRectangle(cornerRadius: WisentDesign.Radius.large))
                    .overlay {
                        RoundedRectangle(cornerRadius: WisentDesign.Radius.large)
                            .stroke(WisentDesign.border, lineWidth: WisentDesign.hairline)
                    }
                }
                .frame(maxWidth: TamaLayout.setupMaximumWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(WisentDesign.Space.x8)
            }
        }
        .navigationTitle("Hooks")
        .accessibilityIdentifier("tama.setup")
        .confirmationDialog("Turn hooks on?", isPresented: $isConfirmingRuntimeInstall, titleVisibility: .visible) {
            Button("Install and continue") { model.installLocalRuntime() }
                .disabled(model.isPolicyMutationInProgress)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Tama will install its verified local protection files while preserving unrelated settings.")
        }
        .confirmationDialog("Allow system protection?", isPresented: $isConfirmingBackendRegistration, titleVisibility: .visible) {
            Button("Continue") { Task { await model.installSystemPolicyService() } }
                .disabled(model.isPolicyMutationInProgress)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("macOS may ask you to approve Tama and Full Disk Access. Tama uses these permissions to enforce process and network policy.")
        }
        .confirmationDialog("Resume Tama protection?", isPresented: $isConfirmingGlobalEnable, titleVisibility: .visible) {
            Button("Turn hooks on") { model.setHooksDisabled(false) }
                .disabled(model.isPolicyMutationInProgress)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Tama will restore every managed hook dispatcher on this Mac.")
        }
        .confirmationDialog("Protect the selected session?", isPresented: $isConfirmingSessionEnable, titleVisibility: .visible) {
            Button("Enable protection") { model.enableAllHooksInSelectedSession() }
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
            Button("OK", role: .cancel) { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }

    private var masterControl: some View {
        WisentPanel(padding: WisentDesign.Space.x6) {
            HStack(spacing: WisentDesign.Space.x5) {
                Image(systemName: statusSymbol)
                    .font(.system(size: TamaLayout.setupStatusSymbolSize, weight: .semibold))
                    .foregroundStyle(statusTone.color)
                    .frame(
                        width: TamaLayout.setupStatusControlSize,
                        height: TamaLayout.setupStatusControlSize
                    )
                    .background(statusTone.softColor, in: RoundedRectangle(cornerRadius: WisentDesign.Radius.large))
                    .overlay {
                        RoundedRectangle(cornerRadius: WisentDesign.Radius.large)
                            .stroke(statusTone.color.opacity(0.18), lineWidth: WisentDesign.hairline)
                    }
                VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                    Text(statusTitle)
                        .font(WisentTypography.heading(24))
                        .foregroundStyle(WisentDesign.ink)
                    Text(statusMessage)
                        .font(WisentTypography.body(14))
                        .foregroundStyle(WisentDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: WisentDesign.Space.x4)
                primaryControl
            }
        }
    }

    @ViewBuilder
    private var primaryControl: some View {
        if model.isPolicyMutationInProgress {
            ProgressView().controlSize(.small).accessibilityLabel("Updating Tama protection")
        } else if model.isSetupComplete {
            Button("Open Tama") { complete() }
                .buttonStyle(WisentPrimaryButtonStyle())
                .accessibilityIdentifier("tama.setup.finish")
        } else if model.snapshot?.validation.ok == false {
            Button("Check again") { Task { await model.refresh() } }
                .buttonStyle(WisentSecondaryButtonStyle())
        } else {
            Button(primaryActionTitle) { performPrimaryAction() }
                .buttonStyle(WisentPrimaryButtonStyle())
                .disabled(model.snapshot == nil)
        }
    }

    private var advancedSetup: some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
            TamaPanelSection("Local hooks", detail: "Integrity-sealed runtime and managed dispatchers") {
                TamaRequirement(title: runtimeInstalled ? "Installed" : "Not installed", satisfied: runtimeInstalled)
                if let releaseID = model.installedHookReleaseID {
                    LabeledContent("Release") {
                        Text(releaseID).font(WisentTypography.mono(11)).textSelection(.enabled)
                    }
                }
                if let nodeVersion = model.installedNodeVersion { LabeledContent("Node", value: nodeVersion) }
                if runtimeInstalled, model.areHooksDisabled {
                    Button("Turn hooks on") { isConfirmingGlobalEnable = true }
                        .buttonStyle(WisentPrimaryButtonStyle())
                        .disabled(model.isPolicyMutationInProgress)
                } else if !runtimeInstalled, bundledPolicyIsValid {
                    Button("Install local hooks") { isConfirmingRuntimeInstall = true }
                        .buttonStyle(WisentPrimaryButtonStyle())
                        .disabled(model.isPolicyMutationInProgress)
                }
            }

            TamaPanelSection("System protection", detail: "Privileged macOS process and network policy") {
                WisentBadge(model.systemPolicyServiceStatus, symbol: backendReady ? "checkmark.circle.fill" : "circle.dashed", tone: backendReady ? .success : .warning)
                if !backendReady {
                    HStack(spacing: WisentDesign.Space.x2) {
                        Button("Allow system protection") { isConfirmingBackendRegistration = true }
                            .buttonStyle(WisentPrimaryButtonStyle())
                            .disabled(!runtimeInstalled || model.isPolicyMutationInProgress)
                        Button("Approval settings") { model.openSystemPolicyApprovalSettings() }
                            .buttonStyle(WisentSecondaryButtonStyle())
                        Button("Full Disk Access") { model.openFullDiskAccessSettings() }
                            .buttonStyle(WisentSecondaryButtonStyle())
                        Button("Refresh") { Task { await model.refreshSystemPolicyStatus() } }
                            .buttonStyle(WisentSecondaryButtonStyle())
                    }
                }
            }

            TamaPanelSection("Active session", detail: "Live provider runtime and per-session policy") {
                if let sessionError = model.sessionErrorMessage {
                    TamaNotice(title: "Session status unavailable", detail: sessionError, symbol: "exclamationmark.triangle.fill", tone: .danger)
                        .textSelection(.enabled)
                } else if model.agentSessions.isEmpty {
                    TamaNotice(title: "No supervised session", detail: "Open or resume a supported coding-agent session, then refresh this view.", symbol: "terminal", tone: .neutral)
                } else {
                    Picker("Session", selection: $model.selectedAgentSessionID) {
                        ForEach(model.agentSessions) { session in
                            Text(session.displayName).tag(Optional(session.id))
                        }
                    }
                    if let session = model.selectedAgentSession {
                        SessionSetupStatus(session: session, installedReleaseID: model.installedHookReleaseID)
                    }
                    if !model.areAllHooksEnabledInSelectedSession {
                        Button("Protect selected session") { isConfirmingSessionEnable = true }
                            .buttonStyle(WisentPrimaryButtonStyle())
                            .disabled(model.isPolicyMutationInProgress || model.snapshot == nil)
                    }
                }
                Button("Refresh sessions", systemImage: "arrow.clockwise") { Task { await model.refreshAgentSessions() } }
                    .buttonStyle(WisentSecondaryButtonStyle())
            }

            TamaPanelSection("Readiness", detail: "All requirements must be satisfied before control opens") {
                TamaRequirement(title: "Bundled policy is valid", satisfied: bundledPolicyIsValid)
                TamaRequirement(title: "Local hooks are installed and enabled", satisfied: hooksEnabled)
                TamaRequirement(title: "System protection is enabled", satisfied: backendReady)
                TamaRequirement(title: "An active protected session is reporting", satisfied: model.setupReadySession != nil)
            }
        }
    }

    private func performPrimaryAction() {
        if !runtimeInstalled { isConfirmingRuntimeInstall = true }
        else if model.areHooksDisabled { isConfirmingGlobalEnable = true }
        else if !backendReady { isConfirmingBackendRegistration = true }
        else if model.agentSessions.isEmpty { Task { await model.refreshAgentSessions() } }
        else if !model.areAllHooksEnabledInSelectedSession { isConfirmingSessionEnable = true }
        else { Task { await model.refreshAgentSessions() } }
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
        return runtime.registeredHookCount > 0
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
        VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
            TamaRequirement(title: "Installed and loaded release identities match", satisfied: runtimeMatches)
            TamaRequirement(title: "Every registered hook is loaded and enabled", satisfied: hooksLoaded)
            TamaRequirement(title: "System policy is kernel-gated", satisfied: kernelGated)
        }
    }
}
