import Combine
import Foundation
import WisentDesignSystem

struct EnforcementSelection: Codable, Equatable, Sendable {
    let mode: String
    let enabled: [String]
    let readError: String?
    let emergencyDisabled: Bool

    var selectedIDs: Set<String> { Set(enabled) }

    func includes(_ hookID: String) -> Bool {
        mode == "all" || selectedIDs.contains(hookID)
    }

    func enforces(_ hookID: String) -> Bool {
        !emergencyDisabled && includes(hookID)
    }

    var modeLabel: String {
        mode == "only" ? "Only \(enabled.count.formatted(.number)) selected" : "All hooks"
    }
}

@MainActor
final class EnforcementSelectionModel: ObservableObject {
    @Published private(set) var selection: EnforcementSelection?
    @Published private(set) var outcome: WisentMutationOutcome = .idle
    @Published private(set) var readError: String?
    @Published private(set) var isLoading = false

    var isWorking: Bool { isLoading || outcome.isWorking }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await client().request(
                "enforcement",
                as: EnforcementSelection.self,
                describing: "read machine enforcement selection"
            )
            selection = loaded
            readError = loaded.readError
        } catch {
            readError = Self.sentence(error)
        }
    }

    func setAll() {
        mutate(
            working: "Selecting every registered hook on this machine…",
            success: "Every registered hook is selected on this machine.",
            body: ["mode": "all"]
        )
    }

    /// Turns one hook on or off against the selection as it is when Tama writes
    /// it (`add`/`remove`), so a change another session made since this screen
    /// read the selection is kept. Turning one hook off on a machine that runs
    /// every hook is the one case that writes a whole list: every catalog hook
    /// but this one.
    func setEnforced(_ enforced: Bool, hookID: String, catalogIDs: [String]) {
        guard let current = selection else {
            outcome = .failed(
                "The machine-wide hook selection has not been read yet, so nothing was changed; refresh and try again."
            )
            return
        }
        let success =
            enforced
            ? "\(hookID) is selected on this machine."
            : "\(hookID) is not selected on this machine."
        let body: [String: Any]
        if current.mode == "all" && !enforced {
            body = ["mode": "only", "enabled": catalogIDs.filter { $0 != hookID }.sorted()]
        } else {
            body = ["mode": enforced ? "add" : "remove", "enabled": [hookID]]
        }
        mutate(
            working: "Changing the machine-wide hook selection…",
            success: success,
            body: body
        )
    }

    func clearOutcome() {
        outcome = .idle
    }

    private func mutate(working: String, success: String, body: [String: Any]) {
        guard !isWorking else { return }
        outcome = .working(working)
        Task {
            do {
                let updated = try await client().request(
                    "enforcement/update",
                    body: body,
                    as: EnforcementSelection.self,
                    describing: "set machine enforcement selection"
                )
                selection = updated
                readError = updated.readError
                outcome = .succeeded(success)
            } catch {
                outcome = .failed(Self.sentence(error))
                await refresh()
            }
        }
    }

    private func client() -> TamaClient {
        TamaClient()
    }

    private static func sentence(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
