import AppKit
import SwiftUI
import WisentDesignSystem

/// The two carried standards as `attestation/required` answers: the claims
/// every commit message carries for review-push, and each stop hook's claims
/// the answer a turn ends with carries.
struct CarriedStandard: Decodable, Sendable {
    struct Commit: Decodable, Sendable { let claims: [String] }
    struct Turn: Decodable, Sendable { let hooks: [String: [String]] }

    let commit: Commit
    let turn: Turn

    /// Each stop hook with its claims, in name order.
    var hooks: [(key: String, value: [String])] {
        turn.hooks.sorted { $0.key < $1.key }
    }
}

/// What one commit message or one answer still lacks, as `attestation/check`
/// answers: the same claims the gate would name in its refusal.
struct CarriedCheck: Decodable, Sendable {
    let kind: String
    let id: String
    let stands: Bool
    let missing: [String]
}

/// `tama attestation standard --commit|--turn` and `tama attestation check`
/// as requests, so the screen shows what the terminal prints and a refusal
/// carries the terminal's sentence. No model is asked by either.
@MainActor
final class CarriedAttestationModel: ObservableObject {
    @Published private(set) var working: String?
    @Published private(set) var failure: String?
    @Published private(set) var standard: CarriedStandard?
    @Published private(set) var check: CarriedCheck?
    @Published var commit = ""
    @Published var repository: URL?
    @Published var hook = ""
    @Published var answer = ""

    private static let operation = "The carried attestations"

    func load() {
        run("Reading the carried standards") {
            self.standard = try await TamaClient().request(
                "attestation/required", as: CarriedStandard.self, describing: Self.operation)
        }
    }

    /// `tama attestation check --commit REV --repository PATH`.
    func checkCommit() {
        let revision = commit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !revision.isEmpty else { return failure = "Name the commit to check." }
        guard let repository else { return failure = "Choose the repository commit \(revision) is in." }
        send(["commit": revision, "repository": repository.path])
    }

    /// `tama attestation check --turn HOOK --file PATH`, with the answer typed here.
    func checkAnswer() {
        guard !hook.isEmpty else { return failure = "Choose the stop hook that reads the answer." }
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return failure = "Write the answer the turn would end with."
        }
        send(["turn": hook, "answer": answer])
    }

    /// The commit standard's claims, one per line, on the clipboard: the
    /// block `tama attestation standard --commit` prints for a message.
    func copyCommitBlock(_ standard: CarriedStandard) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            standard.commit.claims.joined(separator: "\n"), forType: .string)
    }

    private func send(_ body: [String: String]) {
        run("Checking the attestation") {
            let fields: [String: Any] = body
            self.check = try await TamaClient().request(
                "attestation/check", body: fields, as: CarriedCheck.self, describing: Self.operation)
        }
    }

    private func run(_ label: String, _ work: @escaping @MainActor () async throws -> Void) {
        guard working == nil else { return }
        working = label
        failure = nil
        Task {
            do {
                try await work()
            } catch let error as LocalizedError {
                failure = error.errorDescription
            } catch {
                failure = error.localizedDescription
            }
            working = nil
        }
    }
}

/// What review-push and the turn-end stop gates read: the attestation a
/// commit carries in its own message and an answer in its own text, word
/// for word, with no model. The required claims are shown and copied, and a
/// commit or an answer is checked before it is pushed or ended, with the
/// refusal the gate would give.
struct CarriedAttestationSection: View {
    @StateObject private var model = CarriedAttestationModel()

    var body: some View {
        WisentSectionBox(
            title: "Carried attestations",
            detail: "Every pushed commit carries the commit claims in its message; every ending answer carries its stop hooks' claims."
        ) {
            if let working = model.working { WisentSkeletonText(label: working) }
            if let failure = model.failure {
                WisentAlertPanel(tone: .danger, title: "Tama refused", detail: failure)
            }
            if let standard = model.standard {
                standardPanel(standard)
                WisentPanel { form(standard).frame(maxWidth: .infinity, alignment: .leading) }
            }
            if let check = model.check { checkPanel(check) }
        }
        .task { model.load() }
    }

    private func form(_ standard: CarriedStandard) -> some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
            HStack(spacing: WisentDesign.Space.x3) {
                TextField("Commit (read by review-push)", text: $model.commit)
                    .textFieldStyle(.roundedBorder)
                Button("Choose repository…") { chooseRepository() }
                if let repository = model.repository {
                    Text(repository.path)
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(WisentDesign.secondary)
                }
                Button("Check commit") { model.checkCommit() }
            }
            Picker("Stop hook", selection: $model.hook) {
                Text("Choose a hook").tag("")
                ForEach(standard.hooks, id: \.key) { hook in Text(hook.key).tag(hook.key) }
            }
            TextEditor(text: $model.answer)
                .font(WisentTypeScale.caption())
            Button("Check answer") { model.checkAnswer() }
        }
        .disabled(model.working != nil)
    }

    private func standardPanel(_ standard: CarriedStandard) -> some View {
        WisentPanel {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                HStack {
                    Text("Every commit message carries").font(WisentTypeScale.eyebrow())
                    Spacer()
                    Button("Copy block") { model.copyCommitBlock(standard) }
                }
                ForEach(standard.commit.claims, id: \.self) { claim in
                    Text(claim).font(WisentTypeScale.caption()).foregroundStyle(WisentDesign.secondary)
                }
                ForEach(standard.hooks, id: \.key) { hook in
                    Text("An answer ending a turn carries, for \(hook.key)")
                        .font(WisentTypeScale.eyebrow())
                    ForEach(hook.value, id: \.self) { claim in
                        Text(claim).font(WisentTypeScale.caption()).foregroundStyle(WisentDesign.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func checkPanel(_ check: CarriedCheck) -> some View {
        if check.stands {
            WisentAlertPanel(
                tone: .success, title: "\(check.kind) \(check.id) carries every claim",
                detail: "The gate lets it through.")
        } else {
            WisentAlertPanel(
                tone: .warning,
                title: "\(check.kind) \(check.id) does not carry its attestation; the gate refuses it",
                detail: check.missing.map { "missing: \"\($0)\"" }.joined(separator: "\n")
            )
        }
    }

    private func chooseRepository() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            model.repository = panel.url
        }
    }
}
