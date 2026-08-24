import Foundation
import WisentErrors

/// The one reporting path for every failure Tama surfaces.
///
/// Each choke point that turns a failure into user-visible state calls
/// `report` once; the reporter itself is fire-and-forget and silent when the
/// intake is unconfigured, so these calls never change what the operator sees.
enum TamaFailureReporting {
    static let service = "tama"

    static func report(failurePoint: String, code: String, detail: String) {
        WisentFailureReporter.shared.report(
            failurePoint: failurePoint,
            code: code,
            service: service,
            detail: detail
        )
    }

    /// The catalogue's classification of an HTTP status the backend answered
    /// a request with.
    static func code(forRefusalStatus status: Int) -> String {
        switch status {
        case 401, 403:
            "auth"
        case 404:
            "not_found"
        case 429:
            "rate_limit"
        case 501, 505:
            "config"
        case 504:
            "timeout"
        case 500...599:
            "infra_down"
        default:
            "unknown"
        }
    }

    /// The best-fitting catalogue code for a failure raised inside the app.
    static func code(for error: Error) -> String {
        if let failure = error as? TamaBackendError {
            return switch failure {
            case .backendMissing:
                "config"
            case .startFailed, .notHTTP, .streamClosedEarly:
                "infra_down"
            case .refused, .unreadableOutput, .cancelled:
                "unknown"
            }
        }
        if let failure = error as? ViolationsError {
            return switch failure {
            case .invalidRepository:
                "not_found"
            case .repositoryNotOwned:
                "auth"
            case .cleanupAgentUnavailable:
                "config"
            }
        }
        return "unknown"
    }

    /// Failures already reported where they originate — a backend refusal at
    /// the client's mapping, a start failure at the spawn — plus the ones the
    /// operator raised on purpose (a cancellation) must not be reported a
    /// second time where they surface as model state.
    static func isReportedAtOrigin(_ error: Error) -> Bool {
        guard let failure = error as? TamaBackendError else { return false }
        return switch failure {
        case .refused, .startFailed, .backendMissing, .cancelled:
            true
        case .notHTTP, .streamClosedEarly, .unreadableOutput:
            false
        }
    }

    /// Report a model's error state, unless the failure was already reported
    /// where it originated.
    static func reportSurfaced(failurePoint: String, error: Error, sentence: String) {
        guard !isReportedAtOrigin(error) else { return }
        report(failurePoint: failurePoint, code: code(for: error), detail: sentence)
    }
}
