import SwiftUI
import WisentDesignSystem

/// The same cross-session proposals `tama rules digest` prints, including
/// source-backed lessons from Oko's unresolved operator corrections.
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
                        detail: "Corrections and hook decisions across sessions, including causes not yet named.")
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
                if proposal.sources == nil, let quote = proposal.quote {
                    Text("“\(quote)”").textSelection(.enabled)
                }
                Text("\(counted(Int(proposal.evidence), "piece")) of evidence, \(proposal.first ?? "?") – \(proposal.last ?? "?")")
                Text(proposal.action).font(WisentTypeScale.identifierSmall()).textSelection(.enabled)
                if let sources = proposal.sources {
                    DisclosureGroup("Read \(counted(sources.count, "source"))") {
                        VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                            ForEach(sources) { source in
                                VStack(alignment: .leading) {
                                    Text("Session \(source.session)").font(WisentTypeScale.identifierSmall())
                                    Text("“\(source.quote)”").textSelection(.enabled)
                                    Text(source.cause.map { "Cause: \($0)" } ?? "Cause not yet named")
                                        .textSelection(.enabled)
                                    if let defect = source.defect {
                                        Text("Defect: \(defect)").textSelection(.enabled)
                                    }
                                    if let markers = source.markers, !markers.isEmpty {
                                        Text("Read as: \(markers.joined(separator: "; "))")
                                    }
                                    if let repeats = source.repeats, repeats > 0 {
                                        Text("Earlier repeats: \(repeats)")
                                    }
                                }
                            }
                        }
                    }
                }
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
        } catch {
            digest = nil
            failure = error.localizedDescription
        }
    }

    @MainActor private func dismiss(_ proposal: LearningProposal) async {
        busy = true
        failure = nil
        notice = nil
        defer { busy = false }
        do {
            notice = try await LearningClient().dismiss(proposal).detail
            digest = try await LearningClient().digest()
        } catch {
            digest = nil
            failure = error.localizedDescription
        }
    }
}
