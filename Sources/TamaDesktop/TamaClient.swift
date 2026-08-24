import Foundation

/// HTTP/JSON client for the local Tama backend. Reads are plain GETs;
/// long-running jobs POST and stream NDJSON — log events carry the job's own
/// output in its own order, and the single result event carries the status
/// the command would have exited with and the document it would have printed.
struct TamaClient: Sendable {
    let baseURL: URL

    /// The folded end of one streamed job: the status, the result document
    /// re-encoded as JSON, and the job's stdout and stderr text.
    struct JobResult: Sendable {
        let status: Int
        let document: Data
        let stdoutText: String
        let stderrText: String

        /// The bounded stderr sentence, or the bounded stdout sentence when
        /// stderr stayed empty — the same preference the process runner had.
        var failureSentence: String {
            let stderr = Self.snippet(stderrText, limit: Int("600")!)
            if !stderr.isEmpty { return stderr }
            return Self.snippet(stdoutText, limit: Int("4000")!)
        }

        private static func snippet(_ text: String, limit: Int) -> String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > limit else { return trimmed }
            return String(trimmed.prefix(limit)) + "…"
        }
    }

    // MARK: - Reads

    /// GET, decoding the 2xx document; a non-2xx carries the backend's own
    /// refusal sentence.
    func get<Value: Decodable>(
        _ path: String,
        as type: Value.Type,
        operation: String
    ) async throws -> Value {
        let data = try await getData(path, operation: operation)
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw TamaBackendError.unreadableOutput(operation, error.localizedDescription)
        }
    }

    /// GET returning the raw document, for the caller that walks a shape too
    /// irregular for one Decodable type.
    func getDocument(_ path: String, operation: String) async throws -> Data {
        try await getData(path, operation: operation)
    }

    /// GET returning the document as pretty-printed text, for the snippet an
    /// operator pastes into a client configuration.
    func getPrettyText(_ path: String, operation: String) async throws -> String {
        let data = try await getData(path, operation: operation)
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
            ),
            let text = String(data: pretty, encoding: .utf8)
        else {
            throw TamaBackendError.unreadableOutput(operation, "not a JSON document")
        }
        return text
    }

    // MARK: - Jobs

    /// POST streaming NDJSON: a non-2xx before the stream starts is the
    /// refusal envelope; inside the stream, exactly one result event ends the
    /// job. Cancelling the calling task abandons the exchange.
    func postStreaming(
        _ path: String,
        body: [String: Any],
        operation: String
    ) async throws -> JobResult {
        do {
            return try await performStreaming(path, body: body)
        } catch is CancellationError {
            throw TamaBackendError.cancelled(operation)
        }
    }

    private func performStreaming(
        _ path: String,
        body: [String: Any]
    ) async throws -> JobResult {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw TamaBackendError.notHTTP }

        // A non-2xx before the stream starts is the error envelope.
        guard (200...299).contains(http.statusCode) else {
            var data = Data()
            for try await line in bytes.lines {
                data.append(contentsOf: line.utf8)
            }
            throw Self.refusal(data: data, status: http.statusCode)
        }

        var stdoutText = ""
        var stderrText = ""
        var resultStatus: Int?
        var resultDocument = Data()
        for try await line in bytes.lines {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = event["type"] as? String
            else { continue }
            switch type {
            case "log":
                let chunk = event["chunk"] as? String ?? ""
                if event["stream"] as? String == "stderr" {
                    stderrText += chunk
                } else {
                    stdoutText += chunk
                }
            case "result":
                resultStatus = (event["status"] as? NSNumber)?.intValue
                if let document = event["json"] {
                    resultDocument =
                        (try? JSONSerialization.data(withJSONObject: document)) ?? Data()
                }
            default:
                continue
            }
        }
        guard let status = resultStatus else { throw TamaBackendError.streamClosedEarly }
        return JobResult(
            status: status,
            document: resultDocument,
            stdoutText: stdoutText,
            stderrText: stderrText
        )
    }

    // MARK: - Transport

    private func getData(_ path: String, operation: String) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: endpoint(path))
        } catch is CancellationError {
            throw TamaBackendError.cancelled(operation)
        }
        guard let http = response as? HTTPURLResponse else { throw TamaBackendError.notHTTP }
        guard (200...299).contains(http.statusCode) else {
            throw Self.refusal(data: data, status: http.statusCode)
        }
        return data
    }

    private func endpoint(_ path: String) -> URL {
        baseURL.appendingPathComponent("v1").appendingPathComponent(path)
    }

    /// The error envelope is {"error": "<one sentence>"} — the product's own
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
