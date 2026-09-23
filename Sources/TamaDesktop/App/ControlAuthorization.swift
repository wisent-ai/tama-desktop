import AppKit
import Combine
import Foundation
import WisentAuth
import WisentDesignSystem

struct ControlAuthorization: Sendable {
    private static let acceptedRoles: Set<String> = [
        "owner",
        "admin",
        "member",
    ]

    init?(identity: WisentIdentity) {
        guard Self.acceptedRoles.contains(identity.organization.role) else {
            return nil
        }
    }
}
