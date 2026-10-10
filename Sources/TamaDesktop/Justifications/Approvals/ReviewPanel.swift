import SwiftUI
import WisentDesignSystem

/// The view's task owns the native foreground reviewer and its cancellation.
struct TestReviewPanel: View {
    @State private var root = ""
    @State private var requestedRoot: String?
    @State private var busy = false
    @State private var result: TestReview?
    @State private var failure: String?

    var body: some View {
        WisentPanel {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                Text("Review tracked test files").font(WisentTypeScale.body()).bold()
                Text(
                    "Read unreviewed test content through Brama and retain its verdicts. This does not approve or execute tests."
                )
                .font(WisentTypeScale.caption())
                TextField("Repository path", text: $root)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Repository to review test files")
                    .disabled(busy || requestedRoot != nil)
                HStack {
                    Button("Review") { requestedRoot = root }
                        .disabled(busy || requestedRoot != nil || root.isEmpty)
                    if busy || requestedRoot != nil {
                        ProgressView().controlSize(.small)
                        Text("Waiting for the foreground review")
                        Button("Cancel") { requestedRoot = nil }
                    }
                }
                if let failure {
                    WisentAlertPanel(tone: .danger, title: "Review failed", detail: failure)
                }
                if let result {
                    Text(result.message).textSelection(.enabled)
                }
            }
        }
        .task(id: requestedRoot) {
            guard let selectedRoot = requestedRoot else { return }
            busy = true
            failure = nil
            result = nil
            defer {
                busy = false
                requestedRoot = nil
            }
            do {
                let reviewed = try await TestApprovalClient().review(root: selectedRoot)
                try Task.checkCancellation()
                result = reviewed
            } catch is CancellationError {
                failure = "Review cancelled; no successful completion was observed."
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
