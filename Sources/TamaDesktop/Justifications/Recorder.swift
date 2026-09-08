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
/// The rules are not restated here. The sheet runs the sealed `tama-cli` and
/// shows whatever it says, so the interface can never accept an entry the CLI
/// would refuse or refuse one it would accept.
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
                    detail: "Written through the sealed CLI, which enforces the same rules the gates read."
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

/// Runs `tama justify record` from the sealed release beside the application.
struct JustificationRecordingClient {
    struct Request {
        let target: String
        let isTest: Bool
        let justification: String
        let quote: String
    }

    enum Failure: LocalizedError {
        case cliMissing(String)
        case refused(String)

        var errorDescription: String? {
            switch self {
            case .cliMissing(let path): "The sealed Tama CLI is missing at \(path)."
            case .refused(let message): message
            }
        }
    }

    func record(_ request: Request) async throws {
        let executable = try Self.executableURL()
        var arguments = [
            "justify", "record",
            "--file", request.target,
            "--justification", request.justification,
            "--kind", request.isTest ? "test" : "file"
        ]
        if request.isTest {
            arguments += ["--quote", request.quote]
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let errors = Pipe()
        let output = Pipe()
        process.standardError = errors
        process.standardOutput = output
        try process.run()
        let refused = errors.fileHandleForReading.readDataToEndOfFile()
        let printed = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == .zero else {
            let stated = String(decoding: refused, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let onStdout = String(decoding: printed, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.refused(stated.isEmpty ? onStdout : stated)
        }
    }

    /// The binary sealed into this build's hook release, the same one the
    /// backend runs. A debug build may point at a workspace binary.
    static func executableURL() throws -> URL {
        let manager = FileManager.default
#if DEBUG
        if let override = ProcessInfo.processInfo.environment["TAMA_CLI"], !override.isEmpty {
            let url = URL(fileURLWithPath: override).standardizedFileURL
            guard manager.isExecutableFile(atPath: url.path) else {
                throw Failure.cliMissing(url.path)
            }
            return url
        }
#endif
        guard let resources = Bundle.main.resourceURL else {
            throw Failure.cliMissing("Tama.app/Contents/Resources")
        }
        let bundled = resources
            .appendingPathComponent("hooks-release", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("tama-cli")
        guard manager.isExecutableFile(atPath: bundled.path) else {
            throw Failure.cliMissing(bundled.path)
        }
        return bundled
    }
}
