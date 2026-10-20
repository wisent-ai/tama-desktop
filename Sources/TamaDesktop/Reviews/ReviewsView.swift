import SwiftUI
import WisentDesignSystem

struct ReviewsView: View {
    @ObservedObject var model: ReviewsModel

    var body: some View {
        WisentScreen(
            title: "Reviews", scope: model.listing?.directory,
            freshness: freshness,
            actions: [
                WisentAction(
                    "Refresh", symbol: "arrow.clockwise", kind: .primary,
                    isEnabled: model.state != .loading, isBusy: model.state == .loading
                ) { Task { await model.refresh() } }
            ],
            scrolls: false, constrainsWidth: false
        ) {
            VSplitView {
                ScrollView {
                    VStack(alignment: .leading) {
                        StageView()
                        HarshRoundsView()
                    }
                }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .task(id: model.selectedID) { await model.readSelected() }
    }

    private var freshness: String {
        switch model.state {
        case .idle: "not read yet"
        case .loading: "reading retained reviews"
        case .failed: "inspection failed"
        case .ready: "retained results; no reviewer was run"
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .idle:
            WisentEmptyPanel(
                title: "Inspect commit reviews",
                detail:
                    "Refresh to read retained commit-review outcomes and their exact causes without repeating a commit or calling the reviewer.",
                symbol: "text.magnifyingglass"
            )
        case .loading:
            WisentProgressPanel(
                title: "Reading reviews", detail: "Reading Tama's retained commit-review results.")
        case .failed(let cause):
            WisentAlertPanel(tone: .danger, title: "Review inspection failed", detail: cause)
        case .ready:
            if let listing = model.listing {
                if listing.records.isEmpty {
                    WisentEmptyPanel(
                        title: "No retained reviews",
                        detail: "The inspected directory has no review entries.",
                        symbol: "text.magnifyingglass")
                } else {
                    VSplitView {
                        Table(listing.records, selection: $model.selectedID) {
                            TableColumn("REVIEW") { record in
                                Text(record.id).font(WisentTypeScale.identifier())
                            }
                            TableColumn("OUTCOME") { record in
                                if let result = record.result {
                                    Text(result.outcome.title)
                                } else if record.error != nil {
                                    Text("Unreadable result")
                                }
                            }
                        }
                        .tableStyle(.inset)
                        ScrollView { detail.padding(WisentDesign.Space.x4) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.detailState {
        case .idle:
            Text("Select a retained review to read its outcome and cause.")
        case .loading:
            WisentProgressPanel(
                title: "Reading selected review", detail: "Re-reading the selected retained result."
            )
        case .failed(let cause):
            WisentAlertPanel(
                tone: .danger, title: "Selected review could not be read", detail: cause)
        case .ready:
            if let record = model.selected {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                    Text(record.id).font(WisentTypeScale.identifier())
                    Text(record.directory).textSelection(.enabled)
                    if let error = record.error {
                        WisentAlertPanel(
                            tone: .danger, title: "Retained result unreadable", detail: error)
                    }
                    if let result = record.result {
                        Text(result.outcome.title).font(WisentTypeScale.body())
                        if let cause = result.detail { Text(cause).textSelection(.enabled) }
                        switch result.outcome {
                        case .pass:
                            Text(
                                "This records the review outcome, not proof that Git created the commit."
                            )
                        case .sourceFinding:
                            Text("Repair the grounded finding before committing again.")
                        case .reviewFailure:
                            Text(
                                "Repair the named review operation or dependency. A failed review does not establish a source defect."
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
