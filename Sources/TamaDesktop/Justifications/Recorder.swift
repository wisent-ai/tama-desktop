import Foundation
import SwiftUI
import WisentDesignSystem

/// Recording a justification from the application, not only reading one.
///
/// The gates require a justification before a new file or test is written, and
/// the registries holding them sit inside the protected hook directory. The
/// CLI gained `tama justify` for that; this is the same capability on the
/// graphical surface, because a capability the CLI has, the interface has.
///
/// The sheet uses the same backend operation as the CLI and displays its
/// refusal without maintaining a second implementation of the rules.
struct JustificationRecorder: View {
    let collections: [JustificationCollection]
    let onRecorded: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var target = ""
    @State private var kind = Kind.file
    @State private var justification = ""
    @State private var quote = ""
    @State private var refusal: String?
    @State private var isRecording = false

    enum Kind: String, CaseIterable, Identifiable {
        case file
        case test

        var id: String { rawValue }

        var label: String {
            switch self {
            case .file: "New file"
            case .test: "New test"
            }
        }
    }
    var body: some View {
        WisentPanel {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
                WisentSectionHeader(
                    "Record a justification",
                    detail: "Recorded through Tama's backend using the same rules as the CLI."
                )
                picker
                field("Absolute path", text: $target, prompt: "/Users/…/src/module.rs", lines: .one)
                field(
                    "Justification",
                    text: $justification,
                    prompt: "What the file is for and why it exists.",
                    lines: .prose
                )
                if kind == .test {
                    field(
                        "Verbatim user request",
                        text: $quote,
                        prompt: "Copied word for word from the request that asked for this test.",
                        lines: .quote
                    )
                }
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

    /// How tall each text field stands. Layout only: nothing here changes what
    /// the CLI accepts.
    private enum FieldHeight {
        case one
        case quote
        case prose

        var lines: Int {
            switch self {
            case .one: Int("1")!
            case .quote: Int("3")!
            case .prose: Int("6")!
            }
        }
    }

    private var picker: some View {
        Picker("Registry", selection: $kind) {
            ForEach(Kind.allCases) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
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
            switch kind {
            case .file: collection.requirement.directUserQuoteField == nil
            case .test: collection.requirement.directUserQuoteField != nil
            }
        }?.requirement.minimumWords
    }

    private func record() {
        refusal = nil
        isRecording = true
        let request = JustificationRecordingClient.Request(
            target: target.trimmingCharacters(in: .whitespacesAndNewlines),
            isTest: kind == .test,
            justification: justification,
            quote: quote.trimmingCharacters(in: .whitespacesAndNewlines)
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

/// The existing file/test recorder shares the backend with CUA recording.
struct JustificationRecordingClient {
    struct Request {
        let target: String
        let isTest: Bool
        let justification: String
        let quote: String
    }

    private struct Recorded: Decodable {
        let recorded: String
    }

    func record(_ request: Request) async throws {
        let client = TamaClient(baseURL: try await TamaBackend.shared.endpoint())
        var body: [String: Any] = [
            "kind": request.isTest ? "test" : "file",
            "file": request.target,
            "justification": request.justification,
        ]
        if request.isTest { body["quote"] = request.quote }
        _ = try await client.post("justifications/record", body: body,
            as: Recorded.self, operation: "Recording a justification")
    }
}
