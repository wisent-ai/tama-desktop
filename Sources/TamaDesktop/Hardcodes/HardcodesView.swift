import AppKit
import SwiftUI
import WisentDesignSystem

/// Every line of the repositories under one root that writes down a value
/// nobody declared — a fleet host, a vault item, a number, a host with a
/// port — and, when asked, the commit that wrote it. The screen carries the
/// same capability as `tama hardcodes` and reads its document; it changes
/// nothing, because giving a value its source is a commit, not a click.
struct HardcodesView: View {
    @ObservedObject var model: HardcodesModel

    var body: some View {
        WisentScreen(
            title: "Hardcodes",
            scope: model.root.isEmpty ? nil : model.root,
            freshness: freshness,
            actions: actions,
            scrolls: false,
            constrainsWidth: false
        ) {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                Toggle("Name the commit that wrote each line", isOn: $model.origins)
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var freshness: String {
        switch model.state {
        case .idle: model.root.isEmpty ? "no root selected" : "not scanned"
        case .scanning: "scanning now"
        case .failed: "scan refused"
        case .done:
            "\(counted(model.document?.totals.findings ?? .zero, "finding")) · \(counted(model.document?.totals.repositories ?? .zero, "repository"))"
        }
    }

    private var actions: [WisentAction] {
        [
            WisentAction("Choose root…", symbol: "folder.badge.plus", kind: .secondary) {
                chooseRoot()
            },
            WisentAction(
                "Scan",
                symbol: "magnifyingglass",
                kind: .primary,
                isEnabled: model.canScan,
                isBusy: model.state == .scanning
            ) {
                Task { await model.scan() }
            },
        ]
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            WisentEmptyPanel(
                title: model.root.isEmpty ? "No root selected" : "Not scanned",
                detail: "Choose a repository, or the directory holding repositories, to read.",
                symbol: "number"
            )
        case .scanning:
            WisentProgressPanel(
                title: "Reading every tracked line",
                detail:
                    "Host and vault names come live from Stado; numbers are what block-numeric-literals refuses."
            )
        case .failed(let sentence):
            WisentAlertPanel(tone: .danger, title: "Scan refused", detail: sentence)
        case .done:
            VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                ForEach(model.document?.unreadable ?? [], id: \.repo) { unreadable in
                    WisentAlertPanel(
                        tone: .warning,
                        title: "Unreadable: \(unreadable.repo)",
                        detail: unreadable.error
                    )
                }
                if model.rows.isEmpty {
                    WisentEmptyPanel(
                        title: "Nothing written down without a source",
                        detail:
                            "No tracked line under the root names a fleet host or a vault item, or writes a refused number or an address.",
                        symbol: "checkmark.seal"
                    )
                } else {
                    table
                }
            }
        }
    }

    private var table: some View {
        WisentTableFrame {
            Table(model.rows) {
                TableColumn("REPOSITORY") { row in
                    Text(URL(fileURLWithPath: row.repository).lastPathComponent)
                        .font(WisentTypeScale.body())
                        .help(row.repository)
                }
                TableColumn("LINE") { row in
                    Text("\(row.finding.path):\(row.finding.line)")
                        .font(WisentTypeScale.identifier())
                        .lineLimit(1)
                        .truncationMode(.head)
                        .help("\(row.finding.path):\(row.finding.line)")
                }
                TableColumn("KIND") { row in
                    WisentStatusChip(text: row.finding.kind, tone: .warning)
                }
                TableColumn("VALUE") { row in
                    Text(row.finding.value)
                        .font(WisentTypeScale.identifier())
                        .lineLimit(1)
                        .help(row.finding.value)
                }
                TableColumn("WRITTEN IN") { row in
                    Text(row.origin)
                        .font(WisentTypeScale.caption())
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(row.origin)
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
        panel.prompt = "Read hardcodes"
        panel.message = "Choose a repository, or the directory holding repositories."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.root = url.path
    }
}
