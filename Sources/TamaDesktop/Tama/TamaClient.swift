import Foundation

/// The client for Tama's own operations. Every call runs one
/// `tama request <operation>` process (`TamaRequestProcess`): the body
/// goes to its stdin, and nothing of Tama stays running once it has answered.
/// A bounded operation answers with one document; a long-running job reports
/// its own output in its own order, then the status the command would have
/// exited with and the document it would have printed.
struct TamaClient: Sendable {
    /// Nil runs the binary sealed into this build's hook release.
    var command: TamaCommand?

    /// The folded end of one streamed job: the status, the result document
    /// re-encoded as JSON, and the job's stdout and stderr text.
    struct JobResult: Sendable {
        /// How much of stderr, and failing that of stdout, a failure sentence shows.
        private static let stderrSentenceLimit = 600
        private static let stdoutSentenceLimit = 4000

        let status: Int
        let document: Data
        let stdoutText: String
        let stderrText: String

        /// The bounded stderr sentence, or the bounded stdout sentence when
        /// stderr stayed empty — the same preference the process runner had.
        var failureSentence: String {
            let stderr = Self.snippet(stderrText, limit: Self.stderrSentenceLimit)
            if !stderr.isEmpty { return stderr }
            return Self.snippet(stdoutText, limit: Self.stdoutSentenceLimit)
        }

        private static func snippet(_ text: String, limit: Int) -> String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > limit else { return trimmed }
            return String(trimmed.prefix(limit)) + "…"
        }
    }

    // MARK: - Answers

    /// Runs `operation` and decodes the document it answers with; a refusal
    /// carries the product's own sentence.
    func request<Value: Decodable>(
        _ operation: String,
        body: [String: Any] = [:],
        as type: Value.Type,
        describing description: String
    ) async throws -> Value {
        let data = try await answer(operation, body: body, describing: description)
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw TamaBackendError.unreadableOutput(description, error.localizedDescription)
        }
    }

    /// The raw document, for the caller that walks a shape too irregular for
    /// one Decodable type.
    func document(_ operation: String, describing description: String) async throws -> Data {
        try await answer(operation, body: [:], describing: description)
    }

    /// The document as pretty-printed text, for the snippet an operator pastes
    /// into a client configuration.
    func prettyText(_ operation: String, describing description: String) async throws -> String {
        let data = try await answer(operation, body: [:], describing: description)
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
            ),
            let text = String(data: pretty, encoding: .utf8)
        else {
            throw TamaBackendError.unreadableOutput(description, "not a JSON document")
        }
        return text
    }

    // MARK: - Jobs

    /// Runs a streamed job: a refusal before it starts is the product's own
    /// sentence; otherwise exactly one result event ends it. Cancelling the
    /// calling task ends the process and everything it started.
    func job(
        _ operation: String,
        body: [String: Any],
        describing description: String
    ) async throws -> JobResult {
        let exchange = try await run(operation, body: body, describing: description)
        switch exchange.end {
        case let .result(status, document):
            return JobResult(
                status: status,
                document: document,
                stdoutText: exchange.stdoutText,
                stderrText: exchange.stderrText
            )
        case let .response(status, document):
            guard (200...299).contains(status) else {
                throw Self.refusal(data: document, status: status)
            }
            throw TamaBackendError.unreadableOutput(
                description,
                "\(operation) answered instead of running a job"
            )
        case nil:
            throw TamaBackendError.endedWithoutAnswer(exchange.exitStatus, exchange.processError)
        }
    }

    // MARK: - Transport

    private func answer(
        _ operation: String,
        body: [String: Any],
        describing description: String
    ) async throws -> Data {
        let exchange = try await run(operation, body: body, describing: description)
        switch exchange.end {
        case let .response(status, document):
            guard (200...299).contains(status) else {
                throw Self.refusal(data: document, status: status)
            }
            return document
        case .result:
            throw TamaBackendError.unreadableOutput(
                description,
                "\(operation) ran a job instead of answering"
            )
        case nil:
            throw TamaBackendError.endedWithoutAnswer(exchange.exitStatus, exchange.processError)
        }
    }

    /// A process that cannot be found or started is reported where it
    /// happens, once; a cancelled run is the operator's choice, not a failure.
    private func run(
        _ operation: String,
        body: [String: Any],
        describing description: String
    ) async throws -> TamaExchange {
        let input = body.isEmpty ? Data() : try JSONSerialization.data(withJSONObject: body)
        let exchange: TamaExchange
        do {
            let command = try self.command ?? TamaCommand.bundled()
            exchange = try await TamaRequestProcess.run(command, operation: operation, body: input)
        } catch {
            TamaFailureReporting.report(
                failurePoint: "tama.backend.start",
                code: TamaFailureReporting.code(for: error),
                detail: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
            throw error
        }
        if Task.isCancelled { throw TamaBackendError.cancelled(description) }
        return exchange
    }

    /// The refusal envelope is {"error": "<one sentence>"} — the product's own
    /// refusal, surfaced verbatim.
    private static func refusal(data: Data, status: Int) -> TamaBackendError {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message =
            (object?["error"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? "The Tama backend answered with status \(status)."
        TamaFailureReporting.report(
            failurePoint: "tama.backend.refusal",
            code: TamaFailureReporting.code(forRefusalStatus: status),
            detail: message
        )
        return .refused(message)
    }
}
