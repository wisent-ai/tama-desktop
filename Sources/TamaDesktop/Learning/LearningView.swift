import SwiftUI
import WisentDesignSystem

/// What Tama learned across every session, one proposal per hook or drafted
/// rule, with how often it happened and the command that acts on it. The same
/// document `tama rules digest` prints.
struct LearningView: View {
    @State private var digest: LearningDigest?
    @State private var busy = false
    @State private var failure: String?
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
                HStack {
                    WisentSectionHeader("Learned",
                        detail: "Every correction from every session, folded into one proposal per hook or rule.")
                    Spacer()
                    Button(busy ? "Reading…" : "Refresh") { Task { await refresh() } }
                        .disabled(busy).accessibilityIdentifier("tama.learning.refresh")
                }
                if let failure { WisentAlertPanel(tone: .danger, title: "Refused", detail: failure) }
                if let notice { WisentAlertPanel(tone: .info, title: "Dismissed", detail: notice) }
                if let digest {
                    ForEach(digest.unreadable) { source in
                        WisentAlertPanel(tone: .danger, title: "\(source.source) unreadable", detail: source.error)
                    }
                    if digest.proposals.isEmpty {
                        Text("Nothing new to decide. \(counted(digest.dismissed, "dismissed proposal")).")
                    }
                    ForEach(digest.proposals) { proposal in row(proposal) }
                }
            }
            .padding(WisentDesign.Space.x5)
        }
        .task { await refresh() }
    }

    private func row(_ proposal: LearningProposal) -> some View {
        WisentPanel {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                Text(proposal.subject).font(WisentTypeScale.body()).bold()
                if let says = proposal.says { Text(says) }
                if let quote = proposal.quote { Text("“\(quote)”").textSelection(.enabled) }
                Text("\(counted(Int(proposal.evidence), "piece")) of evidence, \(proposal.first ?? "?") – \(proposal.last ?? "?")")
                Text(proposal.action).font(WisentTypeScale.identifierSmall()).textSelection(.enabled)
                Button("Dismiss until new evidence") { Task { await dismiss(proposal) } }
                    .disabled(busy).accessibilityIdentifier("tama.learning.dismiss.\(proposal.id)")
            }
            .font(WisentTypeScale.caption())
        }
    }

    @MainActor private func refresh() async {
        busy = true
        defer { busy = false }
        do {
            digest = try await LearningClient().digest()
            failure = nil
        } catch { failure = error.localizedDescription }
    }

    @MainActor private func dismiss(_ proposal: LearningProposal) async {
        busy = true
        failure = nil
        notice = nil
        defer { busy = false }
        do {
            notice = try await LearningClient().dismiss(proposal).detail
            digest = try await LearningClient().digest()
        } catch { failure = error.localizedDescription }
    }
}
