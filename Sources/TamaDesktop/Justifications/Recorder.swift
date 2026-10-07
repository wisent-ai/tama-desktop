import Foundation
import SwiftUI
import WisentDesignSystem

/// Recording a justification from the application, not only reading one.
///
/// The gate requires a justification before a new file is written, and the
/// registry holding them sits inside the protected hook directory. The CLI
/// gained `tama justify` for that; this is the same capability on the
/// graphical surface, because a capability the CLI has, the interface has.
/// Test code is not justified here: the operator approves it under Test
/// approvals, as `tama tests approve` does.
///
/// The sheet uses the same backend operation as the CLI and displays its
/// refusal without maintaining a second implementation of the rules.
struct JustificationRecorder: View {
    let collections: [JustificationCollection]
    let onRecorded: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var target = ""
    @State private var justification = ""
    @State private var refusal: String?
    @State private var isRecording = false

    var body: some View {
        WisentPanel {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
                WisentSectionHeader(
                    "Record a justification",
                    detail: "Recorded through Tama's backend using the same rules as the CLI."
                )
                field("Absolute path", text: $target, prompt: "/Users/…/src/module.rs", lines: .one)
                field(
                    "Justification",
                    text: $justification,
                    prompt: "What the file is for and why it exists.",
                    lines: .prose
                )
                length
                if let refusal {
                    WisentAlertPanel(tone: .danger, title: "Refused", detail: refusal)
                }
                HStack(spacing: WisentDesign.Space.x2) {
                    Spacer(minLength: .zero)
                    WisentActionButton(
                        action: WisentAction("Cancel", kind: .secondary) { dismiss() }
                    )
                    WisentActionButton(
                        action: WisentAction(
                            isRecording ? "Recording…" : "Record",
                            kind: .primary,
                            isEnabled: !isRecording
                        ) { record() }
                    )
                }
            }
            .frame(minWidth: WisentAppLayout.inspectorWidth)
        }
        .padding(WisentDesign.Space.x5)
    }

    /// How tall each text field stands, in lines: one for a title, six for
    /// prose. Layout only: nothing here changes what the CLI accepts.
    private enum FieldHeight {
        case one
        case prose

        private static let proseLines = 6

        var lines: Int {
            switch self {
            case .one: 1
            case .prose: Self.proseLines
            }
        }
    }

    /// The registry states its own minimum and the application reads it. When
    /// the registries could not be read, the requirement is stated as unknown
    /// rather than as a number nobody declared; the CLI still enforces it.
    @ViewBuilder
    private var length: some View {
        if let required = minimumWords {
            Text("\(words.formatted(.number)) of \(required.formatted(.number)) words")
                .font(WisentTypeScale.identifierSmall())
                .foregroundStyle(words >= required ? WisentDesign.secondary : WisentDesign.warning)
                .monospacedDigit()
        } else {
            Text("\(words.formatted(.number)) words; the registry did not state its minimum")
                .font(WisentTypeScale.identifierSmall())
                .foregroundStyle(WisentDesign.secondary)
                .monospacedDigit()
        }
    }

    private func field(
        _ label: String,
        text: Binding<String>,
        prompt: String,
        lines: FieldHeight
    ) -> some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
            Text(label.uppercased())
                .font(WisentTypeScale.eyebrow())
                .tracking(0.6)
                .foregroundStyle(WisentDesign.muted)
            TextField(prompt, text: text, axis: .vertical)
                .lineLimit(lines.lines, reservesSpace: lines != .one)
                .font(WisentTypeScale.caption())
                .textFieldStyle(.roundedBorder)
        }
    }

    private var words: Int {
        justification.split(whereSeparator: { $0.isWhitespace }).count
    }

    private var minimumWords: Int? {
        collections.first { collection in
            collection.requirement.directUserQuoteField == nil
        }?.requirement.minimumWords
    }

    private func record() {
        refusal = nil
        isRecording = true
        let request = JustificationRecordingClient.Request(
            target: target.trimmingCharacters(in: .whitespacesAndNewlines),
            justification: justification
        )
        Task {
            do {
                try await JustificationRecordingClient().record(request)
                await MainActor.run {
                    isRecording = false
                    onRecorded(request.target)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isRecording = false
                    refusal = error.localizedDescription
                }
            }
        }
    }
}

/// The file recorder shares the backend with CUA recording.
struct JustificationRecordingClient {
    struct Request {
        let target: String
        let justification: String
    }

    private struct Recorded: Decodable {
        let recorded: String
    }

    func record(_ request: Request) async throws {
        let client = TamaClient()
        let body: [String: Any] = [
            "kind": "file",
            "file": request.target,
            "justification": request.justification,
        ]
        _ = try await client.request(
            "justifications/record", body: body,
            as: Recorded.self, describing: "Recording a justification")
    }
}
