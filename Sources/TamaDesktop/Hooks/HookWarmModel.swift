import Combine
import Foundation
import WisentDesignSystem

/// One hook binary's warm run, as the backend measured it.
struct HookWarmRow: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let command: String
    let path: String
    let timeoutMs: Int
    let elapsedMs: Int
    let exitCode: Int?
    let state: String

    /// A run slower than the timeout its bindings allow would have been a
    /// refusal had it happened inside a live event.
    var wasCold: Bool { state == "cold" }
    var isUsable: Bool { state == "warm" || state == "cold" }
}

struct HookWarmReport: Codable, Sendable, Equatable {
    let hooks: [HookWarmRow]
    let warmed: Int
    let cold: Int
    let unusable: Int
}

/// Warming the machine's hook binaries from the window.
///
/// A binary nobody has run yet still owes macOS its first-execution
/// assessment, and a hook pays that debt inside a live event, where it reads
/// as a timeout and blocks the turn: on 2026-09-20
/// `block-delegating-own-work timed out after 10s` refused a finished turn
/// while the binary itself answers in four milliseconds. The terminal pays it
/// with `tama hooks warm`; this is the same operation, over the same backend
/// route, with the same measurements on screen.
@MainActor
final class HookWarmModel: ObservableObject {
    @Published private(set) var report: HookWarmReport?
    @Published private(set) var outcome: WisentMutationOutcome = .idle

    var isWorking: Bool { outcome.isWorking }

    /// The rows worth showing first: what could not run, then what was slow.
    var attention: [HookWarmRow] {
        (report?.hooks ?? [])
            .filter { !$0.isUsable || $0.wasCold }
            .sorted { $0.elapsedMs > $1.elapsedMs }
    }

    func warm(only: [String] = []) {
        guard !isWorking else { return }
        outcome = .working("Running every hook binary once…")
        Task {
            do {
                let measured = try await client().post(
                    "hooks/warm",
                    body: only.isEmpty ? [:] : ["only": only],
                    as: HookWarmReport.self,
                    operation: "warm the machine's hook binaries"
                )
                report = measured
                outcome = .succeeded(Self.sentence(for: measured))
            } catch {
                outcome = .failed(Self.sentence(error))
            }
        }
    }

    func clearOutcome() {
        outcome = .idle
    }

    private static func sentence(for report: HookWarmReport) -> String {
        var said = "\(report.warmed) hook binaries ran."
        if report.cold > 0 {
            said += " \(report.cold) took longer than the timeout a live event allows;"
            said += " that cost is paid now instead of during the next event."
        }
        if report.unusable > 0 {
            said += " \(report.unusable) could not run at all."
        }
        return said
    }

    private func client() async throws -> TamaClient {
        TamaClient(baseURL: try await TamaBackend.shared.endpoint())
    }

    private static func sentence(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
