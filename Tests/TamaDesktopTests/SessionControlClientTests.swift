import Darwin
import Foundation
import Testing
@testable import TamaDesktop

struct SessionControlClientTests {
    @Test
    func discoversAndControlsMultipleProviders() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let now = Date()
        try writeSession(
            root: root,
            agentId: "omp",
            sessionId: "omp-session",
            controlKey: String(repeating: "a", count: 64),
            pid: Int32(getpid()),
            livenessMode: "process",
            updatedAt: now
        )
        try writeSession(
            root: root,
            agentId: "claude",
            sessionId: "claude-session",
            controlKey: String(repeating: "b", count: 64),
            pid: 0,
            livenessMode: "heartbeat",
            updatedAt: now
        )
        try writeSession(
            root: root,
            agentId: "codex",
            sessionId: "codex-session",
            controlKey: String(repeating: "c", count: 64),
            pid: 0,
            livenessMode: "heartbeat",
            updatedAt: now
        )

        let client = SessionControlClient(root: root)
        let sessions = try client.liveSessions(now: now)
        #expect(sessions.map(\.agentId) == ["claude", "codex", "omp"])
        #expect(Set(sessions.map(\.id)) == [
            "claude:claude-session",
            "codex:codex-session",
            "omp:omp-session",
        ])

        let claude = try #require(sessions.first(where: { $0.agentId == "claude" }))
        let hookResponder = respondToNextRequest(
            root: root,
            session: claude,
            expectedOperation: "set-hook",
            expectedHookId: "block-temporary-path-operations",
            globallyDisabled: true,
            enabledHookIds: ["block-temporary-path-operations"]
        )
        let updated = try client.enableHook(
            "block-temporary-path-operations",
            session: claude
        )
        try await hookResponder.value
        #expect(updated.enabledHookIds == ["block-temporary-path-operations"])
        #expect(updated.capability?.expiresAt == "approved-expiration")

        let allResponder = respondToNextRequest(
            root: root,
            session: claude,
            expectedOperation: "enable-all",
            globallyDisabled: false,
            enabledHookIds: []
        )
        let allEnabled = try client.setAllHooksEnabled(session: updated)
        try await allResponder.value
        #expect(!allEnabled.globallyDisabled)
        #expect(allEnabled.disabledHookIds.isEmpty)
        #expect(allEnabled.enabledHookIds.isEmpty)
    }

    private enum FixtureError: Error {
        case invalidRequest
        case requestTimedOut
    }

    private func respondToNextRequest(
        root: URL,
        session: AgentSessionRecord,
        expectedOperation: String,
        expectedHookId: String? = nil,
        globallyDisabled: Bool,
        enabledHookIds: [String]
    ) -> Task<Void, Error> {
        Task.detached {
            let manager = FileManager.default
            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline {
                let urls = try manager.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: nil
                )
                if let requestURL = urls.first(where: {
                    $0.lastPathComponent.hasPrefix("\(session.controlKey).")
                        && $0.lastPathComponent.hasSuffix(".request.json")
                }) {
                    let request = try JSONSerialization.jsonObject(
                        with: Data(contentsOf: requestURL)
                    ) as? [String: Any]
                    guard
                        request?["schema"] as? String == session.schema,
                        request?["sessionId"] as? String == session.sessionId,
                        request?["controlKey"] as? String == session.controlKey,
                        request?["confirmed"] as? Bool == true,
                        request?["operation"] as? String == expectedOperation,
                        request?["hookId"] as? String == expectedHookId,
                        let requestId = request?["requestId"] as? String
                    else {
                        throw FixtureError.invalidRequest
                    }
                    var state = try JSONSerialization.jsonObject(
                        with: Data(contentsOf: root.appendingPathComponent(
                            "\(session.controlKey).session.json"
                        ))
                    ) as! [String: Any]
                    state["globallyDisabled"] = globallyDisabled
                    state["disabledHookIds"] = [String]()
                    state["enabledHookIds"] = enabledHookIds
                    state["updatedAt"] = ISO8601DateFormatter().string(from: Date())
                    let response: [String: Any] = [
                        "schema": session.schema,
                        "requestId": requestId,
                        "ok": true,
                        "state": state,
                    ]
                    let responseURL = root.appendingPathComponent(
                        "\(session.controlKey).\(requestId).response.json"
                    )
                    try JSONSerialization.data(withJSONObject: response)
                        .write(to: responseURL, options: .atomic)
                    return
                }
                try await Task.sleep(for: .milliseconds(10))
            }
            throw FixtureError.requestTimedOut
        }
    }

    private func writeSession(
        root: URL,
        agentId: String,
        sessionId: String,
        controlKey: String,
        pid: Int32,
        livenessMode: String,
        updatedAt: Date
    ) throws {
        var value: [String: Any] = [
            "schema": "ai.wisent.tama.session-control.v2",
            "agentId": agentId,
            "sessionId": sessionId,
            "controlKey": controlKey,
            "pid": pid,
            "cwd": "/tmp/\(agentId)-project",
            "livenessMode": livenessMode,
            "heartbeatTTLSeconds": 900,
            "globallyDisabled": true,
            "disabledHookIds": [],
            "enabledHookIds": [],
            "updatedAt": ISO8601DateFormatter().string(from: updatedAt),
        ]
        if agentId == "claude" {
            value["capability"] = [
                "schemaVersion": 1,
                "issuedBy": "test-user-approval",
                "nonce": "test-nonce",
                "sessionId": sessionId,
                "controlKey": controlKey,
                "releaseId": "test-release",
                "catalogChecksum": "test-checksum",
                "lifetime": "test-lifetime",
                "expiresAt": "approved-expiration",
                "grants": [
                    [
                        "tool": "write",
                        "actions": ["edit"],
                    ],
                ],
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: value)
        try data.write(
            to: root.appendingPathComponent("\(controlKey).session.json"),
            options: .atomic
        )
    }
}
