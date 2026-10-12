import AppKit
import SwiftUI
import WisentDesignSystem

/// Below the model service row: declare that this machine has no model or
/// return Tama to Brama, and read or record a task's attestation, which is
/// what the stop gates read when no model is declared. A service and its key
/// are declared in the terminal (`tama model-provider set --origin`), so the
/// key never crosses a request.
struct ModelChoiceSection: View {
    @ObservedObject var inspection: InspectionModel
    @StateObject private var choice = ModelChoiceModel()

    var body: some View {
        WisentSectionBox(
            title: "No model",
            detail: "Without Brama or any model, Tama still enforces every deterministic rule; a session ends on its own attestation."
        ) {
            if let working = choice.working {
                WisentSkeletonText(label: working)
            }
            if let failure = choice.failure {
                WisentAlertPanel(tone: .danger, title: "Tama refused", detail: failure)
            }
            WisentPanel {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                    HStack(spacing: WisentDesign.Space.x3) {
                        Button("Declare no model") {
                            choice.declareNone { await inspection.loadModelService() }
                        }
                        Button("Return to Brama") {
                            choice.returnToBrama { await inspection.loadModelService() }
                        }
                    }
                    .disabled(choice.working != nil)
                    Divider()
                    attestationForm
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let verdict = choice.verdict {
                verdictPanel(verdict)
            }
        }
    }

    private var attestationForm: some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
            Text("Task or commit attestation")
                .font(WisentTypeScale.eyebrow())
                .foregroundStyle(WisentDesign.muted)
            HStack(spacing: WisentDesign.Space.x3) {
                Button("Choose file…") { chooseFile() }
                if let file = choice.attestationFile {
                    Text(file.path)
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(WisentDesign.secondary)
                } else {
                    Text("No file chosen")
                        .font(WisentTypeScale.caption())
                        .foregroundStyle(WisentDesign.muted)
                }
            }
            TextField("Session id (to record it for the stop gates)", text: $choice.session)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: WisentDesign.Space.x3) {
                TextField("Commit (to record it for review-push)", text: $choice.commit)
                    .textFieldStyle(.roundedBorder)
                Button("Choose repository…") { chooseRepository() }
                if let repository = choice.repository {
                    Text(repository.path)
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(WisentDesign.secondary)
                }
            }
            Button(
                choice.session.isEmpty && choice.commit.isEmpty
                    ? "Read attestation" : "Read and record attestation"
            ) {
                choice.attest()
            }
            .disabled(choice.working != nil || choice.attestationFile == nil)
        }
    }

    @ViewBuilder
    private func verdictPanel(_ verdict: AttestationVerdict) -> some View {
        if !verdict.finished {
            WisentAlertPanel(
                tone: .warning,
                title: "The attestation does not stand",
                detail: verdict.refusals.joined(separator: "\n")
            )
        } else if let recorded = verdict.recorded {
            WisentAlertPanel(tone: .success, title: "The attestation stands", detail: "Recorded at \(recorded).")
        } else {
            WisentAlertPanel(
                tone: .success,
                title: "The attestation stands",
                detail: "Read only; name a session or a commit to record it."
            )
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            choice.attestationFile = panel.url
        }
    }

    private func chooseRepository() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            choice.repository = panel.url
        }
    }
}
