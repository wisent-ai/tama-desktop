import AppKit
import SwiftUI
import WisentDesignSystem

/// What `attestation/pending` answers: every commit a checkout's branch
/// carries over its upstream, as `review-push` will read it, with the
/// commits of that range each one patches.
struct PendingReport: Decodable, Sendable {
    struct Patched: Decodable, Sendable {
        let commit: String
        let subject: String
    }
    struct Commit: Decodable, Sendable {
        let commit: String
        let subject: String
        let stands: Bool
        let carriedIn: String?
        let missing: [String]
        let findings: [String]
        let patches: [Patched]
        /// Why the commits it patches could not be measured, such as a
        /// malformed `Repairs:` line; the commit does not stand while it is set.
        let patchesFailure: String?

        /// Whether the commit stands and where, as Tama answered it.
        var standing: String {
            switch (stands, carriedIn) {
            case (true, let place?): return "Stands in its \(place)"
            case (true, nil): return "Tama answered that it stands and named no place it is carried"
            case (false, _): return "Does not stand"
            }
        }

        /// The lines the gate would name for this commit.
        var lines: [String] {
            missing.map { "missing: \"\($0)\"" } + findings.map { "finding: \"\($0)\"" }
                + patches.map { "patches: \($0.commit) \($0.subject)" }
                + [patchesFailure].compactMap { $0 }.map { "patches unread: \($0)" }
        }
    }
    let repository: String
    let upstream: String
    let stands: Bool
    let commits: [Commit]
}

/// `tama attestation pending --repository PATH` as a request, so the screen
/// shows what the terminal prints and a refusal carries Tama's sentence.
@MainActor
final class PendingCommitsModel: ObservableObject {
    @Published private(set) var working: String?
    @Published private(set) var failure: String?
    @Published private(set) var report: PendingReport?
    @Published var repository: URL?

    private static let operation = "The unpushed commits"

    func read() {
        guard let repository else {
            failure = "Choose the checkout whose unpushed commits to read."
            return
        }
        guard working == nil else { return }
        working = "Reading the unpushed commits"
        failure = nil
        let fields: [String: Any] = ["repository": repository.path]
        Task {
            do {
                report = try await TamaClient().request(
                    "attestation/pending", body: fields, as: PendingReport.self,
                    describing: Self.operation)
            } catch let error as LocalizedError {
                failure = error.errorDescription
            } catch {
                failure = error.localizedDescription
            }
            working = nil
        }
    }
}

/// Every commit a branch would push, read before the push: whether each
/// attestation stands, what it lacks or names, and which commit of the same
/// push it patches, the pair `review-push` refuses until it is folded.
struct PendingCommitsSection: View {
    @StateObject private var model = PendingCommitsModel()

    var body: some View {
        WisentSectionBox(
            title: "Unpushed commits",
            detail:
                "What review-push will read: each commit over the upstream, its attestation, and the commits of the same push it patches."
        ) {
            if let working = model.working { WisentSkeletonText(label: working) }
            if let failure = model.failure {
                WisentAlertPanel(tone: .danger, title: "Tama refused", detail: failure)
            }
            HStack(spacing: WisentDesign.Space.x3) {
                Button("Choose checkout…") { chooseRepository() }
                if let repository = model.repository {
                    Text(repository.path)
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(WisentDesign.secondary)
                }
                Button("Read unpushed commits") { model.read() }
            }
            .disabled(model.working != nil)
            if let report = model.report { reportPanel(report) }
        }
    }

    @ViewBuilder
    private func reportPanel(_ report: PendingReport) -> some View {
        WisentAlertPanel(
            tone: report.stands ? .success : .warning,
            title: report.stands
                ? "Every commit over \(report.upstream) stands"
                : "Not every commit over \(report.upstream) stands; review-push refuses the push",
            detail: report.repository)
        ForEach(report.commits, id: \.commit) { commit in
            WisentPanel {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                    Text("\(commit.commit) \(commit.subject)")
                        .font(WisentTypeScale.identifierSmall())
                    Text(commit.standing).font(WisentTypeScale.eyebrow())
                    ForEach(commit.lines, id: \.self) { line in
                        Text(line).font(WisentTypeScale.caption()).foregroundStyle(
                            WisentDesign.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func chooseRepository() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            model.repository = panel.url
        }
    }
}
