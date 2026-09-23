import Foundation

/// The declared coverage and the install plan, read on demand.
///
/// Both are read-only backend endpoints that had no surface at all. They are
/// not polled: each is read the first time its screen opens and then only when
/// the operator asks.
@MainActor
final class InspectionModel: ObservableObject {
    @Published private(set) var coverage: [ProviderCoverage] = []
    @Published private(set) var coverageError: String?
    @Published private(set) var isReadingCoverage = false
    @Published private(set) var coverageReadAt: Date?

    @Published private(set) var plan: InstallPlan?
    @Published private(set) var planError: String?
    @Published private(set) var isReadingPlan = false
    @Published private(set) var planReadAt: Date?

    @Published private(set) var mcpConfiguration: String?
    @Published private(set) var mcpError: String?
    @Published private(set) var isReadingMCP = false

    private var hasRequestedCoverage = false
    private var hasRequestedPlan = false

    func loadCoverage(force: Bool = false) async {
        guard force || !hasRequestedCoverage, !isReadingCoverage else { return }
        hasRequestedCoverage = true
        isReadingCoverage = true
        do {
            coverage = try await Task.detached(priority: .userInitiated) {
                try await PolicyInspectionClient().providerCoverage()
            }.value
            coverageError = nil
            coverageReadAt = Date()
        } catch {
            coverageError = Self.sentence(error)
            TamaFailureReporting.reportSurfaced(
                failurePoint: "tama.inspection.coverage",
                error: error,
                sentence: coverageError ?? Self.sentence(error)
            )
        }
        isReadingCoverage = false
    }

    func loadPlan(force: Bool = false) async {
        guard force || !hasRequestedPlan, !isReadingPlan else { return }
        hasRequestedPlan = true
        isReadingPlan = true
        async let planResult = Task.detached(priority: .userInitiated) {
            try await PolicyInspectionClient().installPlan()
        }.value
        do {
            plan = try await planResult
            planError = nil
            planReadAt = Date()
        } catch {
            planError = Self.sentence(error)
            TamaFailureReporting.reportSurfaced(
                failurePoint: "tama.inspection.plan",
                error: error,
                sentence: planError ?? Self.sentence(error)
            )
        }
        isReadingPlan = false
        await loadMCPConfiguration()
    }

    /// The MCP snippet is read beside the plan because it is the plan's `mcp`
    /// level made usable: the level names the server path, the snippet is what
    /// an operator pastes into a client configuration.
    private func loadMCPConfiguration() async {
        guard !isReadingMCP else { return }
        isReadingMCP = true
        do {
            mcpConfiguration = try await Task.detached(priority: .userInitiated) {
                try await PolicyInspectionClient().mcpConfiguration()
            }.value
            mcpError = nil
        } catch {
            mcpError = Self.sentence(error)
            TamaFailureReporting.reportSurfaced(
                failurePoint: "tama.inspection.mcp",
                error: error,
                sentence: mcpError ?? Self.sentence(error)
            )
        }
        isReadingMCP = false
    }

    private static func sentence(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
