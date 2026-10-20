import SwiftUI
import WisentDesignSystem

/// The work one session serves, which `block-off-task-work` holds its changes
/// to and `block-unclaimed-calls` admits its calls for: shown, declared and
/// cleared through `tama request task-scope/…`, with the same checks against
/// Oko's registers and the same refusals as `tama task scope show|set|clear`.
struct TaskScopePanel: View {
    let session: String
    @State private var repositories = ""
    @State private var defect = ""
    @State private var task = ""
    @State private var shown: TaskScopeShown?
    @State private var busy = false
    @State private var failure: String?
    @State private var notice: String?
    @State private var colleague: String?

    var body: some View {
        WisentPanel {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                Text("Task scope").font(WisentTypeScale.body()).bold()
                if let shown { declared(shown) }
                if let failure {
                    WisentAlertPanel(tone: .danger, title: "Refused", detail: failure)
                }
                if let notice {
                    WisentAlertPanel(tone: .info, title: "Done", detail: notice)
                }
                if let colleague {
                    WisentAlertPanel(tone: .info, title: "Also declared", detail: colleague)
                }
                form
            }
        }
        .task(id: session) { await show() }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
            TextField("Oko defect ID", text: $defect)
                .accessibilityLabel("Oko defect ID")
            TextField("Oko task ID", text: $task)
                .accessibilityLabel("Oko task ID")
            TextField(
                "Repositories the work changes, one per line (none: the task contract's list)",
                text: $repositories, axis: .vertical
            )
            .accessibilityLabel("Repositories")
            Text(
                "The defect must be open in Oko's register and the task known to it; the declaration is bound to the session's newest operator instruction, so a later instruction leaves it serving nothing."
            )
            .font(WisentTypeScale.caption()).foregroundStyle(WisentDesign.secondary)
            HStack {
                Button(busy ? "Declaring…" : "Declare") { Task { await declare() } }
                    .disabled(busy)
                Button("Clear", role: .destructive) { Task { await clear() } }
                    .disabled(busy || shown?.scope == nil)
                Button("Refresh") { Task { await show() } }.disabled(busy)
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    @ViewBuilder
    private func declared(_ shown: TaskScopeShown) -> some View {
        if let scope = shown.scope {
            WisentField(label: "Working", value: scope.entry)
            WisentField(label: "Touches", value: scope.repositories.joined(separator: ", "))
            Text(scope.task).font(WisentTypeScale.caption()).textSelection(.enabled)
            switch scope.servesCurrentInstruction {
            case true?:
                Text("Declared for the instruction being served.")
                    .font(WisentTypeScale.caption())
            case false?:
                Text("The operator has spoken since; declare the scope of the new instruction.")
                    .font(WisentTypeScale.caption())
            case nil:
                Text("Declared just now for the newest instruction.")
                    .font(WisentTypeScale.caption())
            }
        } else {
            Text("This session has declared no task scope.").font(WisentTypeScale.caption())
        }
    }

    private func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
    }

    @MainActor private func begin() {
        busy = true
        failure = nil
        notice = nil
        colleague = nil
    }

    @MainActor private func show() async {
        begin()
        defer { busy = false }
        do {
            shown = try await TaskScopeClient().show(session: session)
        } catch { failure = error.localizedDescription }
    }

    @MainActor private func declare() async {
        begin()
        defer { busy = false }
        do {
            let result = try await TaskScopeClient().set(
                session: session, repositories: lines(repositories),
                defect: trimmed(defect), task: trimmed(task))
            shown = TaskScopeShown(session: result.session, scope: result.scope)
            notice =
                "\(result.scope.entry) in \(result.scope.repositories.joined(separator: ", "))."
            colleague = result.notice
        } catch { failure = error.localizedDescription }
    }

    @MainActor private func clear() async {
        begin()
        defer { busy = false }
        do {
            let result = try await TaskScopeClient().clear(session: session)
            shown = TaskScopeShown(session: result.session, scope: nil)
            notice =
                result.cleared ? "The task scope is cleared." : "The session had no task scope."
        } catch { failure = error.localizedDescription }
    }
}
