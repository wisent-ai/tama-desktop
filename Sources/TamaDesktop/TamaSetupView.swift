import SwiftUI
import WisentDesignSystem

/// First run, and the only screen in the application that shouts its own name.
///
/// A hero header earns its 24 pt here because the operator has never seen this
/// window before and there is exactly one thing to do on it. Every other screen
/// uses the 44 pt context bar instead.
struct TamaSetupView: View {
    @ObservedObject var model: AppModel
    let complete: () -> Void

    private static let maximumWidth: CGFloat = 820

    private var runtimeInstalled: Bool { model.installedHookReleaseID != nil }
    private var hooksEnabled: Bool { runtimeInstalled && !model.areHooksDisabled }
    private var backendReady: Bool { model.systemPolicyServiceStatus == "Enabled" }
    private var bundledPolicyIsValid: Bool { model.snapshot?.validation.ok == true }

    var body: some View {
        WisentScreen(
            title: "Tama",
            scope: "Setup",
            freshness: model.installedHookReleaseID.map { "release \($0.prefix(8))" }
        ) {
            WisentPageHeader(
                eyebrow: "Local enforcement",
                title: statusTitle,
                detail: statusMessage,
                symbol: statusSymbol,
                tone: statusTone
            )
            WisentMutationBar(outcome: model.mutation) { model.clearMutation() }
            failureAlerts
            control
            readiness
            session
        }
        .accessibilityIdentifier("tama.setup")
    }

    // MARK: - Status

    private var statusTitle: String {
        if model.snapshot?.validation.ok == false { return "Hooks are unavailable" }
        if model.isSetupComplete { return "Hooks are on" }
        if hooksEnabled { return "Hooks need attention" }
        return "Hooks are off"
    }

    private var statusMessage: String {
        if model.snapshot?.validation.ok == false {
            return "This copy of Tama cannot verify its policy. Install a current build."
        }
        if model.isSetupComplete {
            return "Tama is protecting this Mac and the active coding-agent session."
        }
        if !runtimeInstalled { return "Turn hooks on to install Tama protection." }
        if model.areHooksDisabled { return "Protection is paused. Turn hooks on to restore it." }
        if !backendReady {
            return "Local hooks are running. Continue setup to allow system protection."
        }
        if model.agentSessions.isEmpty {
            return "System protection is ready. Open or resume a coding-agent session."
        }
        if !model.areAllHooksEnabled(in: model.selectedAgentSession) {
            return "Select an active session and enable its protection."
        }
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
        if !backendReady { return "Allow system protection" }
        if model.agentSessions.isEmpty { return "Check for an active session" }
        if !model.areAllHooksEnabled(in: model.selectedAgentSession) {
            return "Protect selected session"
        }
        return "Check again"
    }

    // MARK: - Failures

    @ViewBuilder private var failureAlerts: some View {
        if let catalogError = model.catalogError {
            WisentAlertPanel(
                tone: .danger,
                title: "Policy catalog unavailable",
                detail: catalogError,
                command: TamaCommand.status,
                actions: [
                    WisentAction("Check again", symbol: "arrow.clockwise", kind: .primary) {
                        Task { await model.refresh() }
                    }
                ]
            )
        }
        if let snapshot = model.snapshot, !snapshot.validation.ok {
            ForEach(snapshot.validation.errors, id: \.self) { error in
                WisentAlertPanel(
                    tone: .danger,
                    title: "Bundled policy is invalid",
                    detail: error,
                    command: TamaCommand.hooksValidate
                )
            }
        }
        if let sessionError = model.sessionError {
            WisentAlertPanel(
                tone: .danger,
                title: "Session status unavailable",
                detail: sessionError,
                command: TamaCommand.status,
                actions: [
                    WisentAction("Retry", symbol: "arrow.clockwise", kind: .primary) {
                        Task { await model.refreshAgentSessions() }
                    }
                ]
            )
        }
    }

    // MARK: - The one control

    private var control: some View {
        WisentPanel {
            HStack(spacing: WisentDesign.Space.x4) {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                    Text(model.isSetupComplete ? "Ready" : "Next step")
                        .font(WisentTypeScale.eyebrow())
                        .tracking(0.6)
                        .foregroundStyle(WisentDesign.muted)
                    Text(model.isSetupComplete ? "Open Tama" : primaryActionTitle)
                        .font(WisentTypeScale.section())
                        .foregroundStyle(WisentDesign.ink)
                }
                Spacer(minLength: WisentDesign.Space.x4)
                if model.isSetupComplete {
                    Button("Open Tama") { complete() }
                        .buttonStyle(WisentPrimaryButtonStyle())
                        .accessibilityIdentifier("tama.setup.finish")
                } else if model.snapshot?.validation.ok == false {
                    Button("Check again") { Task { await model.refresh() } }
                        .buttonStyle(WisentSecondaryButtonStyle())
                } else {
                    WisentActionButton(
                        action: WisentAction(
                            primaryActionTitle,
                            kind: .primary,
                            isEnabled: model.snapshot != nil && !model.isPolicyMutationInProgress
                        ) {
                            performPrimaryAction()
                        }
                    )
                }
            }
        }
    }

    /// Satisfied requirements and outstanding ones are two lists, not one list
    /// of half-filled circles: the operator reads the second one.
    private var readiness: some View {
        let requirements = [
            ("Bundled policy is valid", bundledPolicyIsValid),
            ("Local hooks are installed and enabled", hooksEnabled),
            ("System protection is enabled", backendReady),
            ("A protected session is reporting", model.setupReadySession != nil),
        ]
        return WisentSectionBox(
            title: "Readiness",
            detail: "All four must hold before control opens.",
            trailing: "\(requirements.filter(\.1).count) of \(requirements.count)"
        ) {
            WisentPanel {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
                    let satisfied = requirements.filter(\.1).map(\.0)
                    let outstanding = requirements.filter { !$0.1 }.map(\.0)
                    if !outstanding.isEmpty {
                        WisentCapabilityList(
                            title: "Outstanding",
                            items: outstanding,
                            isAvailable: false
                        )
                    }
                    if !satisfied.isEmpty {
                        WisentCapabilityList(
                            title: "Satisfied",
                            items: satisfied,
                            isAvailable: true
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder private var session: some View {
        if backendReady {
            WisentSectionBox(
                title: "Active session",
                detail: "Protection is proved by a live session reporting a matching release.",
                trailing: model.agentSessions.isEmpty
                    ? "none"
                    : counted(model.agentSessions.count, "session")
            ) {
                WisentPanel {
                    VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                        if model.agentSessions.isEmpty {
                            Text("Open or resume a supported coding-agent session. Tama publishes its state within a second, and this screen picks it up on its own.")
                                .font(WisentTypeScale.body())
                                .foregroundStyle(WisentDesign.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Picker("Session", selection: $model.selectedAgentSessionID) {
                                ForEach(model.agentSessions) { session in
                                    Text(session.displayName).tag(Optional(session.id))
                                }
                            }
                            .labelsHidden()
                            if let session = model.selectedAgentSession {
                                sessionRequirements(session)
                            }
                        }
                        WisentActionButton(
                            action: WisentAction(
                                "Refresh sessions",
                                symbol: "arrow.clockwise",
                                kind: .secondary
                            ) {
                                Task { await model.refreshAgentSessions() }
                            }
                        )
                    }
                }
            }
        }
    }

    private func sessionRequirements(_ session: AgentSessionRecord) -> some View {
        let runtimeMatches = model.installedHookReleaseID.map { installed in
            session.runtime.map { runtime in
                runtime.installedReleaseId == installed
                    && runtime.loadedReleaseId == installed
                    && runtime.registryLoadError == nil
                    && !runtime.reloadRequired
                    && runtime.reloadPending != true
            } ?? false
        } ?? false
        let hooksLoaded = session.runtime.map { runtime in
            runtime.registeredHookCount > .zero
                && runtime.loadedHookCount == runtime.registeredHookCount
                && runtime.unknownHookIds.isEmpty
                && !session.globallyDisabled
                && session.disabledHookIds.isEmpty
        } ?? false
        let kernelGated = session.systemPolicy.map { policy in
            policy.ready && policy.mode == "kernel-gated" && policy.error == nil
        } ?? false
        let requirements = [
            ("Installed and loaded release identities match", runtimeMatches),
            ("Every registered hook is loaded and enabled", hooksLoaded),
            ("System policy is kernel-gated", kernelGated),
        ]
        return VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
            let outstanding = requirements.filter { !$0.1 }.map(\.0)
            let satisfied = requirements.filter(\.1).map(\.0)
            if !outstanding.isEmpty {
                WisentCapabilityList(title: "Outstanding", items: outstanding, isAvailable: false)
            }
            if !satisfied.isEmpty {
                WisentCapabilityList(title: "Reporting", items: satisfied, isAvailable: true)
            }
        }
    }

    private func performPrimaryAction() {
        if !runtimeInstalled {
            model.installLocalRuntime()
        } else if model.areHooksDisabled {
            model.setHooksDisabled(false)
        } else if !backendReady {
            model.installSystemPolicyService()
        } else if let session = model.selectedAgentSession,
                  !model.areAllHooksEnabled(in: session) {
            model.enableAllHooks(in: session)
        } else {
            Task { await model.refreshAgentSessions() }
        }
    }
}
