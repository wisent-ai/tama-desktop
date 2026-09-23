import AppKit
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
    @ObservedObject var journey: TamaFirstUseJourney
    let continueToSignIn: (() -> Void)?

    @State var isDecidingDeactivation = false
    @State var walkthroughOutcome: WalkthroughOutcome?
    @State var isReopeningWalkthrough = false

    /// What the last press of "Show it again" did, said where it was pressed.
    enum WalkthroughOutcome {
        case started
        case failed(String)
    }

    var buildIdentity: BuildIdentity { .current }
    var backendReady: Bool { model.systemPolicyServiceStatus == "Enabled" }

    var body: some View {
        WisentScreen(
            title: "Settings",
            scope: model.allowsControl ? nil : "inspection mode",
            freshness: buildIdentity.productVersion,
            actions: actions
        ) {
            WisentMutationBar(outcome: model.mutation) { model.clearMutation() }
            if model.allowsControl {
                policyBundles
                localEnforcement
            }
            build
            walkthrough
        }
        .sheet(isPresented: $isDecidingDeactivation) { deactivationDecision }
        .task { await model.refreshPolicyBundles() }
    }

    var actions: [WisentAction] {
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

    var localEnforcement: some View {
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

    // MARK: - Policy bundles

    var policyBundles: some View {
        WisentSectionBox(
            title: "Policy bundles",
            detail: "Adopt an existing self-contained Tama policy bundle or sealed release without installing or enabling it.",
            trailing: "\(model.policyBundles?.bundles.count ?? 0) inactive"
        ) {
            WisentPanel {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                    Button("Import policy bundle") { choosePolicyBundle() }
                        .buttonStyle(WisentPrimaryButtonStyle())
                        .disabled(model.isImportingPolicyBundle)
                    if model.policyBundleMutation != .idle {
                        WisentMutationBar(outcome: model.policyBundleMutation) {
                            model.clearPolicyBundleMutation()
                        }
                    }
                    if let result = model.policyBundleImport {
                        if !result.conflicts.isEmpty {
                            Text("No files changed. Review every conflict:")
                                .font(WisentTypeScale.bodyStrong())
                            ForEach(result.conflicts) { conflict in
                                Text("\(conflict.path) — \(conflict.reason)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(WisentDesign.secondary)
                            }
                            Button("Replace these reviewed bundle files") {
                                Task {
                                    _ = await model.importPolicyBundle(
                                        from: URL(fileURLWithPath: result.sourcePath, isDirectory: true),
                                        replace: true
                                    )
                                }
                            }
                            .buttonStyle(WisentSecondaryButtonStyle())
                            .disabled(model.isImportingPolicyBundle)
                        }
                        ForEach(result.rejections, id: \.self) { rejection in
                            Text("Rejected — \(rejection)")
                                .font(WisentTypeScale.caption())
                                .foregroundStyle(WisentDesign.danger)
                        }
                        ForEach(result.ignoredPaths, id: \.self) { ignored in
                            Text("Not a policy definition — \(ignored)")
                                .font(WisentTypeScale.caption())
                                .foregroundStyle(WisentDesign.secondary)
                        }
                    }
                    Divider()
                    if let bundles = model.policyBundles?.bundles, !bundles.isEmpty {
                        ForEach(bundles) { bundle in
                            VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                                Text(bundle.sourcePath)
                                    .font(.system(size: 11, design: .monospaced))
                                Text("\(bundle.hookCount) hooks · \(bundle.fileCount) files · SHA-256 \(bundle.sourceDigest.prefix(12))… · inactive")
                                    .font(WisentTypeScale.caption())
                                    .foregroundStyle(WisentDesign.secondary)
                            }
                        }
                    } else {
                        Text("No policy bundle imported. Tama remains empty and usable; the bundled release is unchanged.")
                            .font(WisentTypeScale.caption())
                            .foregroundStyle(WisentDesign.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    func choosePolicyBundle() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Tama policy bundle"
        panel.message = "Choose a self-contained Tama policy bundle or sealed release containing shared-hooks/registry.json. Import does not install or enable hooks."
        panel.prompt = "Import"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let source = panel.url {
            Task { _ = await model.importPolicyBundle(from: source) }
        }
    }

    // MARK: - Build

    var build: some View {
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

    // MARK: - First-run walkthrough



    // MARK: - The decision

}
