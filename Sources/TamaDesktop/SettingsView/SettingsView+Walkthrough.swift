import AppKit
import SwiftUI
import WisentDesignSystem

extension SettingsView {
    /// The first run is gated on `tama.hasCompletedSetup`, and nothing ever
    /// turned that back off, so the walkthrough was readable once per machine
    /// and then gone. Asking to read it again is a setting, not a reinstall.
    var walkthrough: some View {
        WisentSectionBox(
            title: "First-run walkthrough",
            detail: "See the walkthrough this product shows on a first run."
        ) {
            WisentPanel {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                    WisentActionButton(
                        action: WisentAction(
                            "Show it again",
                            symbol: "arrow.counterclockwise",
                            kind: .secondary,
                            isEnabled: !isReopeningWalkthrough
                        ) {
                            reopenWalkthrough()
                        }
                    )
                    switch walkthroughOutcome {
                    case .none:
                        EmptyView()
                    case .started:
                        Text("The walkthrough is on screen.")
                            .font(WisentTypeScale.caption())
                            .foregroundStyle(WisentDesign.success)
                    case let .failed(reason):
                        Text(reason)
                            .font(WisentTypeScale.caption())
                            .foregroundStyle(WisentDesign.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
    func reopenWalkthrough() {
        isReopeningWalkthrough = true
        Task {
            do {
                try await journey.showWalkthroughAgain()
                walkthroughOutcome = .started
            } catch {
                walkthroughOutcome = .failed(error.localizedDescription)
            }
            isReopeningWalkthrough = false
        }
    }
    /// Deactivation removes machine-wide enforcement, and macOS may require a
    /// restart before the System Extension is actually gone. What ran unchecked
    /// in between cannot be recalled.
    var deactivationDecision: some View {
        WisentDecisionDialog(
            tone: .danger,
            title: "Turn off policy protection on this machine",
            lines: [
                "Unsafe actions will no longer be blocked.",
                "Current sessions will keep running without policy checks.",
                "macOS may require a restart.",
            ],
            actions: [
                WisentAction("Turn off protection", kind: .destructive) {
                    isDecidingDeactivation = false
                    model.deactivateLocalSetup()
                },
                WisentAction("Keep protection", kind: .primary) {
                    isDecidingDeactivation = false
                },
            ]
        )
    }
}
