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
            } else {
                inspectionOnly
            }
            build
            deferredToCLI
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

    private var inspectionOnly: some View {
        WisentSectionBox(
            title: "Inspection mode",
            detail: "The sealed catalog and declared plan remain available. Install and deactivate controls appear when the managed Tama runtime is available.",
            trailing: "controls unavailable"
        ) {
            WisentPanel {
                WisentCapabilityList(
                    title: "Signing in adds",
                    items: [
                        "Live session capability, grants and decisions",
                        "Per-session hook enablement",
                        "Repository violation scan and repair",
                        "The local justification registries",
                        "Runtime installation and the privileged backend",
                    ],
                    isAvailable: false
                )
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


    // MARK: - What stays in the CLI

    /// Named rather than hidden. Each of these is a real capability of the core
    /// that deliberately has no button, and an operator is better served by the
    /// exact command than by hunting for a control that does not exist.
    private var deferredToCLI: some View {
        WisentSectionBox(
            title: "Only in the tama CLI",
            detail: "Operations this application deliberately does not perform, and the command that does.",
            trailing: "by design"
        ) {
            WisentPanel(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Self.deferred, id: \.command) { entry in
                        VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                            Text(entry.command)
                                .font(WisentTypeScale.identifier())
                                .foregroundStyle(WisentDesign.ink)
                                .textSelection(.enabled)
                            Text(entry.reason)
                                .font(WisentTypeScale.caption())
                                .foregroundStyle(WisentDesign.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(WisentDesign.Space.x4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                    }
                }
            }
        }
    }

    private struct DeferredCommand {
        let command: String
        let reason: String
    }

    private static let deferred = [
        DeferredCommand(
            command: "tama adaptive status | drift | queue | repair | apply",
            reason: "The adaptive doctor prints diagnostic key=value lines with no JSON contract, and drift hashes the live installed scripts. This application reads a sealed snapshot and states so on every screen; parsing terminal prose would let it disagree with the core silently."
        ),
        DeferredCommand(
            command: "tama adaptive install | uninstall | claude-config",
            reason: "These write the legacy-runner shim and the operator's Claude settings routing. Tama installs its own dispatchers only, and never edits another product's configuration."
        ),
        DeferredCommand(
            command: "tama docs --out <path>",
            reason: "Renders the same description, rationale, side effects and events the Hooks inspector already shows, into a Markdown file. A second rendering of one source would be a second thing to keep true."
        ),
        DeferredCommand(
            command: "tama verify",
            reason: "Runs the release's own hook-block fixtures. Test execution and its evidence belong to Probierz, not to a desktop button."
        ),
        DeferredCommand(
            command: "tama hooks add | remove --root <source-tree>",
            reason: "Mutates a source tree's registry and reseals it. The catalog in this build is sealed at build time, so editing it from here would produce a policy no release can reproduce."
        ),
        DeferredCommand(
            command: "tama install --set-git-config",
            reason: "Writes user-global Git configuration. The Install plan screen states the exact paths and the command, so the operator approves it where the change is visible."
        ),
        DeferredCommand(
            command: "tama clean --model kimi | --max-rounds N | --dry-run | --skip",
            reason: "Repair from this application is deliberately one shape: Codex, bounded rounds, mandatory final rescan. Every other combination stays where its output is fully visible."
        ),
    ]

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
