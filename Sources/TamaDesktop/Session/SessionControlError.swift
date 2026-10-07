import Darwin
import Foundation

enum SessionControlError: LocalizedError {
    case invalidSession
    case invalidResponse
    case legacySessionRecords
    case requestRejected(String)
    case directoryUnwatchable(String, String)
    case sessionEnded

    var errorDescription: String? {
        switch self {
        case .invalidSession:
            "Tama rejected an invalid agent session control endpoint."
        case .invalidResponse:
            "The agent runtime returned an invalid session-control response."
        case .legacySessionRecords:
            "Tama found only legacy v1 session records. Reinstall the verified bundled runtime, then stop or resume the affected agent session to publish v2 state."
        case .requestRejected(let reason):
            "The agent runtime rejected the session-control request: \(reason)"
        case .directoryUnwatchable(let path, let reason):
            "Tama could not watch the session-control directory \(path): \(reason)"
        case .sessionEnded:
            "The agent session ended before the session-control request completed."
        }
    }
}
