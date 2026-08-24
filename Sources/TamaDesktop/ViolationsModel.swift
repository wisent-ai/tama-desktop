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
        case cancelling
        case rescanning
        case done(String)
        case failed(String)
    }

    @Published private(set) var repoPath: String
    @Published private(set) var scanState: ScanState = .idle
    @Published private(set) var report: ViolationReport?
    @Published private(set) var cleanState: CleanState = .idle

    private let allowsOperations: Bool
    private var scanTask: Task<ViolationReport, Error>?
    private var cleanTask: Task<String, Error>?
    private var cleanCancellationRequested = false

    init(authorization: ControlAuthorization? = nil) {
        repoPath = ""
        allowsOperations = authorization != nil
    }

    var canScan: Bool {
        allowsOperations
            && !repoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && scanState != .scanning
            && cleanState != .running
            && cleanState != .rescanning
            && cleanState != .cancelling
    }

    var hasViolations: Bool {
        (report?.totals.violations ?? 0) > 0
    }

    /// Changing or clearing the scope discards the report: findings belong to
    /// the tree they were read from, and keeping them beside another tree
    /// invites the operator to repair the wrong one.
    func select(repository path: String) {
        guard path != repoPath else { return }
        repoPath = path
        report = nil
        scanState = .idle
        cleanState = .idle
    }

    func resetRepoPath() {
        select(repository: "")
    }

    func scan(preservingCleanState: Bool = false) async {
        guard allowsOperations, scanState != .scanning else { return }
        let path = repoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            scanState = .failed("Enter a repository path first.")
            return
        }
        if !preservingCleanState {
            cleanState = .idle
        }
        scanState = .scanning
        let task = Task.detached(priority: .userInitiated) {
            try await ViolationsClient().scan(repoPath: path)
        }
        scanTask = task
        do {
            report = try await task.value
            scanState = .done
        } catch {
            let sentence =
            (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            scanState = .failed(sentence)
            TamaFailureReporting.reportSurfaced(
                failurePoint: "tama.violations.scan",
                error: error,
                sentence: sentence
            )
        }
        scanTask = nil
    }

    func clean() async {
        guard
            allowsOperations,
            cleanState != .running,
            cleanState != .cancelling,
            cleanState != .rescanning,
            scanState != .scanning
        else { return }
        let path = repoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        cleanState = .running
        cleanCancellationRequested = false
        let task = Task.detached(priority: .userInitiated) {
            try await ViolationsClient().clean(repoPath: path)
        }
        cleanTask = task
        let outcome: Result<String, Error>
        do {
            outcome = .success(try await task.value)
        } catch {
            outcome = .failure(error)
        }
        cleanTask = nil
        let cancellationRequested = cleanCancellationRequested
        cleanState = .rescanning
        await scan(preservingCleanState: true)
        if case let .failed(message) = scanState {
            let commandMessage: String
            if cancellationRequested {
                commandMessage = ViolationsError.cleanupCancelled
            } else {
                commandMessage = switch outcome {
                case .success:
                    "Cleanup command completed."
                case let .failure(error):
                    (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
            cleanState = .failed(
                "\(commandMessage) Final rescan failed: \(message)"
            )
            cleanCancellationRequested = false
            return
        }
        if cancellationRequested {
            cleanCancellationRequested = false
            cleanState = .failed(ViolationsError.cleanupCancelled)
            return
        }
        cleanCancellationRequested = false

        switch outcome {
        case let .failure(error):
            let sentence =
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            cleanState = .failed(sentence)
            TamaFailureReporting.reportSurfaced(
                failurePoint: "tama.violations.clean",
                error: error,
                sentence: sentence
            )
        case let .success(summary):
            guard
                let report,
                report.totals.violations == .zero,
                report.totals.problems == .zero
            else {
                let sentence =
                    "Cleanup finished but the final scan is not clean. "
                    + "Review the remaining report and command summary: \(summary)"
                cleanState = .failed(sentence)
                TamaFailureReporting.report(
                    failurePoint: "tama.violations.clean",
                    code: "unknown",
                    detail: sentence
                )
                return
            }
            cleanState = .done(summary)
        }
    }

    func cancelScan() {
        guard scanState == .scanning else { return }
        scanTask?.cancel()
    }

    func cancelClean() {
        guard cleanState == .running else { return }
        cleanState = .cancelling
        cleanCancellationRequested = true
        cleanTask?.cancel()
    }

    func cancelAllOperations() {
        if cleanState == .running {
            cleanState = .cancelling
        }
        if cleanState == .running
            || cleanState == .cancelling
            || cleanState == .rescanning {
            cleanCancellationRequested = true
        }
        cleanTask?.cancel()
        scanTask?.cancel()
    }
}
