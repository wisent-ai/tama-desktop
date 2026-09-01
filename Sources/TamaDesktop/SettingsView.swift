import SwiftUI
import WisentDesignSystem

/// The local installation and the build behind it.
///
/// The baseline mixed these controls into the same page as the posture
/// verdicts, so installing a privileged backend sat one panel below a metric
/// tile. Installation is a decision an operator makes once; it belongs where
/// they go looking for it.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    let continueToSignIn: (() -> Void)?

    @State private var isDecidingDeactivation = false

    private var buildIdentity: BuildIdentity { .current }
    private var backendReady: Bool { model.systemPolicyServiceStatus == "Enabled" }

    var body: some View {
        WisentScreen(
            title: "Settings",
            scope: model.allowsControl ? nil : "inspection mode",
            freshness: buildIdentity.productVersion,
            actions: actions
        ) {
            WisentMutationBar(outcome: model.mutation) { model.clearMutation() }
            if model.allowsControl {
                localEnforcement
            }
            build
                    }
        .sheet(isPresented: $isDecidingDeactivation) { deactivationDecision }
    }

    private var actions: [WisentAction] {
        guard model.allowsControl else {
            guard let continueToSignIn else { return [] }
            return [
                WisentAction("Sign in for controls", symbol: "person.badge.key", kind: .primary) {
                    continueToSignIn()
                }
            ]
        }
        return [
            WisentAction("Reveal release", symbol: "folder", kind: .secondary) {
                model.revealHookRelease()
            }
        ]
    }

    // MARK: - Local enforcement

    private var localEnforcement: some View {
        WisentSectionBox(
            title: "Local protection",
            trailing: model.areHooksDisabled ? "off" : "on"
        ) {
            WisentPanel {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
                    HStack(alignment: .top, spacing: WisentDesign.Space.x4) {
                        WisentField(
                            label: "Installed policy",
                            value: model.installedHookReleaseID ?? "Not installed by Tama",
                            tone: model.installedHookReleaseID == nil ? .neutral : .success
                        )
                        WisentField(
                            label: "System protection",
                            value: model.systemPolicyServiceStatus,
                            tone: TamaTone.systemPolicy(model.systemPolicyServiceStatus)
                        )
                    }
                    Divider()
                    HStack(spacing: WisentDesign.Space.x2) {
                        if model.installedHookReleaseID == nil {
                            WisentActionButton(
                                action: WisentAction(
                                    "Install local protection",
                                    symbol: "shippingbox",
                                    kind: .primary,
                                    isEnabled: model.snapshot?.validation.ok == true
                                        && !model.isPolicyMutationInProgress
                                ) {
                                    model.installLocalRuntime()
                                }
                            )
                        }
                        if !backendReady {
                            WisentActionButton(
                                action: WisentAction(
                                    "Enable system protection",
                                    symbol: "lock.shield",
                                    kind: .primary,
                                    isEnabled: !model.isPolicyMutationInProgress
                                ) {
                                    model.installSystemPolicyService()
                                }
                            )
                            WisentActionButton(
                                action: WisentAction("Approval settings", kind: .secondary) {
                                    model.openSystemPolicyApprovalSettings()
                                }
                            )
                            WisentActionButton(
                                action: WisentAction("Full Disk Access", kind: .secondary) {
                                    model.openFullDiskAccessSettings()
                                }
                            )
                        }
                        Spacer(minLength: WisentDesign.Space.x2)
                        if model.installedHookReleaseID != nil
                            || model.systemPolicyServiceStatus != "Not registered" {
                            WisentActionButton(
                                action: WisentAction(
                                    "Deactivate",
                                    kind: .destructive,
                                    isEnabled: !model.isPolicyMutationInProgress
                                ) {
                                    isDecidingDeactivation = true
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Build

    private var build: some View {
        WisentSectionBox(
            title: "Build",
            trailing: buildIdentity.channel
        ) {
            WisentPanel {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                    HStack(alignment: .top, spacing: WisentDesign.Space.x4) {
                        WisentField(label: "Version", value: buildIdentity.productVersion)
                        WisentField(label: "Source revision", value: buildIdentity.displayedRevision)
                    }
                    Divider()
                    HStack(alignment: .top, spacing: WisentDesign.Space.x4) {
                        WisentField(
                            label: "Policy release",
                            value: buildIdentity.hookRelease?.releaseId ?? "Not recorded"
                        )
                        WisentField(
                            label: "Policy revision",
                            value: buildIdentity.hookRelease.map { release in
                                release.sourceDirty
                                    ? "\(release.sourceRevision) (dirty source)"
                                    : release.sourceRevision
                            } ?? "Not recorded",
                            tone: buildIdentity.hookRelease?.sourceDirty == true ? .warning : .neutral
                        )
                    }
                    Divider()
                    HStack(alignment: .top, spacing: WisentDesign.Space.x4) {
                        WisentField(
                            label: "Target",
                            value: "\(buildIdentity.platform) · \(buildIdentity.architecture)"
                        )
                        WisentField(label: "Built", value: buildIdentity.builtAt)
                    }
                }
            }
        }
    }


    // MARK: - The decision

    /// Deactivation removes machine-wide enforcement, and macOS may require a
    /// restart before the System Extension is actually gone. What ran unchecked
    /// in between cannot be recalled.
    private var deactivationDecision: some View {
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
