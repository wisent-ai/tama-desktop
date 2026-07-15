import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: CatalogSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published var selection: SidebarSelection? = .overview
    @Published var selectedHookID: HookRecord.ID?
    @Published var searchText = ""
    @Published var hookFilter: HookFilter = .all
    @Published private(set) var areHooksDisabled = false

    private let client = HookCatalogClient()
    private let emergencySwitch = HookEmergencySwitch()

    var filteredHooks: [HookRecord] {
        guard let hooks = snapshot?.catalog.hooks else { return [] }
        return hooks.filter { hook in
            let matchesFilter = switch hookFilter {
            case .all: true
            case .blocking: hook.isBlocking
            case .nonblocking: !hook.isBlocking
            }
            guard matchesFilter else { return false }
            guard !searchText.isEmpty else { return true }
            return hook.id.localizedStandardContains(searchText)
                || hook.category.localizedStandardContains(searchText)
                || hook.eventNames.localizedStandardContains(searchText)
                || (hook.description?.localizedStandardContains(searchText) ?? false)
        }
    }

    var selectedHook: HookRecord? {
        guard let selectedHookID else { return filteredHooks.first }
        return snapshot?.catalog.hooks.first(where: { $0.id == selectedHookID })
    }

    init() {
        areHooksDisabled = emergencySwitch.isDisabled
        Task { await refresh() }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try HookCatalogClient().load()
            }.value
            snapshot = loaded
            if selectedHookID == nil {
                selectedHookID = loaded.catalog.hooks.first?.id
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isRefreshing = false
    }
    func setHooksDisabled(_ disabled: Bool) {
        do {
            try emergencySwitch.setDisabled(disabled)
            areHooksDisabled = emergencySwitch.isDisabled
            guard areHooksDisabled == disabled else {
                throw HookEmergencyError.stateDidNotPersist
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func revealSelectedSource() {
        guard let sourcePath = selectedHook?.sourcePath else { return }
        do {
            let root = try client.repositoryRoot()
            let source = root.appendingPathComponent(sourcePath)
            NSWorkspace.shared.activateFileViewerSelecting([source])
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func revealRepository() {
        do {
            NSWorkspace.shared.activateFileViewerSelecting([try client.repositoryRoot()])
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct HookEmergencySwitch {
    private static let schema = "ai.wisent.tama.hook-emergency-state.v1"
    private let manager = FileManager.default

    var isDisabled: Bool {
        guard
            let data = try? Data(contentsOf: stateURL),
            let state = try? JSONDecoder().decode(State.self, from: data)
        else {
            return false
        }
        return state.schema == Self.schema && state.disabled
    }

    func setDisabled(_ disabled: Bool) throws {
        if disabled {
            try manager.createDirectory(
                at: stateURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let state = State(
                schema: Self.schema,
                disabled: true,
                changedAt: ISO8601DateFormatter().string(from: Date())
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(state).write(to: stateURL, options: .atomic)
        } else if manager.fileExists(atPath: stateURL.path) {
            try manager.removeItem(at: stateURL)
        }
    }

    private var stateURL: URL {
        manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tama", isDirectory: true)
            .appendingPathComponent("hook-emergency-state.json")
    }

    private struct State: Codable {
        let schema: String
        let disabled: Bool
        let changedAt: String
    }
}

private enum HookEmergencyError: LocalizedError {
    case stateDidNotPersist

    var errorDescription: String? {
        "Tama could not persist the emergency hook state."
    }
}
