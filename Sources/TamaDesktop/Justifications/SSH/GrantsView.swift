import SwiftUI
import WisentDesignSystem

/// Record, inspect and remove an SSH grant `block-unauthorized-ssh` reads,
/// through `tama request justifications/ssh*`: the same fields, refusals
/// and registry as `tama justify --kind ssh`.
struct SSHGrantsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var listing: SSHListing?
    @State private var session = ""
    @State private var targets = ""
    @State private var operation = ""
    @State private var paths = ""
    @State private var commands = ""
    @State private var quote = ""
    @State private var match = true
    @State private var busy = false
    @State private var failure: String?
    @State private var notice: String?
    @State private var removing: SSHGrant?

    var body: some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
            HStack {
                WisentSectionHeader(
                    "SSH consent", detail: "Record a grant already spoken in an OMP session.")
                Spacer()
                Button("Close") { dismiss() }.disabled(busy)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
                    form
                    if let failure {
                        WisentAlertPanel(tone: .danger, title: "Refused", detail: failure)
                    }
                    if let notice {
                        WisentAlertPanel(tone: .info, title: "Recorded", detail: notice)
                    }
                    HStack {
                        Text("Recorded grants").font(WisentTypeScale.body()).bold()
                        Spacer()
                        Button("Refresh") { Task { await refresh() } }.disabled(busy)
                    }
                    if let listing {
                        Text(listing.registry).font(WisentTypeScale.identifierSmall())
                            .textSelection(.enabled)
                        if listing.authorizations.isEmpty { Text("No SSH grants recorded.") }
                        ForEach(listing.authorizations) { grant in record(grant) }
                    }
                }
            }
        }
        .padding(WisentDesign.Space.x5)
        .frame(minWidth: WisentAppLayout.inspectorWidth)
        .task { await refresh() }
        .confirmationDialog(
            "Remove this recorded consent?",
            isPresented: Binding(
                get: { removing != nil }, set: { if !$0 { removing = nil } }
            ), presenting: removing
        ) { grant in
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
                TextField("SSH destinations, one per line", text: $targets, axis: .vertical)
                    .accessibilityLabel("Allowed SSH destinations")
                TextField("Operation: read, write, exec, transfer, tunnel or git", text: $operation)
                    .accessibilityLabel("SSH operation")
                TextField(
                    "Exact ssh:// or sftp:// URLs for read and write, one per line", text: $paths,
                    axis: .vertical
                )
                .accessibilityLabel("Allowed SSH paths")
                TextField(
                    "Exact full commands for exec, transfer, tunnel and git, one per line",
                    text: $commands, axis: .vertical
                )
                .accessibilityLabel("Allowed SSH commands")
                Toggle("Find the original user message from matching text", isOn: $match)
                TextField(
                    match ? "Text found in exactly one user message" : "Verbatim user consent",
                    text: $quote, axis: .vertical
                )
                .accessibilityLabel(match ? "User message match" : "Verbatim user consent")
                Text(
                    "The message must name every destination. Consent itself is the session capability for ssh; recording grants nothing by itself, and the hook reads the capability and the session's transcript on each use."
                )
                .font(WisentTypeScale.caption()).foregroundStyle(WisentDesign.secondary)
                Button(busy ? "Recording…" : "Record consent") { Task { await save() } }
                    .disabled(busy)
            }
            .textFieldStyle(.roundedBorder)
        }
    }

    private func record(_ grant: SSHGrant) -> some View {
        WisentPanel {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                HStack {
                    Text(grant.allowedTargets.joined(separator: ", "))
                        .font(WisentTypeScale.body()).bold()
                    Spacer()
                    Button("Remove", role: .destructive) { removing = grant }.disabled(busy)
                }
                Text(grant.allowedOperations.joined(separator: ", "))
                ForEach(grant.allowedPaths, id: \.self) { path in
                    Text(path).textSelection(.enabled)
                }
                ForEach(grant.allowedCommands, id: \.self) { command in
                    Text(command).textSelection(.enabled)
                }
                Text(grant.userRequestQuote).textSelection(.enabled)
                if let sessionId = grant.sessionId {
                    Text("Session: \(sessionId)")
                } else {
                    Text("Session: checked by the hook at use")
                }
                Text(grant.lifetime)
            }
            .font(WisentTypeScale.caption())
        }
    }

    private func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    @MainActor private func refresh() async {
        busy = true
        defer { busy = false }
        do {
            listing = try await SSHConsentClient().list()
            failure = nil
        } catch { failure = error.localizedDescription }
    }

    @MainActor private func save() async {
        busy = true
        failure = nil
        notice = nil
        defer { busy = false }
        do {
            let result = try await SSHConsentClient().record(
                session: session, targets: lines(targets), operation: operation,
                paths: lines(paths), commands: lines(commands), quote: quote, match: match)
            listing = try await SSHConsentClient().list()
            notice =
                "\(result.authorization.allowedTargets.joined(separator: ", ")): the original user grant is recorded. The hook checks the capability, the session and the exact command or path on each use."
        } catch { failure = error.localizedDescription }
    }

    @MainActor private func remove(_ grant: SSHGrant) async {
        busy = true
        failure = nil
        notice = nil
        defer { busy = false }
        do {
            _ = try await SSHConsentClient().remove(quote: grant.userRequestQuote)
            listing = try await SSHConsentClient().list()
        } catch { failure = error.localizedDescription }
    }
}
