import SwiftUI
import WisentDesignSystem

/// A session's failed and refused calls, which Tama refuses to repeat
/// unchanged, and the stated retry that releases one.
struct FailedCallsSection: View {
    @StateObject private var model = FailedCallsModel()

    var body: some View {
        WisentSectionBox(
            title: "Failed calls",
            detail: "A call that failed or a gate refused is refused when repeated unchanged, until a file changes, the hook catalog changes, Oko binds its functionality to a defect, or a retry says why it differs."
        ) {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                TextField("Session", text: $model.session)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: model.session) { _, _ in model.clear() }
                Button("Read failed calls") {
                    Task { await model.run(retry: nil) }
                }
                .disabled(!model.ready)
                if let working = model.working {
                    WisentSkeletonText(label: working)
                }
                if let result = model.mutationResult {
                    Text(result).textSelection(.enabled)
                }
                if let failure = model.failure {
                    WisentAlertPanel(tone: .danger, title: "Tama refused", detail: failure)
                }
                if let listed = model.listed {
                    if listed.calls.isEmpty {
                        Text("This session keeps no failed call.")
                    }
                    TextField("Why the repeat differs", text: $model.because, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    ForEach(listed.calls.keys.sorted(), id: \.self) { call in
                        if let failed = listed.calls[call] {
                            VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                                Text("\(failed.tool), \(failed.by) at \(failed.at)")
                                Text(failed.said)
                                if let answer = failed.answer, !answer.isEmpty, answer != failed.said {
                                    Text(answer).font(WisentTypeScale.identifierSmall())
                                }
                                Text(call).font(WisentTypeScale.identifierSmall())
                                if let retry = failed.retry {
                                    Text("Repeat hold lifted (other gates still decide): \(retry)")
                                } else {
                                    Button("Retry with this reason") {
                                        Task { await model.run(retry: call) }
                                    }
                                    .disabled(!model.ready || model.because.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                            .textSelection(.enabled)
                        }
                    }
                }
            }
            .disabled(model.working != nil)
        }
    }
}
