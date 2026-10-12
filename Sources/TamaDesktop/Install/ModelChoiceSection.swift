import SwiftUI
import WisentDesignSystem

/// Below the model service row: declare that this machine has no model or
/// return Tama to Brama. With no model, the stop gates and review-push read
/// the attestations of `AttestationSection`. A service and its key are
/// declared in the terminal (`tama model-provider set --origin`), so the key
/// never crosses a request.
struct ModelChoiceSection: View {
    @ObservedObject var inspection: InspectionModel
    @StateObject private var choice = ModelChoiceModel()

    var body: some View {
        WisentSectionBox(
            title: "No model",
            detail: "Without Brama or any model, Tama still enforces every deterministic rule; sessions and pushes stand on their own attestations."
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
                    Button("Return to Brama") {
                        choice.returnToBrama { await inspection.loadModelService() }
                    }
                }
                .disabled(choice.working != nil)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
