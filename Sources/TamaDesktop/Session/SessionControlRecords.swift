import Darwin
import Foundation

/// What a session-control record has to be before Tama addresses it: an agent
/// id and control key it will write into a file name, and a liveness it can
/// tell.
extension SessionControlClient {
    func sessionIsLive(_ session: AgentSessionRecord, now: Date) -> Bool {
        switch session.livenessMode {
        case "process":
            guard let pid = session.pid else { return false }
            return processIsAlive(pid)
        case "heartbeat":
            guard let updated = Self.date(from: session.updatedAt),
                let ttl = session.heartbeatTTLSeconds
            else { return false }
            return updated.addingTimeInterval(TimeInterval(ttl)) >= now
        default:
            return false
        }
    }

    private static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func processIsAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if Darwin.kill(pid_t(pid), 0) == 0 { return true }
        return errno == EPERM
    }

    /// A record's owner process as a sentence fragment; a heartbeat record
    /// states none.
    static func processLabel(_ pid: Int32?) -> String {
        switch pid {
        case let pid?: "process \(pid)"
        case nil: "no owner process"
        }
    }

    func isSafeAgentId(_ value: String) -> Bool {
        guard let first = value.first, first.isASCII, first.isLetter,
            value.count <= Self.maximumAgentIdLength
        else {
            return false
        }
        return value.allSatisfy { character in
            character.isASCII && (character.isLowercase || character.isNumber || character == "-")
        }
    }

    func isSafeControlKey(_ value: String) -> Bool {
        value.count == Self.controlKeyHexLength && value.allSatisfy(\.isHexDigit)
    }
}

struct SessionControlSchemaEnvelope: Decodable {
    let schema: String
}

struct SessionControlRequest: Encodable {
    let schema: String
    let sessionId: String
    let controlKey: String
    let requestId: String
    let confirmed: Bool
    let operation: String
    let hookId: String?
    let enabled: Bool?
}

struct SessionControlResponse: Decodable {
    let schema: String
    let requestId: String
    let ok: Bool
    let error: String?
    let state: AgentSessionRecord?
}
