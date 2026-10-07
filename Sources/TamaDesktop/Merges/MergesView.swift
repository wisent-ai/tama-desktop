import AppKit
import SwiftUI
import WisentDesignSystem

/// Branch merges on `main` under one root since one day, and what each left
/// behind: files over the line limit and paths main had deleted. The screen
/// carries the same capability as `tama merges review` and reads its document;
/// it changes nothing, because repairing a merge is a commit, not a click.
struct MergesView: View {
    @ObservedObject var model: MergesModel

    var body: some View {
        WisentScreen(
            title: "Merges",
            scope: model.root.isEmpty ? nil : model.root,
            freshness: freshness,
            actions: actions,
            scrolls: false,
            constrainsWidth: false
        ) {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                TextField("First day, YYYY-MM-DD", text: $model.since)
                    .textFieldStyle(.roundedBorder)
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var freshness: String {
        switch model.state {
        case .idle: model.root.isEmpty ? "no root selected" : "not reviewed"
        case .reviewing: "reviewing now"
        case .failed: "review refused"
        case .done:
            "\(counted(model.records.count, "merge")) · \(counted(model.damagedCount, "damaged merge"))"
        }
    }

    private var actions: [WisentAction] {
        [
            WisentAction("Choose root…", symbol: "folder.badge.plus", kind: .secondary) {
                chooseRoot()
            },
            WisentAction(
                "Review",
                symbol: "magnifyingglass",
                kind: .primary,
                isEnabled: model.canReview,
                isBusy: model.state == .reviewing
            ) {
                Task { await model.review() }
            },
        ]
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            WisentEmptyPanel(
                title: model.root.isEmpty ? "No root selected" : "Not reviewed",
                detail:
                    "Choose the directory holding the checkouts and the first day whose merges are read.",
                symbol: "arrow.triangle.merge"
            )
        case .reviewing:
            WisentProgressPanel(
                title: "Reviewing merges",
                detail: "Reading main's merges in every checkout under the root."
            )
        case .failed(let sentence):
            WisentAlertPanel(tone: .danger, title: "Review refused", detail: sentence)
        case .done where model.records.isEmpty:
            WisentEmptyPanel(
                title: "No branch merges since that day",
                detail:
                    "No checkout under the root has a 'Merge <branch> into main' commit in that window.",
                symbol: "checkmark.seal"
            )
        case .done:
            table
        }
    }

    private var table: some View {
        WisentTableFrame {
            Table(model.records) {
                TableColumn("REPOSITORY") { record in
                    Text(record.repository).font(WisentTypeScale.body())
                }
                TableColumn("MERGE") { record in
                    Text("\(record.shortCommit) \(record.branch ?? "")")
                        .font(WisentTypeScale.identifier())
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                TableColumn("LEFT ON MAIN") { record in
                    WisentStatusChip(
                        text: record.findings,
                        tone: record.error != nil
                            ? .warning : (record.isDamaged ? .danger : .success)
                    )
                    .help(record.findings)
                }
            }
            .tableStyle(.inset)
        }
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Review merges"
        panel.message = "Choose the directory whose checkouts' merges are reviewed."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.root = url.path
    }
}
