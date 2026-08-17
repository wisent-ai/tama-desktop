import SwiftUI
import WisentAuth
import WisentDesktopUpdate
import WisentDesignSystem

@main
struct TamaDesktopApp: App {
    @StateObject private var auth = WisentAuthStore(productName: "Tama")
    @StateObject private var updater = WisentUpdater()
    @State private var isInspectingPolicy = false

    var body: some Scene {
        WindowGroup("Tama") {
            Group {
                if Self.testIdentityOverride != nil {
                    TamaAuthorizedControlRootView(bypassesSetup: true)
                        .environment(\.wisentIdentity, Self.testIdentityOverride)
                } else if isInspectingPolicy {
                    TamaInspectionRootView {
                        isInspectingPolicy = false
                    }
                } else {
                    WisentAuthGate(store: auth) {
                        TamaAuthorizedControlRootView()
                    }
                    .toolbar {
                        ToolbarItem {
                            Button("Inspect policy without controls", systemImage: "eye") {
                                isInspectingPolicy = true
                            }
                        }
                    }
                }
            }
            .frame(
                minWidth: WisentAppLayout.minimumWindowWidth,
                minHeight: WisentAppLayout.minimumWindowHeight
            )
            .tint(WisentDesign.brand)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                WisentCheckForUpdatesCommand(updater: updater)
            }
        }
    }

    private static var testIdentityOverride: WisentIdentity? {
#if DEBUG
        guard ProcessInfo.processInfo.environment["TAMA_TEST_IDENTITY"] == "1" else { return nil }
        return WisentIdentity(
            userID: "tama-ui-tests",
            email: "tama-ui-tests@wisent.test",
            organization: WisentOrganization(id: "tama-ui-tests", slug: "tama-ui-tests", name: "Tama UI Tests", role: "owner"),
            accessToken: "tama-ui-tests"
        )
#else
        nil
#endif
    }
}

/// The same shell, with the control destinations removed.
///
/// The baseline shipped a second sidebar here whose tags mapped onto different
/// screens, so `violations` meant Overview in one window and Violations in the
/// other.
private struct TamaInspectionRootView: View {
    @StateObject private var model = AppModel(inspectionOnly: true)
    @StateObject private var violations = ViolationsModel()
    let continueToSignIn: () -> Void

    var body: some View {
        RootView(
            model: model,
            violations: violations,
            continueToSignIn: continueToSignIn
        )
    }
}

private struct TamaAuthorizedControlRootView: View {
    @Environment(\.wisentIdentity) private var identity
    let bypassesSetup: Bool

    init(bypassesSetup: Bool = false) {
        self.bypassesSetup = bypassesSetup
    }

    @ViewBuilder
    var body: some View {
        if let identity,
           let authorization = ControlAuthorization(identity: identity) {
            TamaAuthenticatedRootView(
                authorization: authorization,
                bypassesSetup: bypassesSetup
            )
        } else {
            ZStack {
                WisentCanvasBackground()
                WisentEmptyState(
                    title: "Policy controls unavailable",
                    detail: "A current owner, admin, or member role in the selected Wisent organization is required.",
                    symbol: "person.badge.shield.checkmark"
                )
            }
        }
    }
}

private struct TamaAuthenticatedRootView: View {
    @StateObject private var model: AppModel
    @StateObject private var violations: ViolationsModel
    @AppStorage("tama.hasCompletedSetup") private var hasCompletedSetup = false
    @StateObject private var firstUseJourney = TamaFirstUseJourney()
    let bypassesSetup: Bool

    init(authorization: ControlAuthorization, bypassesSetup: Bool) {
        _model = StateObject(
            wrappedValue: AppModel(authorization: authorization)
        )
        _violations = StateObject(
            wrappedValue: ViolationsModel(authorization: authorization)
        )
        self.bypassesSetup = bypassesSetup
    }

    var body: some View {
        Group {
            if bypassesSetup || hasCompletedSetup {
                RootView(model: model, violations: violations, continueToSignIn: nil)
                    .overlay(alignment: .bottom) {
                        if firstUseJourney.isAwaitingFirstSession {
                            firstSessionHint
                        }
                    }
            } else if firstUseJourney.isLoading {
                ZStack {
                    WisentCanvasBackground()
                    ProgressView("Loading Tama…")
                        .controlSize(.large)
                        .font(WisentTypeScale.bodyStrong())
                }
            } else if !firstUseJourney.isAtSetup {
                TamaOnboardingView(journey: firstUseJourney)
            } else {
                TamaSetupView(model: model) {
                    Task {
                        guard await firstUseJourney.completeSetup() else { return }
                        hasCompletedSetup = true
                    }
                }
            }
        }
        .task {
            await firstUseJourney.start()
            if hasCompletedSetup && !firstUseJourney.isCompleted {
                await firstUseJourney.reconcileCompletedSetup()
            }
            if !model.agentSessions.isEmpty {
                await firstUseJourney.observeSupervisedSession()
            }
        }
        .onChange(of: model.agentSessions.isEmpty) { _, isEmpty in
            guard !isEmpty else { return }
            Task { await firstUseJourney.observeSupervisedSession() }
        }
        .onAppear {
            model.startControlMonitoring()
        }
        .onDisappear {
            model.stopControlMonitoring()
            violations.cancelAllOperations()
        }
    }

    /// Waiting for the first supervised session is not a fault, so it is a quiet
    /// strip at the foot of the window rather than an alert.
    private var firstSessionHint: some View {
        HStack(spacing: WisentDesign.Space.x3) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WisentDesign.brand)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                Text(firstUseJourney.currentTitle)
                    .font(WisentTypeScale.bodyStrong())
                    .foregroundStyle(WisentDesign.ink)
                Text(firstUseJourney.currentBody)
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(WisentDesign.Space.x4)
        .frame(maxWidth: TamaOnboardingView.maximumWidth)
        .background(
            WisentDesign.surface,
            in: RoundedRectangle(cornerRadius: WisentDesign.Radius.medium)
        )
        .overlay {
            RoundedRectangle(cornerRadius: WisentDesign.Radius.medium)
                .stroke(WisentDesign.border, lineWidth: WisentDesign.hairline)
        }
        .padding(WisentDesign.Space.x4)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}
