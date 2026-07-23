import Foundation

@MainActor
final class ViolationsModel: ObservableObject {
    enum ScanState: Equatable {
        case idle
        case scanning
        case done
        case failed(String)
    }

    enum CleanState: Equatable {
        case idle
        case running
        case done(String)
        case failed(String)
    }

    @Published var repoPath: String
    @Published private(set) var scanState: ScanState = .idle
    @Published private(set) var report: ViolationReport?
    @Published private(set) var cleanState: CleanState = .idle

    private let defaultRepoPath: String?

    init() {
        defaultRepoPath = try? HookCatalogClient().repositoryRoot().path
        repoPath = defaultRepoPath ?? ""
    }

    var isRepoPathModified: Bool {
        repoPath != (defaultRepoPath ?? "")
    }

    var canScan: Bool {
        !repoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && scanState != .scanning
            && cleanState != .running
    }

    var hasViolations: Bool {
        (report?.totals.violations ?? 0) > 0
    }

    func resetRepoPath() {
        repoPath = defaultRepoPath ?? ""
    }

    func scan(preservingCleanState: Bool = false) async {
        guard scanState != .scanning else { return }
        let path = repoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            scanState = .failed("Enter a repository path first.")
            return
        }
        if !preservingCleanState {
            cleanState = .idle
        }
        scanState = .scanning
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try ViolationsClient().scan(repoPath: path)
            }.value
            report = loaded
            scanState = .done
        } catch {
            scanState = .failed(
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    func clean() async {
        guard cleanState != .running, scanState != .scanning else { return }
        let path = repoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        cleanState = .running
        do {
            let summary = try await Task.detached(priority: .userInitiated) {
                try ViolationsClient().clean(repoPath: path)
            }.value
            cleanState = .done(summary)
        } catch {
            cleanState = .failed(
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
        await scan(preservingCleanState: true)
    }
}
