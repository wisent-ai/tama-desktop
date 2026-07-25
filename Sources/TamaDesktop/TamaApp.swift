import SwiftUI
import WisentAuth

@main
struct TamaDesktopApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var violations = ViolationsModel()
    @StateObject private var auth = WisentAuthStore(productName: "Tama")

    var body: some Scene {
        WindowGroup("Tama") {
            if Self.testIdentityOverride != nil {
                // UI-test seam: TAMA_TEST_IDENTITY=1 skips the real Wisent
                // gate (Supabase OTP) with a synthetic identity so automated
                // journeys can exercise the signed-in UI without an account.
                RootView(model: model, violationsModel: violations)
                    .environment(\.wisentIdentity, Self.testIdentityOverride)
            } else {
                WisentAuthGate(store: auth) {
                    RootView(model: model, violationsModel: violations)
                }
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }

    private static var testIdentityOverride: WisentIdentity? {
        guard ProcessInfo.processInfo.environment["TAMA_TEST_IDENTITY"] == "1" else { return nil }
        return WisentIdentity(
            userID: "tama-ui-tests",
            email: "tama-ui-tests@wisent.test",
            organization: WisentOrganization(id: "tama-ui-tests", slug: "tama-ui-tests", name: "Tama UI Tests", role: "owner"),
            accessToken: "tama-ui-tests"
        )
    }
}
