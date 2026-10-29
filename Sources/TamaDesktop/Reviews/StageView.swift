import SwiftUI
import WisentDesignSystem

struct StageView: View {
    @StateObject private var model = StageModel()

    var body: some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
            Text("Session-owned staging").font(WisentTypeScale.body())
            Text(
                "Stage recorded edits without taking another session's hunks. A file whose recorded edits overlap, are gone, moved or rewritten is left out and named with its cause while the rest are staged; no compiler is run."
            )
            TextField("Session identity", text: $model.session)
                .disabled(model.running)
            TextField("Repository checkout path", text: $model.repository)
                .disabled(model.running)
            TextField(
                "Only these files, one per line (empty stages every recorded edit)",
                text: $model.paths, axis: .vertical
            )
            .disabled(model.running)
            TextField(
                "Sessions that wrote these files with it, one per line (empty names none)",
                text: $model.coauthors, axis: .vertical
            )
            .disabled(model.running)
            TextField(
                "Oko task taken over from a stopped session above (empty names none)",
                text: $model.task
            )
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
                if !report.paths.isEmpty {
                    Text(report.paths.joined(separator: "\n")).textSelection(.enabled)
                } else if report.omitted.isEmpty {
                    Text("No unstaged recorded changes remain.")
                } else {
                    Text(
                        "Nothing was staged: \(report.omitted.count) recorded change(s) remain unstaged, left out below with their causes."
                    )
                }
                if !report.omitted.isEmpty {
                    WisentAlertPanel(
                        tone: .warning, title: "Left out of this staging",
                        detail: report.omitted.map { "\($0.path): \($0.cause)" }.joined(
                            separator: "\n")
                    )
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
