import AppKit
import SwiftUI
import WisentDesignSystem

/// Every repository copy under the named roots, and the one verb that deletes
/// them.
///
/// Tama blocks `git clone` of a local path and a recursive copy of a
/// checkout, so the copies that exist are the only ones there will be.
/// Removing them is what reclaims disk: on 2026-09-09 this machine held 45
/// nested checkouts worth 24 GiB under one project tree, an 8.4 GiB clone of
/// one upstream among them. The screen carries the same capability as
/// `tama copies`, and the same refusals.
struct CopiesView: View {
    @ObservedObject var model: CopiesModel

    @State var selection: CopyRecord.ID?
    @State var isDecidingRemoval = false

    var body: some View {
        WisentScreen(
            title: "Copies",
            scope: model.roots.isEmpty ? nil : counted(model.roots.count, "root"),
            freshness: freshness,
            actions: actions,
            scrolls: false,
            constrainsWidth: false
        ) {
            HStack(spacing: .zero) {
                centre
                inspector
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .sheet(isPresented: $isDecidingRemoval) { removalDecision }
    }

    // MARK: - Context bar

    private var freshness: String {
        switch model.scanState {
        case .idle: model.roots.isEmpty ? "no root selected" : "not scanned"
        case .scanning: "scanning now"
        case .failed: "scan refused"
        case .done: "\(counted(model.copyCount, "copy")) · \(model.sizeLabel)"
        }
    }

    /// Four verbs in the order the decision is made: name a root, read what is
    /// there, read what removal would do, then remove.
    private var actions: [WisentAction] {
        [
            WisentAction("Add root…", symbol: "folder.badge.plus", kind: .secondary) {
                chooseRoot()
            },
            WisentAction(
                "Scan",
                symbol: "magnifyingglass",
                kind: .primary,
                isEnabled: model.canScan,
                isBusy: model.scanState == .scanning
            ) {
                Task { await model.list() }
            },
            WisentAction(
                "Preview removal",
                symbol: "eye",
                kind: .secondary,
                isEnabled: model.canPreview,
                isBusy: model.removalState == .previewing
            ) {
                Task { await model.previewRemoval() }
            },
            WisentAction(
                "Remove copies",
                symbol: "trash",
                kind: .destructive,
                isEnabled: model.canApply,
                isBusy: model.removalState == .applying
            ) {
                isDecidingRemoval = true
            },
        ]
    }

    /// A directory chooser, not a free-text field: the walk refuses a relative
    /// path and a directory that does not exist, and both are avoidable before
    /// the request leaves.
    func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Scan for copies"
        panel.message = "Choose a directory to scan for second full checkouts."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { model.add(root: url.path) }
    }
}
