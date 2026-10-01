import SwiftUI
import WisentDesignSystem

/// Tama Desktop's side of `tama tests audit`: how much test code each
/// repository under a root carries, how much of it is approved, and Remove,
/// which deletes every unapproved test file after a confirmation. A test
/// module inside a source file is listed, never deleted, as the command does.
struct TestAuditPanel: View {
    @State private var root = ""
    @State private var audit: TestAudit?
    @State private var busy = false
    @State private var failure: String?
    @State private var confirmingRemoval = false

    var body: some View {
        WisentPanel {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                Text("Audit test code").font(WisentTypeScale.body()).bold()
                TextField("A repository, or a directory whose children are repositories", text: $root)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Root to audit for test code")
                HStack {
                    Button(busy ? "Reading…" : "Audit") { Task { await run(remove: false) } }
                        .disabled(busy || root.isEmpty)
                    Button("Remove unapproved test files", role: .destructive) { confirmingRemoval = true }
                        .disabled(busy || root.isEmpty)
                }
                if let failure { WisentAlertPanel(tone: .danger, title: "Refused", detail: failure) }
                if let audit { result(audit) }
            }
        }
        .confirmationDialog("Remove every unapproved test file?", isPresented: $confirmingRemoval) {
            Button("Remove", role: .destructive) { Task { await run(remove: true) } }
        } message: {
            Text("Each test file under \(root) that no approval covers is deleted. Test modules inside source files are only listed.")
        }
    }

    private func result(_ audit: TestAudit) -> some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
            Text("\(audit.approved) approved, \(audit.unapproved) unapproved across \(audit.repositoriesRead) repositories; \(audit.remaining) still on disk")
            ForEach(audit.failures, id: \.self) { failure in
                Text(failure).foregroundStyle(WisentDesign.danger)
            }
            ForEach(audit.repositories.filter { $0.testCode > 0 }) { repository in
                VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                    Text("\(repository.repository): \(repository.testCode) test code path(s), \(repository.approved.count) approved")
                        .bold()
                    ForEach(repository.unapprovedFiles, id: \.self) { file in
                        Text("\(repository.filesRemoved ? "removed" : "unapproved file") \(file)")
                    }
                    ForEach(repository.unapprovedInline, id: \.self) { file in
                        Text("unapproved test module inside \(file)")
                    }
                }
            }
        }
        .font(WisentTypeScale.caption())
        .textSelection(.enabled)
    }

    @MainActor private func run(remove: Bool) async {
        busy = true
        failure = nil
        defer { busy = false }
        do {
            audit = try await TestApprovalClient().audit(roots: [root], remove: remove)
        } catch { failure = error.localizedDescription }
    }
}
