import SwiftUI
import WisentDesignSystem

/// Below the model service row: declare that this machine has no model, or
/// remove the declaration so each request goes to Stado's inference
/// alternatives (`stado capabilities call inference`), which ask whichever
/// answers. With no model, the stop gates that would ask one read the
/// session's recorded attestation (`AttestationSection`); review-push and
/// the turn-end gates read the attestation commits and answers carry
/// (`CarriedAttestationSection`) on every machine. A service and its key are
/// declared in the terminal (`tama model set --origin`), so the key never
/// crosses a request.
struct ModelChoiceSection: View {
    @ObservedObject var inspection: InspectionModel
    @StateObject private var choice = ModelChoiceModel()

    var body: some View {
        WisentSectionBox(
            title: "No model",
            detail:
                "Without Brama or any model, Tama still enforces every deterministic rule; pushes and ending answers carry their attestations, and sessions stand on their recorded ones."
        ) {
            if let working = choice.working {
                WisentSkeletonText(label: working)
            }
            if let failure = choice.failure {
                WisentAlertPanel(tone: .danger, title: "Tama refused", detail: failure)
            }
            WisentPanel {
                HStack(spacing: WisentDesign.Space.x3) {
                    Button("Declare no model") {
                        choice.declareNone { await inspection.loadModelService() }
                    }
                    Button("Use Stado's alternatives") {
                        choice.useStadoAlternatives { await inspection.loadModelService() }
                    }
                }
                .disabled(choice.working != nil)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
