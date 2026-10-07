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
    @Published private(set) var scanMode: ViolationScanMode = .everyRule
    /// How many repair rounds the operator allows, as typed. `tama clean`
    /// has no default for `--max-rounds`, so neither does this screen.
    @Published var repairRounds: String = ""

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

    /// The typed rounds as a whole number above zero, or nothing.
    var repairRoundCount: Int? {
        guard
            let rounds = Int(repairRounds.trimmingCharacters(in: .whitespacesAndNewlines)),
            rounds > .zero
        else { return nil }
        return rounds
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

    /// Choosing another pass discards the report for the same reason a new
    /// scope does: its findings answer a different question.
    func select(mode: ViolationScanMode) {
        guard mode != scanMode, scanState != .scanning else { return }
        scanMode = mode
        report = nil
        scanState = .idle
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
        let mode = scanMode
        let task = Task.detached(priority: .userInitiated) {
            try await ViolationsClient().scan(repoPath: path, mode: mode)
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
        guard let rounds = repairRoundCount else {
            cleanState = .failed(
                "Say how many repair rounds the run may take: a whole number above zero.")
            return
        }
        cleanState = .running
        cleanCancellationRequested = false
        let task = Task.detached(priority: .userInitiated) {
            try await ViolationsClient().clean(repoPath: path, maxRounds: rounds)
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
        if case .failed(let message) = scanState {
            let commandMessage: String
            if cancellationRequested {
                commandMessage = ViolationsError.cleanupCancelled
            } else {
                commandMessage =
                    switch outcome {
                    case .success:
                        "Cleanup command completed."
                    case .failure(let error):
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
        case .failure(let error):
            let sentence =
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            cleanState = .failed(sentence)
            TamaFailureReporting.reportSurfaced(
                failurePoint: "tama.violations.clean",
                error: error,
                sentence: sentence
            )
        case .success(let summary):
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
            || cleanState == .rescanning
        {
            cleanCancellationRequested = true
        }
        cleanTask?.cancel()
        scanTask?.cancel()
    }
}
