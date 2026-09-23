import Combine
import Foundation
import WisentDesignSystem

/// One hook binary's warm run, as the backend measured it.
struct HookWarmRow: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let command: String
    let path: String
    let elapsedMs: Int
    let exitCode: Int?
    let state: String

    var isUsable: Bool { state == "warm" }
}

struct HookWarmReport: Codable, Sendable, Equatable {
    let hooks: [HookWarmRow]
    let warmed: Int
    /// The binary that cost the most, and what it cost. Nothing is killed for
    /// being slow any more, so this is how a slow gate is found.
    let slowest: String?
    let slowestMs: Int?
    let unusable: Int
}

/// Warming the machine's hook binaries from the window.
///
/// A binary nobody has run yet still owes macOS its first-execution
/// assessment, and a hook pays that debt inside a live event, where everybody
/// waits it out: on 2026-09-20 a freshly installed
/// `tama-block-delegating-own-work` spent 147 seconds there while the binary
/// itself answers in four milliseconds. The terminal pays it with
/// `tama hooks warm`; this is the same operation, over the same backend
/// route, with the same measurements on screen.
@MainActor
final class HookWarmModel: ObservableObject {
    @Published private(set) var report: HookWarmReport?
    @Published private(set) var outcome: WisentMutationOutcome = .idle

    var isWorking: Bool { outcome.isWorking }

    /// The rows worth showing first: what could not run, then what cost most.
    var attention: [HookWarmRow] {
        (report?.hooks ?? [])
            .filter { !$0.isUsable || $0.elapsedMs == report?.slowestMs }
            .sorted { $0.elapsedMs > $1.elapsedMs }
    }

    func warm(only: [String] = []) {
        guard !isWorking else { return }
        outcome = .working("Running every hook binary once…")
        Task {
            do {
                let measured = try await client().request(
                    "hooks/warm",
                    body: only.isEmpty ? [:] : ["only": only],
                    as: HookWarmReport.self,
                    describing: "warm the machine's hook binaries"
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
        if let slowest = report.slowest, let cost = report.slowestMs {
            said += " \(slowest) cost the most at \(cost) ms;"
            said += " that cost is paid now instead of during the next event."
        }
        if report.unusable > 0 {
            said += " \(report.unusable) could not run at all."
        }
        return said
    }

    private func client() -> TamaClient {
        TamaClient()
    }

    private static func sentence(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
