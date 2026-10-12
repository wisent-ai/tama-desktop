import AppKit
import SwiftUI
import WisentDesignSystem

/// The attestations Tama reads in place of a model when none is declared: a
/// session's, that its task is finished, which the stop gates read, and a
/// commit's, against the push reviewer's standard, which review-push reads.
/// Record one from a file, show or remove the one the form names, and see
/// every kept record with its verdict today.
struct AttestationSection: View {
    @StateObject private var model = AttestationModel()

    var body: some View {
        WisentSectionBox(
            title: "Attestations",
            detail: "With no model declared, a session ends and a commit is pushed on its own attestation."
        ) {
            if let working = model.working {
                WisentSkeletonText(label: working)
            }
            if let failure = model.failure {
                WisentAlertPanel(tone: .danger, title: "Tama refused", detail: failure)
            }
            if let removed = model.removed {
                WisentAlertPanel(tone: .success, title: "Removed", detail: removed)
            }
            WisentPanel {
                form.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let verdict = model.verdict {
                verdictPanel(verdict)
            }
            if let shown = model.shown {
                shownPanel(shown)
            }
            recordsPanel
        }
        .task { model.list() }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
            HStack(spacing: WisentDesign.Space.x3) {
                Button("Choose file…") { chooseFile() }
                if let file = model.attestationFile {
                    Text(file.path)
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(WisentDesign.secondary)
                } else {
                    Text("No file chosen")
                        .font(WisentTypeScale.caption())
                        .foregroundStyle(WisentDesign.muted)
                }
            }
            TextField("Session id (read by the stop gates)", text: $model.session)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: WisentDesign.Space.x3) {
                TextField("Commit (read by review-push)", text: $model.commit)
                    .textFieldStyle(.roundedBorder)
                Button("Choose repository…") { chooseRepository() }
                if let repository = model.repository {
                    Text(repository.path)
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(WisentDesign.secondary)
                }
            }
            HStack(spacing: WisentDesign.Space.x3) {
                Button("Record") { model.record() }
                    .disabled(model.attestationFile == nil)
                Button("Show") { model.show() }
                Button("Remove") { model.removeNamed() }
                Button("Refresh list") { model.list() }
            }
            .disabled(model.working != nil)
        }
    }

    @ViewBuilder
    private func verdictPanel(_ verdict: AttestationReport) -> some View {
        if verdict.stands, let recorded = verdict.recorded {
            WisentAlertPanel(
                tone: .success, title: "\(verdict.subject) stands", detail: "Recorded at \(recorded).")
        } else {
            WisentAlertPanel(
                tone: .warning,
                title: "\(verdict.subject) does not stand; nothing was recorded",
                detail: verdict.refusals.joined(separator: "\n")
            )
        }
    }

    private func shownPanel(_ shown: ShownAttestation) -> some View {
        let claims = shown.attestation.attestations.sorted { $0.key < $1.key }
        return WisentPanel {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                Text("\(shown.kind) \(shown.id): \(shown.stands ? "stands" : "does not stand")")
                    .font(WisentTypeScale.eyebrow())
                ForEach(shown.refusals, id: \.self) { refusal in
                    Text(refusal).font(WisentTypeScale.caption()).foregroundStyle(WisentDesign.secondary)
                }
                ForEach(claims, id: \.key) { claim in
                    VStack(alignment: .leading) {
                        Text("\(claim.key): \(claim.value.confirmed == true ? "confirmed" : "not confirmed")")
                            .font(WisentTypeScale.identifierSmall())
                        if let how = claim.value.how {
                            Text(how).font(WisentTypeScale.caption()).foregroundStyle(WisentDesign.muted)
                        }
                    }
                }
                if let recorded = shown.recorded {
                    Text("Kept at \(recorded)")
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(WisentDesign.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var recordsPanel: some View {
        WisentPanel {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                Text("Kept attestations")
                    .font(WisentTypeScale.eyebrow())
                    .foregroundStyle(WisentDesign.muted)
                if model.records.isEmpty {
                    Text("No attestation is recorded.")
                        .font(WisentTypeScale.caption())
                        .foregroundStyle(WisentDesign.muted)
                }
                ForEach(model.records, id: \.subject) { record in
                    HStack(spacing: WisentDesign.Space.x3) {
                        Text(record.subject).font(WisentTypeScale.identifierSmall())
                        Text(record.stands ? "stands" : "does not stand")
                            .font(WisentTypeScale.caption())
                            .foregroundStyle(record.stands ? WisentDesign.secondary : WisentDesign.muted)
                        Spacer()
                        Button("Remove") { model.remove(record, in: model.repository) }
                            .disabled(model.working != nil)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            model.attestationFile = panel.url
        }
    }

    private func chooseRepository() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            model.repository = panel.url
        }
    }
}
