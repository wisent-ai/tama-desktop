import Foundation
import WisentErrors

/// The one reporting path for every failure Tama surfaces.
///
/// Each choke point reports once without awaiting delivery. Diagnostics can
/// await the reports already issued; settlement means the intake answered or
/// the attempt ended, not that every report was accepted.
enum TamaFailureReporting {
    static let service = "tama"
    private static let pending = DispatchGroup()

    static func report(failurePoint: String, code: String, detail: String) {
        let failure = Failure.orFallback(
            failurePoint: failurePoint,
            code: Code(rawValue: code) ?? .unknown,
            service: service
        ).detail(detail)
        pending.enter()
        WisentFailureReporter.shared.report(failure) {
            pending.leave()
        }
    }

    /// Wait for issued reports to settle before inspecting their stored state
    /// or exiting. Registration is synchronous, so a detached POST that has
    /// not started yet is included; no later sentinel can overtake it.
    static func settle() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pending.notify(queue: .global(qos: .utility)) {
                continuation.resume()
            }
        }
    }

    /// The catalogue's classification of the status a request process
    /// answered with, in HTTP's vocabulary: the catalogue's own reading of an
    /// upstream status, so the app and every other consumer classify alike.
    static func code(forRefusalStatus status: Int) -> String {
        Code.fromUpstream(status: status).rawValue
    }

    /// The best-fitting catalogue code for a failure raised inside the app.
    static func code(for error: Error) -> String {
        if let failure = error as? TamaBackendError {
            return switch failure {
            case .backendMissing:
                Code.config.rawValue
            case .startFailed, .endedWithoutAnswer, .inputFailed, .unexpectedExit:
                Code.infraDown.rawValue
            case .refused, .outputFailed, .unreadableOutput, .cancelled:
                Code.unknown.rawValue
            }
        }
        if let failure = error as? ViolationsError {
            return switch failure {
            case .invalidRepository:
                Code.notFound.rawValue
            case .repositoryNotOwned:
                Code.auth.rawValue
            }
        }
        return Code.unknown.rawValue
    }

    /// Failures already reported where they originate — a backend refusal at
    /// the client's mapping, a start failure at the spawn — plus the ones the
    /// operator raised on purpose (a cancellation) must not be reported a
    /// second time where they surface as model state.
    static func isReportedAtOrigin(_ error: Error) -> Bool {
        guard let failure = error as? TamaBackendError else { return false }
        return switch failure {
        case .refused, .startFailed, .backendMissing, .cancelled, .inputFailed, .outputFailed,
            .unexpectedExit:
            true
        case .endedWithoutAnswer, .unreadableOutput:
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
