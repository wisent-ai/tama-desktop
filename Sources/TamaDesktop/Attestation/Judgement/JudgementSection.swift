import SwiftUI
import WisentDesignSystem

struct JudgementSection: View {
    @StateObject private var model = JudgementModel()

    var body: some View {
        WisentSectionBox(
            title: "Review failures and alternatives",
            detail: "An explicit local attestation is not an independent model review. It changes no consent or authorization."
        ) {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                TextField("Judgement request file", text: $model.request)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: model.request) { _, _ in model.clearInspection() }
                Button("Read review and failure") {
                    Task { await model.run("judgement/show") }
                }
                .disabled(!model.ready)
                if let working = model.working {
                    WisentSkeletonText(label: working)
                }
                if let result = model.mutationResult {
                    Text(result)
                        .textSelection(.enabled)
                }
                if let failure = model.failure {
                    WisentAlertPanel(tone: .danger, title: "Tama refused", detail: failure)
                }
                if let inspection = model.inspection {
                    Text(inspection.question)
                        .font(WisentTypeScale.identifierSmall())
                        .textSelection(.enabled)
                    if let failure = inspection.failure {
                        WisentAlertPanel(
                            tone: .warning, title: "Review unavailable", detail: failure.cause)
                        failureMetadata(failure)
                    } else if inspection.failureError == nil {
                        Text("No unavailable review has been recorded for this question.")
                    }
                    if let cause = inspection.failureError {
                        WisentAlertPanel(
                            tone: .danger, title: "Latest failure could not be read", detail: cause)
                    }
                    if let cause = inspection.attestationError {
                        WisentAlertPanel(
                            tone: .danger, title: "Attestation could not be read", detail: cause)
                    }
                    if let cause = inspection.historyError {
                        WisentAlertPanel(
                            tone: .danger, title: "Failure history could not be read", detail: cause)
                    }
                    if let failures = inspection.failures {
                        let otherAttempts = failures.last == inspection.failure
                            ? failures.dropLast() : failures[...]
                        if !otherAttempts.isEmpty {
                            DisclosureGroup("Other recorded failed attempts") {
                                ForEach(otherAttempts.indices, id: \.self) { index in
                                    let failure = otherAttempts[index]
                                    VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                                        Text(failure.cause)
                                        failureMetadata(failure)
                                    }
                                    .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    if let failure = inspection.failure {
                        if failure.attestable == nil {
                            Text("Eligibility for a local attestation is unknown for this failure. Its recorded cause remains available, but no local decision is authorized.")
                        } else if failure.attestable == false {
                            Text("This operation requires its original authority. A local statement cannot supply consent, credentials or a successful external action.")
                        } else if inspection.options.isEmpty {
                            Text("This question declares no decision options, so no local attestation can be recorded.")
                        }
                    } else {
                        Text("No readable latest failure establishes eligibility for a local attestation. Read the recorded causes before deciding how to repair it.")
                    }
                    Picker("Explicit decision", selection: $model.choice) {
                        Text("Choose a declared option").tag("")
                        ForEach(inspection.options, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    TextField("What was checked and why this decision holds", text: $model.reason, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Record local attestation") {
                            Task { await model.run("judgement/attest") }
                        }
                        .disabled(!model.ready || inspection.failure?.attestable != true || model.choice.isEmpty || model.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Withdraw local attestation") {
                            Task { await model.run("judgement/revoke") }
                        }
                        .disabled(!model.ready || (inspection.attestation == nil && inspection.attestationError == nil))
                    }
                    if let attestation = inspection.attestation {
                        VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                            Text("Source: \(attestation.source), not model review")
                            if let attester = attestation.attester {
                                Text("Attested by: \(attester.joined(separator: " / "))")
                            } else {
                                Text("Attested by the operator, outside an agent session")
                            }
                            Text("Decision: \(attestation.answer.choice)")
                            Text(attestation.answer.reason)
                            Text("Unavailable review: \(attestation.unavailable)")
                        }
                        .textSelection(.enabled)
                    }
                }
            }
            .disabled(model.working != nil)
        }
    }

    @ViewBuilder
    private func failureMetadata(_ failure: JudgementInspection.Failure) -> some View {
        if let observed = failure.observedAtUnixMilliseconds {
            Text("Observed at Unix milliseconds: \(observed)")
                .font(WisentTypeScale.identifierSmall())
        }
        if let caller = failure.caller {
            Text("Caller: \(caller.joined(separator: " / "))")
        }
        if let cause = failure.attributionError {
            WisentAlertPanel(tone: .danger, title: "Caller could not be identified", detail: cause)
        }
        if let cause = failure.priorFailureError {
            WisentAlertPanel(tone: .danger, title: "Earlier failure state could not be read", detail: cause)
        }
    }
}
