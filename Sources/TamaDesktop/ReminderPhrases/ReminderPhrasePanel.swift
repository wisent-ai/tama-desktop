import SwiftUI
import WisentDesignSystem

/// The operator's reminder phrases, which `remind-open-work` puts after
/// every tool result and `block-missing-reminder-phrase` demands in the
/// agent's own text: listed, added and removed through
/// `tama request reminder-phrase/…`, with the same checks against Oko's
/// registers and the same refusals as
/// `tama reminder-phrase list|add|remove`.
struct ReminderPhrasePanel: View {
    let session: String
    @State private var sentence = ""
    @State private var defect = ""
    @State private var listed: ReminderPhrases?
    @State private var busy = false
    @State private var failure: String?
    @State private var notice: String?

    var body: some View {
        WisentPanel {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                Text("Reminder phrases").font(WisentTypeScale.body()).bold()
                if let listed {
                    entries(listed)
                }
                if let failure {
                    WisentAlertPanel(tone: .danger, title: "Refused", detail: failure)
                }
                if let notice {
                    WisentAlertPanel(tone: .info, title: "Done", detail: notice)
                }
                form
            }
        }
        .task { await list() }
    }

    @ViewBuilder
    private func entries(_ listed: ReminderPhrases) -> some View {
        if listed.entries.isEmpty {
            Text("No reminder phrase is set.")
                .font(WisentTypeScale.caption())
        } else {
            ForEach(listed.entries) { entry in
                VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                    Text(entry.sentence).font(WisentTypeScale.caption()).textSelection(.enabled)
                    HStack {
                        Text("\(entry.id) · \(entry.scope)")
                            .font(WisentTypeScale.caption())
                            .foregroundStyle(WisentDesign.secondary)
                        if let defect = entry.defect {
                            Text("defect \(defect)")
                                .font(WisentTypeScale.caption())
                                .foregroundStyle(WisentDesign.secondary)
                        }
                        Spacer()
                        Text(entry.applies ? "applies" : "repaired: no longer applies")
                            .font(WisentTypeScale.caption())
                            .foregroundStyle(entry.applies ? nil : WisentDesign.secondary)
                        Button("Remove") { Task { await remove(entry) } }.disabled(busy)
                    }
                }
            }
        }
        if let unread = listed.unread {
            Text(
                "Oko's open-defect register could not be read, so every phrase applies: \(unread)"
            )
            .font(WisentTypeScale.caption())
            .foregroundStyle(WisentDesign.secondary)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
            TextField("The sentence, exactly as the agent must write it", text: $sentence, axis: .vertical)
                .accessibilityLabel("The sentence")
            TextField("Oko defect ID it is bound to", text: $defect)
                .accessibilityLabel("Oko defect ID")
            Text(
                "The defect must be open in Oko's register; the phrase stops applying by itself when it is repaired. Leave the session field to add the phrase for the whole machine."
            )
            .font(WisentTypeScale.caption()).foregroundStyle(WisentDesign.secondary)
            HStack {
                Button(busy ? "Adding…" : "Add for this session") { Task { await add(sessionOnly: true) } }
                    .disabled(busy || trimmed(sentence).isEmpty)
                Button("Add for the machine") { Task { await add(sessionOnly: false) } }
                    .disabled(busy || trimmed(sentence).isEmpty)
                Button("Refresh") { Task { await list() } }.disabled(busy)
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    @MainActor private func begin() {
        busy = true
        failure = nil
        notice = nil
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
    }

    @MainActor private func list() async {
        begin()
        defer { busy = false }
        do {
            listed = try await ReminderPhraseClient().list()
        } catch { failure = error.localizedDescription }
    }

    @MainActor private func add(sessionOnly: Bool) async {
        begin()
        defer { busy = false }
        do {
            let added = try await ReminderPhraseClient().add(
                sentence: trimmed(sentence),
                defect: trimmed(defect),
                session: sessionOnly ? session : "")
            notice = "Added \(added.id)."
            sentence = ""
            listed = try await ReminderPhraseClient().list()
        } catch { failure = error.localizedDescription }
    }

    @MainActor private func remove(_ entry: ReminderPhraseEntry) async {
        begin()
        defer { busy = false }
        do {
            let removed = try await ReminderPhraseClient().remove(id: entry.id)
            notice = removed.removed ? "Removed \(entry.id)." : "\(entry.id) was already gone."
            listed = try await ReminderPhraseClient().list()
        } catch { failure = error.localizedDescription }
    }
}
