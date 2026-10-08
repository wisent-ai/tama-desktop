/// Which pass of `tama violations find` a scan runs: the hook replay, or one
/// of the in-process passes the CLI offers as `--size-only`, `--duplicates`,
/// `--internal-names` and `--time-limits`. The screen offers every pass the
/// command has, and `requestValue` is the `mode` the `violations/scan`
/// request takes.
enum ViolationScanMode: String, CaseIterable, Identifiable, Sendable {
    case everyRule
    case sizes
    case duplicates
    case internalNames
    case timeLimits

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyRule: "Every rule"
        case .sizes: "File and folder size"
        case .duplicates: "Capabilities written again"
        case .internalNames: "Internal names"
        case .timeLimits: "Waits and time limits"
        }
    }

    /// `nil` replays the hooks: the request carries no mode.
    var requestValue: String? {
        switch self {
        case .everyRule: nil
        case .sizes: "size-only"
        case .duplicates: "duplicates"
        case .internalNames: "internal-names"
        case .timeLimits: "time-limits"
        }
    }
}
