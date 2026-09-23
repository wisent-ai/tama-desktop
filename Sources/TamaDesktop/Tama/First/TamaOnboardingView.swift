import AppKit
import Foundation
import SwiftUI
import WisentDesignSystem
import WisentOnboarding

struct TamaOnboardingView: View {
    @ObservedObject var journey: TamaFirstUseJourney
    @ObservedObject var model: AppModel

    static let maximumWidth: CGFloat = 820

    private var isPolicyImport: Bool {
        journey.currentScreen?.screenId == "import_policy_bundle"
    }

    private var hasAcceptedPolicyImport: Bool {
        model.policyBundleImport?.accepted == true
    }

    var body: some View {
        ZStack {
            WisentCanvasBackground()

            VStack(alignment: .leading, spacing: WisentDesign.Space.x5) {
                WisentPanel(padding: WisentDesign.Space.x8) {
                    VStack(alignment: .leading, spacing: WisentDesign.Space.x6) {
                        WisentPageHeader(
                            eyebrow: "Policy control",
                            title: journey.currentScreen.flatMap {
                                $0.presentation.text("title")
                            } ?? journey.currentScreen?.titleKey ?? "Welcome to Tama",
                            detail: journey.currentScreen.flatMap {
                                $0.presentation.text("body")
                            } ?? journey.currentScreen?.bodyKey ?? "Prepare local policy enforcement for your coding agents.",
                            symbol: "checkmark.shield.fill"
                        )

                        if isPolicyImport {
                            policyImportResult
                        }

                        Divider()

                        HStack(spacing: WisentDesign.Space.x3) {
                            if !isPolicyImport || !hasAcceptedPolicyImport {
                                Button(isPolicyImport ? "Skip" : "Skip Explanation") {
                                    Task {
                                        if isPolicyImport {
                                            await journey.advance()
                                        } else {
                                            await journey.skipExplanation()
                                        }
                                    }
                                }
                                .buttonStyle(WisentSecondaryButtonStyle())
                            }

                            Spacer()

                            Button(
                                isPolicyImport
                                    ? (hasAcceptedPolicyImport ? "Continue" : "Choose bundle")
                                    : "Continue"
                            ) {
                                if isPolicyImport {
                                    if hasAcceptedPolicyImport {
                                        Task {
                                            await journey.advance(
                                                evidence: ["policy_bundle_imported": .boolean(true)]
                                            )
                                        }
                                    } else {
                                        choosePolicyBundle()
                                    }
                                } else {
                                    Task { await journey.advance() }
                                }
                            }
                            .buttonStyle(WisentPrimaryButtonStyle())
                            .disabled(isPolicyImport && (!model.allowsControl || model.isImportingPolicyBundle))
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                }
                if let errorMessage = journey.errorMessage {
                    WisentAlertPanel(
                        tone: .danger,
                        title: "Onboarding is unavailable",
                        detail: errorMessage,
                        actions: [
                            WisentAction("Dismiss", kind: .secondary) {
                                journey.dismissError()
                            }
                        ]
                    )
                }
            }
            .frame(maxWidth: Self.maximumWidth)
            .padding(WisentDesign.Space.x8)
        }
        .task(id: journey.currentScreen?.screenId) {
            await journey.expose()
        }
    }

    @ViewBuilder
    private var policyImportResult: some View {
        if !model.allowsControl {
            Text("Sign in with a control role to import. Skipping remains available.")
                .font(WisentTypeScale.caption())
                .foregroundStyle(WisentDesign.secondary)
        }
        if model.policyBundleMutation != .idle {
            WisentMutationBar(outcome: model.policyBundleMutation) {
                model.clearPolicyBundleMutation()
            }
        }
        if let result = model.policyBundleImport {
            if !result.conflicts.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                        ForEach(result.conflicts) { conflict in
                            Text("\(conflict.path) — \(conflict.reason)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(WisentDesign.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 120)
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
    }

    private func choosePolicyBundle() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Tama policy bundle"
        panel.message = "Choose a self-contained policy bundle or sealed release containing shared-hooks/registry.json. Import installs and enables zero hooks."
        panel.prompt = "Import"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let source = panel.url {
            Task {
                _ = await model.importPolicyBundle(from: source)
            }
        }
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    func text(_ key: String) -> String? {
        guard case let .string(value)? = self[key] else { return nil }
        return value
    }
}
