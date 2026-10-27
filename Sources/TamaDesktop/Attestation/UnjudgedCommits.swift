import AppKit
import SwiftUI
import WisentDesignSystem

/// What `attestation/unjudged` answers: the commits HEAD carries that no
/// remote holds, those of them whose attestation does not stand, the most
/// the operator admits, and whether the gates refuse edits and commits there.
struct UnjudgedReport: Decodable, Sendable {
    struct Commit: Decodable, Sendable {
        let commit: String
        let subject: String
        let missing: [String]
        let findings: [String]
    }
    let repository: String
    /// Null while HEAD names no commit yet.
    let unpushed: Int?
    let admitted: Int
    let count: Int
    let stands: Bool
    let commits: [Commit]
}

/// `tama attestation unjudged --repository PATH` as a request, so the screen
/// shows what the terminal prints and a refusal carries Tama's sentence.
@MainActor
final class UnjudgedCommitsModel: ObservableObject, SectionRequests {
    @Published var working: String?
    @Published var failure: String?
    @Published private(set) var report: UnjudgedReport?
    @Published var repository: URL? {
        didSet {
            if repository != oldValue {
                report = nil
                failure = nil
            }
        }
    }

    private let client: TamaClient

    init(command: TamaCommand? = nil) {
        client = TamaClient(command: command)
    }

    private static let operation = "The unjudged commits"

    func read() {
        guard let repository else {
            failure = "Choose the checkout whose unjudged commits to read."
            return
        }
        let fields: [String: Any] = ["repository": repository.path]
        run("Reading the unjudged commits") {
            // A refused read must not leave the previous checkout's report beside it.
            self.report = nil
            do {
                let report = try await self.client.request(
                    "attestation/unjudged", body: fields, as: UnjudgedReport.self,
                    describing: Self.operation)
                guard self.repository == repository else { return }
                self.report = report
            } catch {
                guard self.repository == repository else { return }
                throw error
            }
        }
    }
}

/// The unpushed commits nobody judged against the commit standard, and
/// whether work in the checkout is refused until they stand or are pushed.
struct UnjudgedCommitsSection: View {
    @StateObject private var model = UnjudgedCommitsModel()

    var body: some View {
        WisentSectionBox(
            title: "Unjudged commits",
            detail:
                "Unpushed commits whose attestation does not stand. Over the operator's limit, edits and commits in the checkout are refused."
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
                Button("Read unjudged commits") { model.read() }
            }
            .disabled(model.working != nil)
            if let report = model.report { reportPanel(report) }
        }
    }

    @ViewBuilder
    private func reportPanel(_ report: UnjudgedReport) -> some View {
        if let unpushed = report.unpushed {
            WisentAlertPanel(
                tone: report.stands ? .success : .danger,
                title: report.stands
                    ? "\(report.count) of \(unpushed) unpushed commits unjudged; the operator admits \(report.admitted)"
                    : "\(report.count) of \(unpushed) unpushed commits unjudged, more than the \(report.admitted) the operator admits: edits of files the checkout does not ignore, and commits, are refused",
                detail: report.repository)
        } else {
            WisentAlertPanel(
                tone: .success, title: "HEAD names no commit yet, so nothing is unpushed",
                detail: report.repository)
        }
        ForEach(report.commits, id: \.commit) { commit in
            WisentPanel {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                    Text("\(commit.commit) \(commit.subject)")
                        .font(WisentTypeScale.identifierSmall())
                    ForEach(commit.missing, id: \.self) { line in
                        Text("missing: \(line)").font(WisentTypeScale.caption()).foregroundStyle(
                            WisentDesign.secondary)
                    }
                    ForEach(commit.findings, id: \.self) { line in
                        Text("finding: \(line)").font(WisentTypeScale.caption()).foregroundStyle(
                            WisentDesign.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func chooseRepository() {
        if let directory = chooseDirectory() { model.repository = directory }
    }
}
