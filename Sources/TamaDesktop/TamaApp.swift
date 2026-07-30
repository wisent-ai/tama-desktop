import SwiftUI
import WisentAuth

@main
struct TamaDesktopApp: App {
    @StateObject private var auth = WisentAuthStore(productName: "Tama")
    @AppStorage("tama.hasSeenWelcome") private var hasSeenWelcome = false
    @State private var destination: TamaDestination = .welcome

    var body: some Scene {
        WindowGroup("Tama") {
            if Self.testIdentityOverride != nil {
                // UI-test seam: TAMA_TEST_IDENTITY=1 skips the real Wisent
                // gate (Supabase OTP) with a synthetic identity so automated
                // journeys can exercise the signed-in UI without an account.
                TamaAuthorizedControlRootView()
                    .environment(\.wisentIdentity, Self.testIdentityOverride)
            } else if !hasSeenWelcome && destination == .welcome {
                TamaWelcomeView(
                    inspectPolicy: {
                        destination = .inspect
                    },
                    continueToSignIn: {
                        hasSeenWelcome = true
                        destination = .controls
                    }
                )
            } else if destination == .controls || (hasSeenWelcome && destination == .welcome) {
                WisentAuthGate(store: auth) {
                    TamaAuthorizedControlRootView()
                }
                .toolbar {
                    ToolbarItem {
                        Button("Inspect policy without controls", systemImage: "eye") {
                            destination = .inspect
                        }
                    }
                }
            } else {
                ReadOnlyRootView {
                    hasSeenWelcome = true
                    destination = .controls
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

    @ViewBuilder
    var body: some View {
        if let identity,
           let authorization = ControlAuthorization(identity: identity) {
            TamaControlRootView(authorization: authorization)
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

private struct TamaControlRootView: View {
    @StateObject private var model: AppModel
    @StateObject private var violations: ViolationsModel

    init(authorization: ControlAuthorization) {
        _model = StateObject(
            wrappedValue: AppModel(authorization: authorization)
        )
        _violations = StateObject(
            wrappedValue: ViolationsModel(authorization: authorization)
        )
    }

    var body: some View {
        RootView(model: model, violationsModel: violations)
    }
}

private enum TamaDestination {
    case welcome
    case inspect
    case controls
}

private struct TamaWelcomeView: View {
    let inspectPolicy: () -> Void
    let continueToSignIn: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Label("Tama", systemImage: "shield.lefthalf.filled")
                .font(.largeTitle.bold())
            Text("Local policy control for supervised coding agents")
                .font(.title2)
            Text(
                "Inspect the approved policy first. Installing the local runtime and "
                    + "registering privileged macOS components are separate actions that "
                    + "always require your confirmation."
            )
            .foregroundStyle(.secondary)
            GroupBox("Before you continue") {
                VStack(alignment: .leading) {
                    Label("Apple-silicon Mac running macOS Sonoma or newer", systemImage: "desktopcomputer")
                    Label("A Wisent account is required for policy changes", systemImage: "person.badge.key")
                    Label("Python and Node.js are needed only for local runtime workflows", systemImage: "terminal")
                    Label("Opening Tama does not install hooks or register services", systemImage: "checkmark.shield")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Link(
                    "Read onboarding",
                    destination: URL(
                        string: "https://github.com/wisent-ai/tama-desktop/blob/main/docs/onboarding.md"
                    )!
                )
                Spacer()
                Button("Inspect bundled policy") {
                    inspectPolicy()
                }
                Button("Continue to Wisent sign-in") {
                    continueToSignIn()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .accessibilityIdentifier("tama.welcome")
    }
}
