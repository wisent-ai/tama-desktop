import SwiftUI

struct ViolationsView: View {
    @ObservedObject var model: ViolationsModel

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            TextField("Repository path", text: $model.repoPath)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .onSubmit {
                    if model.canScan {
                        Task { await model.scan() }
                    }
                }
            Button("Reset", systemImage: "arrow.counterclockwise") {
                model.resetRepoPath()
            }
            .labelStyle(.iconOnly)
            .help("Restore the default hooks-rotator repository")
            .disabled(!model.isRepoPathModified)
            Button("Scan", systemImage: "magnifyingglass") {
                Task { await model.scan() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canScan)
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        switch model.scanState {
        case .idle:
            ContentUnavailableView(
                "No scan yet",
                systemImage: "ladybug",
                description: Text(
                    "Scan a repository for existing violations of the shared pre-write hook rules. The scan is read-only."
                )
            )
        case .scanning:
            ProgressView("Scanning \(model.repoPath)…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView(
                "Scan failed",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .done:
            if let report = model.report {
                ViolationReportView(report: report, model: model)
            } else {
                ContentUnavailableView(
                    "No report",
                    systemImage: "ladybug",
                    description: Text("The scan finished without a report.")
                )
            }
        }
    }
}
