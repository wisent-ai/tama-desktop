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
            title: "Local enforcement",
            detail: "The verified runtime under Application Support, and the privileged macOS components that gate processes and network traffic.",
            trailing: model.areHooksDisabled ? "bypassed" : "active"
        ) {
            WisentPanel {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
                    HStack(alignment: .top, spacing: WisentDesign.Space.x4) {
                        WisentField(
                            label: "Installed release",
                            value: model.installedHookReleaseID ?? "Not installed by Tama",
                            tone: model.installedHookReleaseID == nil ? .neutral : .success
                        )
                        WisentField(
                            label: "Privileged backend",
                            value: model.systemPolicyServiceStatus,
                            tone: TamaTone.systemPolicy(model.systemPolicyServiceStatus)
                        )
                    }
                    if let node = model.installedNodeVersion {
                        HStack(alignment: .top, spacing: WisentDesign.Space.x4) {
                            WisentField(label: "Node version", value: node)
                            WisentField(
                                label: "Node executable",
                                value: model.installedNodeExecutable ?? "Not recorded"
                            )
                        }
                    }
                    Divider()
                    HStack(spacing: WisentDesign.Space.x2) {
                        if model.installedHookReleaseID == nil {
                            WisentActionButton(
                                action: WisentAction(
                                    "Install local runtime",
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
                                    "Register privileged backend",
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
                    Text("macOS asks for approval of Tama's daemon, System Extension, network filter and Full Disk Access where each is required. Registration is per machine and survives updates.")
                        .font(WisentTypeScale.caption())
                        .foregroundStyle(WisentDesign.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Build

    private var build: some View {
        WisentSectionBox(
            title: "Build",
            detail: "What this application is, and which hook release it carries.",
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
                            label: "Bundled hook release",
                            value: buildIdentity.hookRelease?.releaseId ?? "Not recorded"
                        )
                        WisentField(
                            label: "Hook source revision",
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
            title: "Deactivate local policy enforcement on this machine",
            lines: [
                "Every managed hook dispatcher is disabled, so \(counted(model.hooks.filter(\.isBlocking).count, "blocking policy")) stops refusing unsafe work.",
                "Tama unregisters its privileged daemon, System Extension and network filter. macOS may require a restart to finish removal.",
                "Supervised sessions that are running keep running without enforcement. Stop them first if that matters.",
            ],
            reasonCode: "hook-emergency-state.v1 disabled=true; SMAppService unregister",
            listing: [
                "~/Library/Application Support/Tama/hook-emergency-state.json",
                "~/Library/Application Support/Tama/emergency-backup/manifest.json",
                "ai.wisent.tama.system-policy",
                "ai.wisent.tama.network-filter",
            ],
            footnote: "recovery files are preserved; reinstalling verifies the bundled release before restoring dispatchers",
            actions: [
                WisentAction("Deactivate everything", kind: .destructive) {
                    isDecidingDeactivation = false
                    model.deactivateLocalSetup()
                },
                WisentAction("Keep enforcement", kind: .primary) {
                    isDecidingDeactivation = false
                },
            ]
        )
    }
}
