import Darwin
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

    /// A streamed job's result and the complete process exchange that produced it.
    struct JobResult: Sendable {
        let status: Int
        let document: Data
        let operation: String
        let exchange: TamaExchange

        var stdoutText: String { exchange.stdoutText }

        /// Keep the terminal document and every observed cause labelled together.
        var failureSentence: String {
            "\(operation)\n\(exchange.diagnostics)"
        }

        /// The result document decoded as `type`. A schema mismatch keeps the
        /// whole exchange beside the decoder's cause, as a bounded answer's
        /// does, so a consumer never loses the document, exit and output.
        func decoded<Value: Decodable>(as type: Value.Type, describing description: String) throws
            -> Value
        {
            do {
                return try TamaClient.decode(
                    document, operation: operation, as: type, describing: description)
            } catch TamaBackendError.unreadableOutput(let context, let cause) {
                throw TamaBackendError.unreadableOutput(
                    context, "\(cause)\n\(exchange.diagnostics)")
            }
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
        let response = try await answer(operation, body: body, describing: description)
        do {
            return try Self.decode(
                response.data, operation: operation, as: type, describing: description)
        } catch TamaBackendError.unreadableOutput(let context, let cause) {
            throw TamaBackendError.unreadableOutput(
                context, "\(cause)\n\(response.exchange.diagnostics)")
        }
    }

    /// Bounded answers and streamed job results retain the same decoder
    /// context when an app and backend disagree about the response contract.
    static func decode<Value: Decodable>(
        _ data: Data,
        operation: String,
        as type: Value.Type,
        describing description: String
    ) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw TamaBackendError.unreadableOutput(
                "\(description) [\(operation)]", String(reflecting: error))
        }
    }

    /// The raw document, for the caller that walks a shape too irregular for
    /// one Decodable type.
    func document(_ operation: String, describing description: String) async throws -> Data {
        try await answer(operation, body: [:], describing: description).data
    }

    /// The document as pretty-printed text, for the snippet an operator pastes
    /// into a client configuration.
    func prettyText(_ operation: String, describing description: String) async throws -> String {
        let response = try await answer(operation, body: [:], describing: description)
        let pretty: Data
        do {
            pretty = try JSONSerialization.data(
                withJSONObject: try JSONSerialization.jsonObject(with: response.data),
                options: [.prettyPrinted, .sortedKeys]
            )
        } catch {
            throw TamaBackendError.unreadableOutput(
                "\(description) [\(operation)]",
                "JSON formatting failed: \(String(reflecting: error))\n\(response.exchange.diagnostics)"
            )
        }
        return String(decoding: pretty, as: UTF8.self)
    }

    // MARK: - Jobs

    /// Runs a streamed job: a refusal before it starts is the product's own
    /// sentence; otherwise exactly one result event ends it. Cancelling the
    /// calling task ends the process and everything it started.
    func job(
        _ operation: String,
        body: [String: Any],
        describing description: String,
        onEvent: (@Sendable (TamaJobEvent) -> Void)? = nil
    ) async throws -> JobResult {
        let exchange = try await run(
            operation, body: body, describing: description, onEvent: onEvent)
        switch exchange.end {
        case .result(let status, let document):
            try Self.validateExit(
                exchange, expected: status, operation: operation, describing: description)
            return JobResult(
                status: status,
                document: document,
                operation: operation,
                exchange: exchange
            )
        case .response(let status, let document):
            // Successful HTTP status class: https://www.rfc-editor.org/rfc/rfc9110.html#section-15.3
            guard (200...299).contains(status) else {
                throw Self.refusal(
                    data: document, status: status, operation: operation, exchange: exchange)
            }
            throw TamaBackendError.unreadableOutput(
                "\(description) [\(operation)]",
                "\(operation) answered instead of running a job\n\(exchange.diagnostics)"
            )
        case nil:
            throw Self.unanswered(exchange, describing: "\(description) [\(operation)]")
        }
    }

    /// A missing terminal event must not hide earlier output. Keep every
    /// observed channel separately labelled, together with operation and exit.
    private static func unanswered(
        _ exchange: TamaExchange, describing description: String
    ) -> TamaBackendError {
        return .endedWithoutAnswer(exchange.exitStatus, "\(description)\n\(exchange.diagnostics)")
    }

    // MARK: - Transport

    private func answer(
        _ operation: String,
        body: [String: Any],
        describing description: String
    ) async throws -> (data: Data, exchange: TamaExchange) {
        let exchange = try await run(operation, body: body, describing: description)
        switch exchange.end {
        case .response(let status, let document):
            // Successful HTTP status class: https://www.rfc-editor.org/rfc/rfc9110.html#section-15.3
            guard (200...299).contains(status) else {
                throw Self.refusal(
                    data: document, status: status, operation: operation, exchange: exchange)
            }
            try Self.validateExit(
                exchange, expected: Int(EXIT_SUCCESS), operation: operation, describing: description
            )
            return (document, exchange)
        case .result:
            throw TamaBackendError.unreadableOutput(
                "\(description) [\(operation)]",
                "\(operation) ran a job instead of answering\n\(exchange.diagnostics)"
            )
        case nil:
            throw Self.unanswered(exchange, describing: "\(description) [\(operation)]")
        }
    }

    /// A terminal document is not success when its process ended differently.
    /// Both require a normal exit, never a numerically matching signal.
    private static func validateExit(
        _ exchange: TamaExchange, expected: Int, operation: String, describing description: String
    ) throws {
        if exchange.terminationReason == .exit, Int(exchange.exitStatus) == expected { return }
        let error = TamaBackendError.unexpectedExit(
            "\(description) [\(operation)] expected normal process exit status \(expected) from its terminal event, but observed \(exchange.terminationReason) with status \(exchange.exitStatus).\n\(exchange.diagnostics)"
        )
        TamaFailureReporting.report(
            failurePoint: "tama.backend.exit",
            code: TamaFailureReporting.code(for: error),
            detail: error.localizedDescription
        )
        throw error
    }

    /// A process that cannot be found or started is reported where it
    /// happens, once; a cancelled run is the operator's choice, not a failure.
    private func run(
        _ operation: String,
        body: [String: Any],
        describing description: String,
        onEvent: (@Sendable (TamaJobEvent) -> Void)? = nil
    ) async throws -> TamaExchange {
        let exchange: TamaExchange
        do {
            let input: Data
            // JSONSerialization raises an Objective-C exception, which no
            // Swift `catch` reaches, for a body it cannot write (a NaN, an
            // infinity, a value of no JSON type); it is asked first, so the
            // body is refused here naming the operation instead of ending the app.
            guard body.isEmpty || JSONSerialization.isValidJSONObject(body) else {
                throw TamaBackendError.startFailed(
                    "\(description) [\(operation)] request body cannot be encoded: it holds a value JSON cannot write (a NaN, an infinity or a value of no JSON type)"
                )
            }
            do {
                input = body.isEmpty ? Data() : try JSONSerialization.data(withJSONObject: body)
            } catch {
                throw TamaBackendError.startFailed(
                    "\(description) [\(operation)] request body cannot be encoded: \(String(reflecting: error))"
                )
            }
            let command = try self.command ?? TamaCommand.bundled()
            do {
                exchange = try await TamaRequestProcess.run(
                    command, operation: operation, body: input, onEvent: onEvent)
            } catch TamaBackendError.startFailed(let cause) {
                throw TamaBackendError.startFailed(
                    "\(description) [\(operation)] using \(command.executable.path): \(cause)"
                )
            }
        } catch is CancellationError {
            throw TamaBackendError.cancelled(description)
        } catch {
            TamaFailureReporting.report(
                failurePoint: "tama.backend.start",
                code: TamaFailureReporting.code(for: error),
                detail: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
            throw error
        }
        if Task.isCancelled { throw TamaBackendError.cancelled(description) }
        if !exchange.inputErrors.isEmpty {
            let error = TamaBackendError.inputFailed(
                exchange.exitStatus, "\(description) [\(operation)]\n\(exchange.diagnostics)")
            TamaFailureReporting.report(
                failurePoint: "tama.backend.input",
                code: TamaFailureReporting.code(for: error),
                detail: error.localizedDescription
            )
            throw error
        }
        if !exchange.outputErrors.isEmpty || !exchange.unreadableEvents.isEmpty {
            let error = TamaBackendError.outputFailed(
                "\(description) [\(operation)]", exchange.diagnostics)
            TamaFailureReporting.report(
                failurePoint: exchange.outputErrors.isEmpty
                    ? "tama.backend.protocol" : "tama.backend.output",
                code: TamaFailureReporting.code(for: error),
                detail: error.localizedDescription
            )
            throw error
        }
        return exchange
    }

    /// The refusal envelope is {"error": "<one sentence>"} — the product's own
    /// refusal, surfaced verbatim. A body that is not that envelope (not JSON,
    /// or JSON without a sentence) is shown as it came with the parser's
    /// reason: "answered with status N" alone dropped the only words that
    /// said what went wrong.
    private static func refusal(
        data: Data, status: Int, operation: String, exchange: TamaExchange
    ) -> TamaBackendError {
        let body = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let message: String
        do {
            let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let sentence = envelope?["error"] as? String, !sentence.isEmpty {
                message = sentence
            } else {
                message =
                    "The Tama backend answered with status \(status) without an error sentence: \(body)"
            }
        } catch {
            message =
                body.isEmpty
                ? "The Tama backend answered with status \(status) and an empty body."
                : "The Tama backend answered with status \(status) and a body that is not JSON (\(error)): \(body)"
        }
        let detail = "\(message)\nrequest operation: \(operation)\n\(exchange.diagnostics)"
        TamaFailureReporting.report(
            failurePoint: "tama.backend.refusal",
            code: TamaFailureReporting.code(forRefusalStatus: status),
            detail: detail
        )
        return .refused(detail)
    }
}
