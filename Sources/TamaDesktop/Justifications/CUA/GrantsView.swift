import SwiftUI
import WisentDesignSystem

struct CUAGrantsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var listing: CUAListing?
    @State private var session = ""
    @State private var app = ""
    @State private var actions = ""
    @State private var quote = ""
    @State private var match = true
    @State private var busy = false
    @State private var failure: String?
    @State private var notice: String?
    @State private var removing: CUAGrant?

    var body: some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
            HStack {
                WisentSectionHeader("CUA consent", detail: "Record a grant already spoken in an OMP session.")
                Spacer()
                Button("Close") { dismiss() }.disabled(busy)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
                    form
                    if let failure { WisentAlertPanel(tone: .danger, title: "Refused", detail: failure) }
                    if let notice { WisentAlertPanel(tone: .info, title: "Recorded", detail: notice) }
                    HStack {
                        Text("Recorded grants").font(WisentTypeScale.body()).bold()
                        Spacer()
                        Button("Refresh") { Task { await refresh() } }.disabled(busy)
                    }
                    if let listing {
                        Text(listing.registry).font(WisentTypeScale.identifierSmall()).textSelection(.enabled)
                        if listing.authorizations.isEmpty { Text("No CUA grants recorded.") }
                        ForEach(listing.authorizations) { grant in record(grant) }
                    }
                }
            }
        }
        .padding(WisentDesign.Space.x5)
        .frame(minWidth: WisentAppLayout.inspectorWidth)
        .task { await refresh() }
        .confirmationDialog("Remove this recorded consent?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }
        ), presenting: removing) { grant in
            Button("Remove consent", role: .destructive) {
                Task { await remove(grant) }
            }
        } message: { grant in
            Text("Remove every grant with this exact quote: \(grant.userRequestQuote)")
        }
    }

    private var form: some View {
        WisentPanel {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                TextField("OMP session ID", text: $session)
                    .accessibilityLabel("OMP session ID")
                TextField("Installed application name", text: $app)
                    .accessibilityLabel("Installed application name")
                TextField("Actions, separated by commas", text: $actions, axis: .vertical)
                    .accessibilityLabel("Allowed CUA actions")
                Toggle("Find the original user message from matching text", isOn: $match)
                TextField(match ? "Text found in exactly one user message" : "Verbatim user consent",
                    text: $quote, axis: .vertical)
                    .accessibilityLabel(match ? "User message match" : "Verbatim user consent")
                Text("The message must name CUA, the application and every requested action. Recording does not start the driver or prove that an action ran.")
                    .font(WisentTypeScale.caption()).foregroundStyle(WisentDesign.secondary)
                Button(busy ? "Recording…" : "Record consent") { Task { await save() } }
                    .disabled(busy)
            }
            .textFieldStyle(.roundedBorder)
        }
    }

    private func record(_ grant: CUAGrant) -> some View {
        WisentPanel {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                HStack {
                    Text(grant.allowedAppName).font(WisentTypeScale.body()).bold()
                    Spacer()
                    Button("Remove", role: .destructive) { removing = grant }.disabled(busy)
                }
                Text(grant.allowedActions.joined(separator: ", "))
                Text(grant.userRequestQuote).textSelection(.enabled)
                Text("Session: \(grant.sessionId ?? "Checked by the hook at use")")
                Text(grant.lifetime)
                Text(grant.allowedBundleId).textSelection(.enabled)
                Text(grant.allowedExecutable).textSelection(.enabled)
            }
            .font(WisentTypeScale.caption())
        }
    }

    @MainActor private func refresh() async {
        busy = true
        defer { busy = false }
        do {
            listing = try await CUAConsentClient().list()
            failure = nil
        } catch { failure = error.localizedDescription }
    }

    @MainActor private func save() async {
        busy = true
        failure = nil
        notice = nil
        defer { busy = false }
        do {
            let result = try await CUAConsentClient().record(session: session, app: app,
                actions: actions.split(separator: ",", omittingEmptySubsequences: false).map(String.init),
                quote: quote, match: match)
            listing = try await CUAConsentClient().list()
            notice = "\(result.authorization.allowedAppName): the original user grant is recorded. The hook checks the current session, action and target on each use."
        } catch { failure = error.localizedDescription }
    }

    @MainActor private func remove(_ grant: CUAGrant) async {
        busy = true
        failure = nil
        notice = nil
        defer { busy = false }
        do {
            _ = try await CUAConsentClient().remove(quote: grant.userRequestQuote)
            listing = try await CUAConsentClient().list()
        } catch { failure = error.localizedDescription }
    }
}
