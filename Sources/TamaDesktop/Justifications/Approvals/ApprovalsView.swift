import SwiftUI
import WisentDesignSystem

/// Tama Desktop's side of `tama tests`: the paths the operator approved test
/// code under, a form to approve another, and Revoke on each. The app runs
/// outside any agent session, so this is the operator's own approval, as the
/// terminal command is; `block-unapproved-tests` refuses test code anywhere
/// else.
struct TestApprovalsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var listing: TestApprovalListing?
    @State private var path = ""
    @State private var busy = false
    @State private var failure: String?
    @State private var notice: String?
    @State private var revoking: TestApproval?

    var body: some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
            HStack {
                WisentSectionHeader("Test approvals", detail: "Test code is written only under a path approved here.")
                Spacer()
                Button("Close") { dismiss() }.disabled(busy)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
                    form
                    if let failure { WisentAlertPanel(tone: .danger, title: "Refused", detail: failure) }
                    if let notice { WisentAlertPanel(tone: .info, title: "Saved", detail: notice) }
                    HStack {
                        Text("Approved paths").font(WisentTypeScale.body()).bold()
                        Spacer()
                        Button("Refresh") { Task { await refresh() } }.disabled(busy)
                    }
                    if let listing {
                        Text(listing.record).font(WisentTypeScale.identifierSmall()).textSelection(.enabled)
                        if listing.approved.isEmpty { Text("No test code is approved.") }
                        ForEach(listing.approved) { approval in row(approval) }
                    }
                    TestAuditPanel()
                }
            }
        }
        .padding(WisentDesign.Space.x5)
        .frame(minWidth: WisentAppLayout.inspectorWidth)
        .task { await refresh() }
        .confirmationDialog("Revoke this approval?", isPresented: Binding(
            get: { revoking != nil }, set: { if !$0 { revoking = nil } }
        ), presenting: revoking) { approval in
            Button("Revoke", role: .destructive) {
                Task { await revoke(approval) }
            }
        } message: { approval in
            Text("Test code under \(approval.path) is refused again after this.")
        }
    }

    private var form: some View {
        WisentPanel {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                TextField("Absolute path of a test file or directory", text: $path)
                    .accessibilityLabel("Path to approve for test code")
                Text("An approved directory covers everything below it. Approve only a test you asked for.")
                    .font(WisentTypeScale.caption()).foregroundStyle(WisentDesign.secondary)
                Button(busy ? "Approving…" : "Approve") { Task { await approve() } }
                    .disabled(busy)
            }
            .textFieldStyle(.roundedBorder)
        }
    }

    private func row(_ approval: TestApproval) -> some View {
        WisentPanel {
            HStack {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                    Text(approval.path).textSelection(.enabled)
                    Text("Approved \(approval.approvedAt)").foregroundStyle(WisentDesign.secondary)
                }
                Spacer()
                Button("Revoke", role: .destructive) { revoking = approval }.disabled(busy)
            }
            .font(WisentTypeScale.caption())
        }
    }

    @MainActor private func refresh() async {
        busy = true
        defer { busy = false }
        do {
            listing = try await TestApprovalClient().list()
            failure = nil
        } catch { failure = error.localizedDescription }
    }

    @MainActor private func approve() async {
        busy = true
        failure = nil
        notice = nil
        defer { busy = false }
        do {
            let result = try await TestApprovalClient().approve(paths: [path])
            listing = TestApprovalListing(approved: result.approved, record: result.record)
            notice = "Approved \(result.changed.joined(separator: ", "))."
            path = ""
        } catch { failure = error.localizedDescription }
    }

    @MainActor private func revoke(_ approval: TestApproval) async {
        busy = true
        failure = nil
        notice = nil
        defer { busy = false }
        do {
            let result = try await TestApprovalClient().revoke(paths: [approval.path])
            listing = TestApprovalListing(approved: result.approved, record: result.record)
            notice = "Revoked \(result.changed.joined(separator: ", "))."
        } catch { failure = error.localizedDescription }
    }
}
