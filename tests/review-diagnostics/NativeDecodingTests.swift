import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import TamaDesktop

final class NativeDecodingTests: XCTestCase, @unchecked Sendable {
    /// `model-provider/set` answers `{"choice": {...}, "check": {...}}`
    /// (tama-cli brama/desktop.rs); the declared provider is the choice's.
    private struct ProviderChoice: Decodable {
        struct Choice: Decodable {
            let provider: String
        }
        let choice: Choice
        var provider: String { choice.provider }
    }

    func testIncompatibleNativeResponseNamesOperationAndMissingFieldWithoutMutatingState() async throws {
        let (client, root, provider) = try fixture()
        let selected: ProviderChoice = try await client.request(
            "model-provider/set", body: ["none": true], as: ProviderChoice.self,
            describing: "Select an independent review declaration")
        XCTAssertEqual(selected.provider, "none")
        let before = try Data(contentsOf: provider)
        let response = try await client.document("model-provider", describing: "Read the declaration")
        try response.write(to: root.appendingPathComponent("response.json"))
        do {
            // A real native response with an incompatible consumer schema models
            // the observable contract mismatch between app and backend releases.
            let _: JudgementInspection = try await client.request(
                "model-provider", as: JudgementInspection.self,
                describing: "Read a retained review")
            XCTFail("An incompatible native document must not become a review inspection")
        } catch let error as TamaBackendError {
            try Data(error.localizedDescription.utf8).write(to: root.appendingPathComponent("failure.txt"))
            guard case .unreadableOutput(let operation, let cause) = error else {
                return XCTFail("Expected a native document mismatch, observed: \(error)")
            }
            XCTAssertTrue(operation.contains("model-provider"), operation)
            XCTAssertTrue(cause.contains("question"), cause)
            XCTAssertTrue(cause.contains("keyNotFound"), cause)
            XCTAssertTrue(cause.contains("bounded response document:"), cause)
            XCTAssertTrue(cause.contains("\"provider\""), cause)
            XCTAssertTrue(cause.contains("\"none\""), cause)
            XCTAssertTrue(cause.contains("request process exit status: \(EXIT_SUCCESS)"), cause)
        }
        XCTAssertEqual(try Data(contentsOf: provider), before)
    }

    func testBoundedAnswerRefusesJobConsumerWithItsDocumentAndUnchangedState() async throws {
        let (client, root, provider) = try fixture()
        let selected: ProviderChoice = try await client.request(
            "model-provider/set", body: ["none": true], as: ProviderChoice.self,
            describing: "Select an independent review declaration")
        XCTAssertEqual(selected.provider, "none")
        let before = try Data(contentsOf: provider)
        let operation = "model-provider"
        do {
            _ = try await client.job(
                operation, body: [:], describing: "Request a document as a streamed job")
            XCTFail("A bounded response must not become a streamed job result")
        } catch let error as TamaBackendError {
            try Data(error.localizedDescription.utf8)
                .write(to: root.appendingPathComponent("terminal-mismatch.txt"))
            guard case .unreadableOutput(let context, let cause) = error else {
                return XCTFail("Expected a native terminal-kind mismatch, observed: \(error)")
            }
            XCTAssertTrue(context.contains(operation), context)
            XCTAssertTrue(cause.contains("answered instead of running a job"), cause)
            XCTAssertTrue(cause.contains("\"provider\""), cause)
            XCTAssertTrue(cause.contains("\"none\""), cause)
            XCTAssertTrue(cause.contains("request process exit status: \(EXIT_SUCCESS)"), cause)
        }
        XCTAssertEqual(try Data(contentsOf: provider), before)
    }

    func testBoundedRefusalRetainsBackendCauseAndExchangeWithoutChangingState() async throws {
        let (client, root, provider) = try fixture()
        let selected: ProviderChoice = try await client.request(
            "model-provider/set", body: ["none": true], as: ProviderChoice.self,
            describing: "Select an independent review declaration")
        XCTAssertEqual(selected.provider, "none")
        let before = try Data(contentsOf: provider)
        let operation = "review-diagnostics/\(UUID().uuidString)"
        for runAsJob in [false, true] {
            do {
                if runAsJob {
                    _ = try await client.job(
                        operation, body: [:], describing: "Read an unknown job operation")
                } else {
                    _ = try await client.document(
                        operation, describing: "Read an unknown bounded operation")
                }
                XCTFail("An unknown native operation must not become a successful answer")
            } catch let error as TamaBackendError {
                let cause = error.localizedDescription
                try Data(cause.utf8).write(
                    to: root.appendingPathComponent("bounded-refusal-\(runAsJob).txt"))
                guard case .refused = error else {
                    return XCTFail("Expected the backend's bounded refusal, observed: \(error)")
                }
                XCTAssertTrue(cause.contains("unknown operation: \(operation)"), cause)
                XCTAssertTrue(cause.contains("request operation: \(operation)"), cause)
                XCTAssertTrue(cause.contains("bounded response status:"), cause)
                XCTAssertTrue(cause.contains("bounded response document:"), cause)
                XCTAssertTrue(cause.contains("request process exit status: \(EXIT_FAILURE)"), cause)
            }
            XCTAssertEqual(try Data(contentsOf: provider), before)
        }
    }

    func testEarlyNativeRefusalRetainsCompleteUnicodeCauseWithoutWritingState() async throws {
        let (client, root, provider) = try fixture()
        // A host page supplies a real multi-chunk argument and request body.
        // The actual CLI refuses the option before reading request input.
        let option = "--" + String(repeating: "é", count: Int(getpagesize()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: provider.path))
        do {
            let _: ProviderChoice = try await client.request(
                option, body: ["input": option], as: ProviderChoice.self,
                describing: "Read an invalid native operation")
            XCTFail("An unknown native option must not become a successful document")
        } catch let error as TamaBackendError {
            try Data(error.localizedDescription.utf8).write(to: root.appendingPathComponent("failure.txt"))
            let status: Int32
            switch error {
            case .endedWithoutAnswer(let observed, _), .inputFailed(let observed, _):
                status = observed
            default:
                throw error
            }
            let cause = error.localizedDescription
            XCTAssertNotEqual(status, EXIT_SUCCESS)
            XCTAssertTrue(cause.contains(option), cause)
            try JSONSerialization.data(withJSONObject: [
                "arguments": ["request", option], "requestBody": ["input": option],
                "exitStatus": status, "diagnostic": cause
            ], options: [.prettyPrinted, .sortedKeys])
                .write(to: root.appendingPathComponent("refusal.json"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: provider.path))
    }

    func testMissingNativeExecutableNamesOperationAndExecutableWithoutWritingState() async throws {
        let (_, root, provider) = try fixture()
        let executable = root.appendingPathComponent("unavailable-tama")
        let operation = "model-provider"
        let client = TamaClient(command: TamaCommand(
            executable: executable, root: nil,
            environment: [
                "HOME": provider.deletingLastPathComponent().path,
                "TAMA_MODEL_PROVIDER_PATH": provider.path
            ]
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: executable.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: provider.path))
        do {
            _ = try await client.document(operation, describing: "Read the review declaration")
            XCTFail("A missing native executable must not become a successful document")
        } catch let error as TamaBackendError {
            try JSONSerialization.data(withJSONObject: [
                "operation": operation, "executable": executable.path,
                "diagnostic": error.localizedDescription
            ], options: [.prettyPrinted, .sortedKeys])
                .write(to: root.appendingPathComponent("startup-refusal.json"))
            guard case .startFailed(let cause) = error else {
                return XCTFail("Expected the real process launch refusal, observed: \(error)")
            }
            XCTAssertTrue(cause.contains(operation), cause)
            XCTAssertTrue(cause.contains(executable.path), cause)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: executable.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: provider.path))
    }

    func testUnencodableRequestNamesOperationAndPreservesDeclaration() async throws {
        let (client, root, provider) = try fixture()
        let selected: ProviderChoice = try await client.request(
            "model-provider/set", body: ["none": true], as: ProviderChoice.self,
            describing: "Select an independent review declaration")
        XCTAssertEqual(selected.provider, "none")
        let before = try Data(contentsOf: provider)
        do {
            let _: ProviderChoice = try await client.request(
                "model-provider/set", body: ["none": Double.nan], as: ProviderChoice.self,
                describing: "Set the review declaration")
            XCTFail("A non-JSON request body must not reach the backend as a declaration")
        } catch let error as TamaBackendError {
            try Data(error.localizedDescription.utf8)
                .write(to: root.appendingPathComponent("encoding-refusal.txt"))
            guard case .startFailed(let cause) = error else {
                return XCTFail("Expected native request encoding refusal, observed: \(error)")
            }
            XCTAssertTrue(cause.contains("model-provider/set"), cause)
            XCTAssertTrue(cause.contains("request body cannot be encoded"), cause)
        }
        XCTAssertEqual(try Data(contentsOf: provider), before)
        let current: ProviderChoice = try await client.request(
            "model-provider", as: ProviderChoice.self,
            describing: "Read the unchanged review declaration")
        XCTAssertEqual(current.provider, selected.provider)
    }
}
