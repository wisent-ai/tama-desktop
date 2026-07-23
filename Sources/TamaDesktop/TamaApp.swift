import SwiftUI
import WisentAuth

@main
struct TamaDesktopApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var violations = ViolationsModel()
    @StateObject private var auth = WisentAuthStore(productName: "Tama")

    var body: some Scene {
        WindowGroup("Tama") {
            WisentAuthGate(store: auth) {
                RootView(model: model, violationsModel: violations)
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
