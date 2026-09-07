import SwiftUI
import WisentDesignSystem

extension HooksView {
    // MARK: - Centre

    @ViewBuilder
    func centre(visible: [HookRecord]) -> some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
            machineSelectionPanel
            if let catalogError = model.catalogError, model.snapshot != nil {
                WisentErrorBanner(
                    title: "Policy refresh failed",
                    detail: catalogError,
                    action: WisentAction("Retry", symbol: "arrow.clockwise", kind: .secondary) {
                        Task { await model.refresh() }
                    }
                )
            }
            WisentMutationBar(outcome: model.mutation) { model.clearMutation() }
            if model.snapshot == nil {
                if let catalogError = model.catalogError {
                    WisentAlertPanel(
                        tone: .danger,
                        title: "Policy unavailable",
                        detail: catalogError,
                                                actions: [
                            WisentAction("Retry", symbol: "arrow.clockwise", kind: .primary) {
                                Task { await model.refresh() }
                            }
                        ]
                    )
                } else {
                    WisentSkeletonTable(
                        rows: 6,
                        columns: 5,
                        header: true,
                        label: "Reading policies"
                    )
                }
                Spacer(minLength: 0)
            } else if model.hooks.isEmpty {
                WisentEmptyPanel(
                    title: "No policies in this release",
                    detail: "No policies are available.",
                    symbol: "tray"
                )
                Spacer(minLength: 0)
            } else if visible.isEmpty {
                WisentEmptyPanel(
                    title: "No policy matches this selection",
                    detail: "\(counted(model.hooks.count, "policy")) available. Change or clear the filters.",
                    symbol: "line.3.horizontal.decrease.circle",
                    action: WisentAction("Clear filters", kind: .secondary) { clearFilters() }
                )
                Spacer(minLength: 0)
            } else {
                table(visible: visible)
            }
        }
        .padding(WisentDesign.Space.x5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The chip marks the minority. When most of the catalog blocks, the pill
    /// moves to the advisory rows, and the majority count stays in the rail.
    private var chipsBlocking: Bool {
        let hooks = model.hooks
        let blocking = hooks.lazy.filter(\.isBlocking).count
        return blocking * Int("2")! <= hooks.count
    }

    private func table(visible: [HookRecord]) -> some View {
        WisentTableFrame {
            Table(visible, selection: $selection) {
                TableColumn("POLICY") { hook in
                    Text(hook.id)
                        .font(WisentTypeScale.identifier())
                        .foregroundStyle(WisentDesign.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(hook.id)
                        .frame(height: WisentAppLayout.tableRowHeight, alignment: .leading)
                }
                .width(min: 130, ideal: 220)
                TableColumn("CATEGORY") { hook in
                    Text(hook.category)
                        .font(WisentTypeScale.body())
                        .foregroundStyle(WisentDesign.secondary)
                        .lineLimit(1)
                }
                .width(min: 70, ideal: 110)
                TableColumn("EVENTS") { hook in
                    Text(hook.events.count.formatted(.number))
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(WisentDesign.secondary)
                        .monospacedDigit()
                }
                .width(min: 44, ideal: 60)
                TableColumn("MACHINE") { hook in
                    let status = machineStatus(hook)
                    WisentStatusChip(text: status.0, tone: status.1)
                }
                .width(min: 74, ideal: 92)
                TableColumn("FLAG") { hook in
                    if hook.isBlocking == chipsBlocking {
                        WisentStatusChip(
                            text: hook.isBlocking ? "Blocking" : "Advisory",
                            tone: hook.isBlocking ? .warning : .neutral
                        )
                    }
                }
                .width(min: 40, ideal: 72)
            }
            .tableStyle(.inset)
            .font(WisentTypeScale.body())
            // A click on this table already means "select this hook" and a drag
            // means "extend that selection", so selectable cell text would
            // compete with both. Opting out restores exactly the behaviour the
            // index had before the window turned selection on.
            .textSelection(.disabled)
        }
    }

}
