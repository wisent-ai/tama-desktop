import SwiftUI
import WisentDesignSystem

struct StageView: View {
    @StateObject private var model = StageModel()

    var body: some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
            Text("Session-owned staging").font(WisentTypeScale.body())
            Text("Stage recorded edits without taking another session's hunks. Overlapping or missing evidence refuses the operation; no compiler is run.")
            TextField("Session identity", text: $model.session)
                .disabled(model.running)
            TextField("Repository checkout path", text: $model.repository)
                .disabled(model.running)
            HStack {
                Button("Inspect changes") { Task { await model.run(inspect: true) } }
                Button("Stage session changes") { Task { await model.run(inspect: false) } }
            }
            .disabled(!model.ready)
            if model.running {
                ProgressView("Reading receipts and projecting the index")
            }
            if let failure = model.failure {
                WisentAlertPanel(tone: .danger, title: "Staging refused", detail: failure)
            }
            if let report = model.report {
                Text(report.applied ? "Index updated" : "Inspected only; index unchanged")
                Text("Session: \(report.session)").textSelection(.enabled)
                Text("Repository: \(report.repository)").textSelection(.enabled)
                Text("Tree: \(report.tree)").textSelection(.enabled)
                if report.paths.isEmpty {
                    Text("No unstaged recorded changes remain.")
                } else {
                    Text(report.paths.joined(separator: "\n")).textSelection(.enabled)
                }
                DisclosureGroup("Recorded edit calls") {
                    Text(report.calls.joined(separator: "\n")).textSelection(.enabled)
                }
                Text("This is staging evidence, not a commit, a build or a qualification verdict.")
            }
        }
        .padding(WisentDesign.Space.x4)
    }
}
