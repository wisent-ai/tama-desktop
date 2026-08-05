import SwiftUI
import WisentAuth

@main
struct TamaDesktopApp: App {
    @StateObject private var auth = WisentAuthStore(productName: "Tama")
    @State private var isInspectingPolicy = false

    var body: some Scene {
        WindowGroup("Tama") {
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
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
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
            ContentUnavailableView(
                "Policy controls unavailable",
                systemImage: "person.badge.shield.checkmark",
                description: Text(
                    "A current owner, admin, or member role in the selected Wisent organization is required."
                )
            )
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
                            VStack(alignment: .leading, spacing: 6) {
                                Text(firstUseJourney.currentTitle)
                                    .font(.headline)
                                Text(firstUseJourney.currentBody)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(16)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                            .padding()
                            .allowsHitTesting(false)
                        }
                    }
            } else if firstUseJourney.isLoading {
                ProgressView("Loading Tama…")
                    .controlSize(.large)
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

