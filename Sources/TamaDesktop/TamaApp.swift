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
                    ReadOnlyRootView {
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
                minWidth: TamaLayout.minimumWindowWidth,
                minHeight: TamaLayout.minimumWindowHeight
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
                RootView(model: model, violationsModel: violations)
                    .overlay(alignment: .bottom) {
                        if firstUseJourney.isAwaitingFirstSession {
                            TamaNotice(
                                title: firstUseJourney.currentTitle,
                                detail: firstUseJourney.currentBody,
                                symbol: "terminal.fill",
                                tone: .info
                            )
                            .frame(maxWidth: TamaLayout.setupMaximumWidth)
                            .padding(WisentDesign.Space.x4)
                            .allowsHitTesting(false)
                        }
                    }
            } else if firstUseJourney.isLoading {
                ZStack {
                    WisentCanvasBackground()
                    ProgressView("Loading Tama…")
                        .controlSize(.large)
                        .font(WisentTypography.bodyMedium(13))
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
}

