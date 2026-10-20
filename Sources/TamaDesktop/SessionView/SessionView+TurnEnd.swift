import Foundation
import SwiftUI
import WisentDesignSystem

/// A time the core wrote: milliseconds since the epoch, or why its clock
/// could not say.
enum TurnEndClock: Decodable, Equatable, Sendable {
    case milliseconds(UInt64)
    case clockError(String)

    private enum Keys: String, CodingKey { case clockError }

    init(from decoder: Decoder) throws {
        do {
            self = .milliseconds(try decoder.singleValueContainer().decode(UInt64.self))
        } catch DecodingError.typeMismatch {
            let keyed = try decoder.container(keyedBy: Keys.self)
            self = .clockError(try keyed.decode(String.self, forKey: .clockError))
        }
    }

    var shown: String {
        switch self {
        case .milliseconds(let milliseconds):
            let seconds = Measurement(value: Double(milliseconds), unit: UnitDuration.milliseconds)
                .converted(to: .seconds).value
            return Date(timeIntervalSince1970: seconds).formatted(date: .abbreviated, time: .standard)
        case .clockError(let error):
            return "at a time the core's clock could not give (\(error))"
        }
    }
}

/// One hook the decision ran.
struct TurnEndHook: Decodable, Equatable, Sendable {
    let id: String?
    let code: Int?
    let ms: UInt64?
    let skipped: Bool?
}

/// The decision the core sent for the stop.
struct TurnEndDecision: Decodable, Equatable, Sendable {
    let blockedHookId: String?
    let results: [TurnEndHook]?
}

/// `turn-end.<session id>.json`, as the core writes it for every stop.
struct TurnEndRecord: Decodable, Equatable, Sendable {
    let answered: Bool
    let startedAtMs: TurnEndClock?
    let finishedAtMs: TurnEndClock?
    let reading: String?
    let decision: TurnEndDecision?
}

extension SessionControlClient {
    /// The session's last turn ending; nil when the core has recorded none.
    func turnEnd(sessionId: String) throws -> TurnEndRecord? {
        let url = try sessionDirectory().appendingPathComponent("turn-end.\(sessionId).json")
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
        return try JSONDecoder().decode(TurnEndRecord.self, from: data)
    }
}

/// How the session's last turn ended: the record and the sentence
/// `tama hooks running` prints for it.
struct TurnEndPanel: View {
    let session: AgentSessionRecord
    @State private var record: TurnEndRecord?
    @State private var failure: String?

    var body: some View {
        Group {
            if let failure {
                WisentAlertPanel(tone: .danger, title: "Last turn ending unreadable", detail: failure)
            } else if let record {
                if record.answered, record.decision?.blockedHookId == nil {
                    WisentField(label: "Last turn ending", value: Self.detail(record))
                } else {
                    WisentAlertPanel(tone: .warning, title: "Last turn ending", detail: Self.detail(record))
                }
            }
        }
        .task(id: session.updatedAt) {
            do {
                record = try SessionControlClient().turnEnd(sessionId: session.sessionId)
                failure = nil
            } catch {
                failure = "turn-end.\(session.sessionId).json: \(error)"
            }
        }
    }

    private static func detail(_ record: TurnEndRecord) -> String {
        var lines: [String] = []
        if let reading = record.reading {
            lines.append(reading)
        } else {
            lines.append("This record was written before the core gave each record its reading; `tama hooks running` reads it.")
        }
        if let started = record.startedAtMs {
            lines.append("Received \(started.shown)")
        }
        if let finished = record.finishedAtMs {
            lines.append("Answered \(finished.shown)")
        }
        if let refusing = record.decision?.blockedHookId {
            lines.append("Refused by \(refusing)")
        }
        if let results = record.decision?.results {
            lines.append(contentsOf: results.map(Self.hookLine))
        }
        return lines.joined(separator: "\n")
    }

    private static func hookLine(_ hook: TurnEndHook) -> String {
        let name: String
        if let id = hook.id {
            name = id
        } else {
            name = "A hook the decision names without an id"
        }
        if hook.skipped == true {
            return "\(name): skipped"
        }
        let exit: String
        if let code = hook.code {
            exit = "exit \(code)"
        } else {
            exit = "no exit code"
        }
        if let ms = hook.ms {
            return "\(name): \(exit) after \(ms) ms"
        }
        return "\(name): \(exit)"
    }
}

extension SessionView {
    /// What holds this session's next step: how its last turn ended, and the
    /// task scope its changes and calls are judged against.
    @ViewBuilder
    func turnEnd(_ session: AgentSessionRecord) -> some View {
        TurnEndPanel(session: session)
        TaskScopePanel(session: session.sessionId)
    }
}
