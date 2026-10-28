import Foundation
import SwiftUI
import WisentDesignSystem

/// One index entry whose object the store lacks, and what was done
/// (`tama index repair`'s `missing`).
struct IndexMissingEntry: Decodable, Sendable, Hashable {
    let path: String
    let object: String
    let copied_from: String?
    let repair: String?
    let lost: Bool

    /// The entry as the CLI's text output says it.
    var said: String {
        switch (repair, lost) {
        case let (.some(done), true): return "\(path) \(object): \(done); its staged content is lost"
        case let (.some(done), false): return "\(path) \(object): \(done)"
        case (.none, _): return "\(path) \(object): missing (choose Repair index to repair it)"
        }
    }
}

/// An index with no entry while HEAD tracks files.
struct IndexEmptied: Decodable, Sendable {
    let head_entries: Int
    let restored: Bool
}

/// An entry that belongs to no state of the checkout (`tama index repair`'s
/// `strays`): `foreign`, staged for a path neither HEAD nor the working tree
/// holds, or `dropped`, a tracked path missing from the index whose working
/// file is present.
struct IndexStray: Decodable, Sendable, Hashable {
    let path: String
    let shape: String
    let object: String?
    let repaired: Bool

    var said: String {
        let done = repaired ? "read back from HEAD" : "choose Repair index to read it back from HEAD"
        guard let object else { return "\(path): \(shape), \(done)" }
        return "\(path) \(object): \(shape), \(done)"
    }
}

/// The answer of `tama index repair --json` and the `index/repair` request.
struct IndexRepairReport: Decodable, Sendable {
    let repository: String
    let index: String
    let index_variable: String?
    let entries: Int
    let missing: [IndexMissingEntry]
    let emptied: IndexEmptied?
    let strays: [IndexStray]
    let applied: Bool
}

@MainActor
final class IndexRepairModel: ObservableObject {
    @Published var repository = ""
    @Published private(set) var running = false
    @Published private(set) var report: IndexRepairReport?
    @Published private(set) var failure: String?

    var ready: Bool {
        !running && !repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func run(apply: Bool) async {
        guard ready else { return }
        running = true
        report = nil
        failure = nil
        defer { running = false }
        do {
            report = try await TamaClient().request(
                "index/repair", body: ["repository": repository, "apply": apply],
                as: IndexRepairReport.self, describing: "Index repair"
            )
        } catch {
            failure = error.localizedDescription
            TamaFailureReporting.reportSurfaced(
                failurePoint: "tama.index.repair", error: error,
                sentence: error.localizedDescription
            )
        }
    }
}

/// Reads a checkout's index for entries whose object is missing and for an
/// index emptied while HEAD tracks files, and repairs them on request; it
/// names the index file it read and the GIT_INDEX_FILE that chose it.
struct IndexRepairView: View {
    @StateObject private var model = IndexRepairModel()

    var body: some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
            Text("Index repair").font(WisentTypeScale.body())
            Text("Reads the checkout's index for entries whose object the store lacks and for an index emptied while HEAD tracks files. Repair writes the index only; working files stay as they are.")
            TextField("Repository checkout path", text: $model.repository)
                .disabled(model.running)
            HStack {
                Button("Read index") { Task { await model.run(apply: false) } }
                Button("Repair index") { Task { await model.run(apply: true) } }
            }
            .disabled(!model.ready)
            if model.running {
                ProgressView("Reading the index and the object store")
            }
            if let failure = model.failure {
                WisentAlertPanel(tone: .danger, title: "Index repair refused", detail: failure)
            }
            if let report = model.report {
                Text("Index file: \(report.index)").textSelection(.enabled)
                if let variable = report.index_variable {
                    WisentAlertPanel(
                        tone: .warning, title: "GIT_INDEX_FILE chose this file",
                        detail: "GIT_INDEX_FILE=\(variable) names \(report.index), not necessarily the checkout's own index."
                    )
                }
                Text("\(report.entries) entries, \(report.missing.count) naming an object the store does not hold")
                if let emptied = report.emptied {
                    Text(emptied.restored
                        ? "The index held no entry while HEAD tracks \(emptied.head_entries) files; read back from HEAD."
                        : "The index holds no entry while HEAD tracks \(emptied.head_entries) files; every tracked file reads as staged for deletion.")
                }
                ForEach(report.missing, id: \.self) { entry in
                    Text(entry.said).textSelection(.enabled)
                }
                ForEach(report.strays, id: \.self) { stray in
                    Text(stray.said).textSelection(.enabled)
                }
            }
        }
        .padding(WisentDesign.Space.x4)
    }
}
