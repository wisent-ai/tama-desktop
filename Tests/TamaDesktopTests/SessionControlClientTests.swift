import Darwin
import Foundation
import Testing
@testable import TamaDesktop

struct SessionControlClientTests {
    @Test
    func discoversAndControlsMultipleProviders() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let now = Date()
        try writeSession(
            root: root,
            provider: "omp",
            sessionId: "omp-session",
            controlKey: String(repeating: "a", count: 64),
            pid: Int32(getpid()),
            livenessMode: "process",
            updatedAt: now
        )
        try writeSession(
            root: root,
            provider: "claude",
            sessionId: "claude-session",
            controlKey: String(repeating: "b", count: 64),
            pid: 0,
            livenessMode: "heartbeat",
            updatedAt: now
        )
        try writeSession(
            root: root,
            provider: "codex",
            sessionId: "codex-session",
            controlKey: String(repeating: "c", count: 64),
            pid: 0,
            livenessMode: "heartbeat",
            updatedAt: now
        )

        let client = SessionControlClient(root: root)
        let sessions = try client.liveSessions(now: now)
        #expect(sessions.map(\.provider) == ["claude", "codex", "omp"])
        #expect(Set(sessions.map(\.id)) == [
            "claude:claude-session",
            "codex:codex-session",
            "omp:omp-session",
        ])

        let claude = try #require(sessions.first(where: { $0.provider == "claude" }))
        let updated = try client.setHookEnabled(
            true,
            hookId: "block-temporary-path-operations",
            session: claude,
            globallyDisabled: true
        )
        #expect(updated.enabledHookIds == ["block-temporary-path-operations"])
        #expect(updated.capability?.expiresAt == "approved-expiration")
        let overrideURL = root.appendingPathComponent("\(claude.controlKey).override.json")
        let value = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: overrideURL)) as? [String: Any]
        )
        #expect(value["provider"] as? String == "claude")
        #expect(value["sessionId"] as? String == "claude-session")
        #expect(value["enabledHookIds"] as? [String] == ["block-temporary-path-operations"])
        let preservedCapability = try #require(value["capability"] as? [String: Any])
        #expect(preservedCapability["expiresAt"] as? String == "approved-expiration")

        let allEnabled = try client.setAllHooksEnabled(
            ["check-speculation", "block-temporary-path-operations"],
            session: updated,
            globallyDisabled: true
        )
        #expect(allEnabled.disabledHookIds.isEmpty)
        #expect(allEnabled.enabledHookIds == [
            "block-temporary-path-operations",
            "check-speculation",
        ])

        let oneDisabled = try client.setHookEnabled(
            false,
            hookId: "check-speculation",
            session: allEnabled,
            globallyDisabled: false
        )
        #expect(oneDisabled.disabledHookIds == ["check-speculation"])
        let allEnabledUnderNormalPolicy = try client.setAllHooksEnabled(
            ["check-speculation", "block-temporary-path-operations"],
            session: oneDisabled,
            globallyDisabled: false
        )
        #expect(allEnabledUnderNormalPolicy.disabledHookIds.isEmpty)
        #expect(allEnabledUnderNormalPolicy.enabledHookIds.isEmpty)
    }

    private func writeSession(
        root: URL,
        provider: String,
        sessionId: String,
        controlKey: String,
        pid: Int32,
        livenessMode: String,
        updatedAt: Date
    ) throws {
        var value: [String: Any] = [
            "schema": "ai.wisent.tama.session-control.v1",
            "provider": provider,
            "sessionId": sessionId,
            "controlKey": controlKey,
            "pid": pid,
            "cwd": "/tmp/\(provider)-project",
            "livenessMode": livenessMode,
            "heartbeatTTLSeconds": 900,
            "globallyDisabled": true,
            "disabledHookIds": [],
            "enabledHookIds": [],
            "updatedAt": ISO8601DateFormatter().string(from: updatedAt),
        ]
        if provider == "claude" {
            value["capability"] = [
                "schemaVersion": 1,
                "issuedBy": "test-user-approval",
                "nonce": "test-nonce",
                "sessionId": sessionId,
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
