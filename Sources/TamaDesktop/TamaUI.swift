import SwiftUI
import WisentDesignSystem

/// Where the operator can go, grouped by the decision they came to make.
///
/// The baseline listed six containers — Overview, Hook catalog, Justifications,
/// Snapshot validation, Repository hooks, Violations — and the decision the
/// operator actually arrives with ("may I unblock this session") was a
/// subsection of a hook's detail pane. Each destination below exists because
/// something is settled or verified there.
enum SidebarDestination: String, Identifiable, CaseIterable {
    case posture
    case hooks
    case session
    case violations
    case justifications
    case coverage
    case installPlan
    case settings

    enum Group: String, CaseIterable, Identifiable {
        case policy = "Policy"
        case repair = "Repair"
        case system = "System"

        var id: String { rawValue }
    }

    var id: String { rawValue }

    var group: Group {
        switch self {
        case .posture, .hooks, .session: .policy
        case .violations, .justifications: .repair
        case .coverage, .installPlan, .settings: .system
        }
    }

    var title: String {
        switch self {
        case .posture: "Posture"
        case .hooks: "Hooks"
        case .session: "Session"
        case .violations: "Violations"
        case .justifications: "Justifications"
        case .coverage: "Coverage"
        case .installPlan: "Install plan"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .posture: "shield.lefthalf.filled"
        case .hooks: "list.bullet.rectangle"
        case .session: "person.badge.key"
        case .violations: "ladybug"
        case .justifications: "text.badge.checkmark"
        case .coverage: "point.3.connected.trianglepath.dotted"
        case .installPlan: "shippingbox"
        case .settings: "gearshape.2"
        }
    }

    /// Read-only inspection keeps only what a signed-out operator may read: the
    /// bundled snapshot and the declared plan. Live sessions, the local
    /// justification registry and repository mutation stay behind the
    /// authorization boundary rather than appearing as dead rows.
    var requiresControl: Bool {
        switch self {
        case .session, .violations, .justifications: true
        case .posture, .hooks, .coverage, .installPlan, .settings: false
        }
    }

    static func destinations(controlEnabled: Bool, in group: Group) -> [SidebarDestination] {
        allCases.filter { $0.group == group && (controlEnabled || !$0.requiresControl) }
    }
}

/// The command that reproduces what the screen is reporting.
///
/// A failure the operator cannot reproduce outside the application is a rumour;
/// every alert on every screen carries one of these.
enum TamaCommand {
    static let status = "tama status --runtime"
    static let hooksValidate = "tama hooks validate --runtime"
    static let providerCoverage = "tama provider coverage --json"
    static let installPlan = "tama install-plan --json"
    static let mcpConfig = "tama mcp-config"

    static func findViolations(repository: String) -> String {
        "tama find-violations --repo \(repository.isEmpty ? "<path>" : repository)"
    }

    static func clean(repository: String) -> String {
        "tama clean --repo \(repository.isEmpty ? "<path>" : repository)"
    }
}

/// Availability mapped to tone in one place instead of in every view.
enum TamaTone {
    /// `Not registered` is a fresh install, not an outage.
    ///
    /// The baseline painted an absent macOS backend `danger`, which teaches an
    /// operator that red means nothing. Red is kept for a registration that
    /// failed or a status the system could not report at all.
    static func systemPolicy(_ status: String) -> WisentTone {
        if status == "Enabled" { return .success }
        if status == "Not registered" { return .neutral }
        if status.contains("failed") || status.contains("unavailable") { return .danger }
        return .warning
    }

    static func runtime(_ runtime: HookRuntimeStatus) -> WisentTone {
        if runtime.registryLoadError != nil { return .danger }
        if runtime.reloadPending == true { return .warning }
        if runtime.reloadRequired { return .warning }
        if runtime.loadedHookCount != runtime.registeredHookCount { return .warning }
        return .success
    }

    static func runtimeLabel(_ runtime: HookRuntimeStatus) -> String {
        if runtime.registryLoadError != nil { return "Load failed" }
        if runtime.reloadPending == true { return "Reload scheduled" }
        if runtime.reloadRequired { return "Reload required" }
        return "Loaded"
    }
}

/// `3 hooks`, `1 hook`: a count and its noun, agreed, without a format string
/// at every call site.
func counted(_ value: Int, _ noun: String) -> String {
    "\(value.formatted(.number)) \(noun)\(value == Int("1")! ? "" : "s")"
}

/// A 64-character control key or a 40-character release identifier is evidence,
/// not prose: the head is what identifies it in a log.
func shortIdentifier(_ value: String) -> String {
    String(value.prefix(Int("12")!))
}
