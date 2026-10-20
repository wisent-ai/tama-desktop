import SwiftUI
import WisentDesignSystem

/// Every agent session's commit standing: a point earned for each commit in
/// rustfmt's form, one lost for each with a Rust file out of it, and below
/// zero every tool call refused by `block-negative-commit-standing`. Commits
/// made before they were scored are charged here, and a charge recorded in
/// error is taken back with its reason, through `tama request standing/…`,
/// with the same checks and refusals as `tama standing list|score|withdraw`.
struct StandingView: View {
    @State private var sessions: [SessionStanding]?
    @State private var repository = ""
    @State private var range = ""
    @State private var scored: [ScoredCommit]?
    @State private var reasons: [String: String] = [:]
    @State private var busy = false
    @State private var failure: String?
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
                HStack {
                    WisentSectionHeader(
                        "Commit standing",
                        detail:
                            "A session that commits more unformatted Rust than formatted has every tool call refused."
                    )
                    Spacer()
                    Button("Refresh") { Task { await refresh() } }.disabled(busy)
                        .accessibilityIdentifier("tama.standing.refresh")
                }
                if let failure {
                    WisentAlertPanel(tone: .danger, title: "Refused", detail: failure)
                }
                if let notice { WisentAlertPanel(tone: .info, title: "Recorded", detail: notice) }
                scoreForm
                if let scored { scoredList(scored) }
                if let sessions {
                    if sessions.isEmpty {
                        WisentEmptyPanel(
                            title: "No commit scored",
                            detail: "No agent session's commit is recorded in the register yet.",
                            symbol: "checkmark.seal")
                    }
                    ForEach(sessions) { session in standing(session) }
                }
            }
            .padding(WisentDesign.Space.x5)
        }
        .task { await refresh() }
    }

    private var scoreForm: some View {
        WisentPanel {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                Text("Score commits made before they were scored").font(WisentTypeScale.body())
                    .bold()
                TextField("Repository path", text: $repository)
                    .accessibilityIdentifier("tama.standing.repository")
                TextField("Revision range, as Git reads it", text: $range)
                    .accessibilityIdentifier("tama.standing.range")
                Text(
                    "Each commit goes to the session whose commit call was running when Git recorded it, read from the session transcripts; a commit no call or several calls cover is listed with that cause and not scored."
                )
                .font(WisentTypeScale.caption()).foregroundStyle(WisentDesign.secondary)
                Button(busy ? "Scoring…" : "Score") { Task { await score() } }
                    .disabled(busy).accessibilityIdentifier("tama.standing.score")
            }
            .textFieldStyle(.roundedBorder)
        }
    }

    private func scoredList(_ scored: [ScoredCommit]) -> some View {
        WisentPanel {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                Text("\(scored.count) commit(s) read").font(WisentTypeScale.body()).bold()
                ForEach(scored) { entry in
                    Text("\(entry.commit) \(entry.subject)").textSelection(.enabled)
                    Text(outcome(entry)).foregroundStyle(WisentDesign.secondary)
                }
            }
            .font(WisentTypeScale.caption())
        }
    }

    private func outcome(_ entry: ScoredCommit) -> String {
        switch (entry.session, entry.cause) {
        case (_, let cause?): "Not scored: \(cause)"
        case (let session?, nil) where entry.unformatted.isEmpty: "\(session) earned a point"
        case (let session?, nil):
            "\(session) lost a point: \(entry.unformatted.joined(separator: ", "))"
        case (nil, nil): "Not scored: no session was found for it"
        }
    }

    private func standing(_ session: SessionStanding) -> some View {
        WisentPanel {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                Text("\(session.session) — \(session.blocked ? "blocked" : "free")")
                    .font(WisentTypeScale.body()).bold().textSelection(.enabled)
                Text(session.rule)
                ForEach(session.charges) { charge in
                    Text(
                        "Charge \(charge.id) in \(charge.repository), \(charge.recordedAt): \(charge.unformatted.joined(separator: ", "))"
                    )
                    .textSelection(.enabled)
                    HStack {
                        TextField(
                            "Why this charge was recorded in error",
                            text: Binding(
                                get: { reasons[charge.id, default: ""] },
                                set: { reasons[charge.id] = $0 })
                        )
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("tama.standing.reason.\(charge.id)")
                        Button("Take back") { Task { await withdraw(charge) } }
                            .disabled(busy)
                            .accessibilityIdentifier("tama.standing.withdraw.\(charge.id)")
                    }
                }
            }
            .font(WisentTypeScale.caption())
        }
    }

    @MainActor private func refresh() async {
        busy = true
        defer { busy = false }
        do {
            sessions = try await StandingClient().list()
            failure = nil
        } catch { failure = error.localizedDescription }
    }

    @MainActor private func score() async {
        busy = true
        failure = nil
        notice = nil
        defer { busy = false }
        do {
            let entries = try await StandingClient().score(repository: repository, range: range)
            scored = entries
            let recorded = entries.filter(\.recorded).count
            notice = "\(recorded) of \(entries.count) commit(s) were scored."
            sessions = try await StandingClient().list()
        } catch { failure = error.localizedDescription }
    }

    @MainActor private func withdraw(_ charge: StandingCommit) async {
        busy = true
        failure = nil
        notice = nil
        defer { busy = false }
        do {
            let taken = try await StandingClient().withdraw(
                charge: charge.id, reason: reasons[charge.id, default: ""])
            notice =
                "Charge \(taken.withdrawn.commit.id) of \(taken.standing.session) was taken back; its standing is \(taken.standing.standing)."
            reasons[charge.id] = nil
            sessions = try await StandingClient().list()
        } catch { failure = error.localizedDescription }
    }
}
