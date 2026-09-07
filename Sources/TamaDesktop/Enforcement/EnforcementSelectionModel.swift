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
            let loaded = try await client().get(
                "enforcement",
                as: EnforcementSelection.self,
                operation: "read machine enforcement selection"
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

    func setEnforced(_ enforced: Bool, hookID: String, catalogIDs: [String]) {
        let current = selection ?? EnforcementSelection(
            mode: "all",
            enabled: [],
            readError: nil,
            emergencyDisabled: false
        )
        var enabled = current.mode == "all" ? Set(catalogIDs) : current.selectedIDs
        if enforced {
            enabled.insert(hookID)
        } else {
            enabled.remove(hookID)
        }
        let sorted = enabled.sorted()
        mutate(
            working: "Changing the machine-wide hook selection…",
            success: enforced
                ? "\(hookID) is selected on this machine."
                : "\(hookID) is not selected on this machine.",
            body: ["mode": "only", "enabled": sorted]
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
                let updated = try await client().post(
                    "enforcement",
                    body: body,
                    as: EnforcementSelection.self,
                    operation: "set machine enforcement selection"
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

    private func client() async throws -> TamaClient {
        TamaClient(baseURL: try await TamaBackend.shared.endpoint())
    }

    private static func sentence(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
