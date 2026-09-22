import SwiftUI
import WisentDesignSystem

struct BuildsView: View {
    @State private var listing: BuildListing?
    @State private var target = ""
    @State private var revision = ""
    @State private var reason = ""
    @State private var repository = ""
    @State private var hasConsent = false
    @State private var session = ""
    @State private var quote = ""
    @State private var busy = false
    @State private var failure: String?
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
                HStack {
                    WisentSectionHeader("Build registry", detail: "Record a build and the user's permission to exceed the daily limit.")
                    Spacer()
                    Button("Refresh") { Task { await refresh() } }.disabled(busy)
                }
                form
                if let failure { WisentAlertPanel(tone: .danger, title: "Refused", detail: failure) }
                if let notice { WisentAlertPanel(tone: .info, title: "Recorded", detail: notice) }
                if let listing {
                    Text(listing.registry).font(WisentTypeScale.identifierSmall()).textSelection(.enabled)
                    ForEach(listing.ration) { allowance in
                        Text("\(allowance.kind): \(allowance.spent) intents recorded in 24 hours; local limit \(allowance.allowed).")
                    }
                    Text("Current entries").font(WisentTypeScale.body()).bold()
                    if listing.entries.isEmpty { Text("No open registry entries.") }
                    ForEach(listing.entries) { row in
                        intent(row.entry, status: row.open ? "Open" : "Expired")
                        Button("Close \(row.entry.target)") { Task { await close(row.entry) } }
                            .disabled(busy).accessibilityIdentifier("tama.build.close.\(row.key)")
                    }
                    Text("User approval history").font(WisentTypeScale.body()).bold()
                    Text("Closing or expiring an entry does not erase its approval or allow the same message to be used again for this product.")
                        .font(WisentTypeScale.caption())
                    ForEach(listing.approvalHistory) { entry in intent(entry, status: "Recorded approval") }
                }
            }
            .padding(WisentDesign.Space.x5)
        }
        .task { await refresh() }
    }

    private var form: some View {
        WisentPanel {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                TextField("Product", text: $target).accessibilityIdentifier("tama.build.target")
                TextField("Full source revision", text: $revision).accessibilityIdentifier("tama.build.revision")
                TextField("Repository path", text: $repository).accessibilityIdentifier("tama.build.repository")
                TextField("Reason for this build", text: $reason, axis: .vertical)
                Toggle("Use recorded user consent for a daily-limit exception", isOn: $hasConsent)
                    .accessibilityIdentifier("tama.build.use-consent")
                if hasConsent {
                    TextField("Session ID", text: $session).accessibilityIdentifier("tama.build.session")
                    TextField("Verbatim current user message", text: $quote, axis: .vertical)
                        .accessibilityIdentifier("tama.build.quote")
                    Text("Tama checks the captured message and its meaning through Brama. A request to add an approval mechanism is not permission to exceed the limit. The default limit, change-size checks and expiry stay unchanged.")
                        .font(WisentTypeScale.caption()).foregroundStyle(WisentDesign.secondary)
                }
                Button(busy ? "Recording…" : "Record build") { Task { await save() } }
                    .disabled(busy).accessibilityIdentifier("tama.build.record")
            }
            .textFieldStyle(.roundedBorder)
        }
    }

    private func intent(_ entry: BuildIntent, status: String) -> some View {
        WisentPanel {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                Text("\(entry.target) — \(status)").font(WisentTypeScale.body()).bold()
                Text(entry.reason)
                if let revision = entry.revision { Text(revision).textSelection(.enabled) }
                Text("Expires: \(Date(timeIntervalSince1970: TimeInterval(entry.expiresAt)).formatted())")
                if let approval = entry.userApproval {
                    Text("User-approved daily-limit exception").bold()
                    Text(approval.quote).textSelection(.enabled)
                    Text("Session: \(approval.sessionID)").textSelection(.enabled)
                    Text("Message: \(approval.turnDigest)").textSelection(.enabled)
                    Text("Captured at epoch: \(approval.capturedAt)")
                }
            }
            .font(WisentTypeScale.caption())
        }
    }

    @MainActor private func refresh() async {
        busy = true
        defer { busy = false }
        do {
            listing = try await BuildRegistryClient().list()
            failure = nil
        } catch { failure = error.localizedDescription }
    }

    @MainActor private func close(_ entry: BuildIntent) async {
        busy = true
        failure = nil
        notice = nil
        defer { busy = false }
        do {
            let result = try await BuildRegistryClient().close(kind: entry.kind, target: entry.target)
            listing = try await BuildRegistryClient().list()
            notice = "\(result.closed) is closed. Its approval remains in the audit history. Already accepted jobs are not cancelled."
        } catch { failure = error.localizedDescription }
    }

    @MainActor private func save() async {
        busy = true
        failure = nil
        notice = nil
        defer { busy = false }
        do {
            let result = try await BuildRegistryClient().record(target: target, revision: revision,
                reason: reason, repository: repository, session: hasConsent ? session : nil,
                quote: hasConsent ? quote : nil)
            listing = try await BuildRegistryClient().list()
            notice = "\(result.entry.target): the intent and any verified consent are recorded. No build has been started by this action."
        } catch { failure = error.localizedDescription }
    }
}
