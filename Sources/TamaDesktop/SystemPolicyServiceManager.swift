import AppKit
@preconcurrency import NetworkExtension
import ServiceManagement
import SystemExtensions

private let networkFilterIdentifier = "ai.wisent.tama.network-filter"

private final class NetworkExtensionActivator: NSObject, OSSystemExtensionRequestDelegate {
    private var continuation: CheckedContinuation<OSSystemExtensionRequest.Result, Error>?

    func activate() async throws -> OSSystemExtensionRequest.Result {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = OSSystemExtensionRequest.activationRequest(
                forExtensionWithIdentifier: networkFilterIdentifier,
                queue: .main
            )
            request.delegate = self
            OSSystemExtensionManager.shared.submitRequest(request)
        }
    }

    func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {}

    func request(
        _ request: OSSystemExtensionRequest,
        didFinishWithResult result: OSSystemExtensionRequest.Result
    ) {
        continuation?.resume(returning: result)
        continuation = nil
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

struct SystemPolicyServiceManager: Sendable {
    private static let plistName = "ai.wisent.tama.system-policy.plist"

    func register() async throws -> String {
        let daemon = SMAppService.daemon(plistName: Self.plistName)
        if daemon.status == .notRegistered {
            try daemon.register()
        }
        _ = try await NetworkExtensionActivator().activate()
        try await configureNetworkFilter()
        return daemon.status == .enabled
            ? "Enabled"
            : Self.label(for: daemon.status)
    }

    @MainActor
    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    @MainActor
    func openFullDiskAccessSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func configureNetworkFilter() async throws {
        let manager = NEFilterManager.shared()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.loadFromPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let configuration = manager.providerConfiguration
                    ?? NEFilterProviderConfiguration()
                configuration.filterSockets = true
                configuration.filterPackets = false
                configuration.filterDataProviderBundleIdentifier = networkFilterIdentifier
                manager.providerConfiguration = configuration
                manager.localizedDescription = "Tama supervised-session network policy"
                manager.isEnabled = true
                manager.saveToPreferences { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
        }
    }

    private static func label(for status: SMAppService.Status) -> String {
        switch status {
        case .enabled:
            "Network filter requires approval"
        case .requiresApproval:
            "Requires administrator approval"
        case .notRegistered:
            "Not registered"
        case .notFound:
            "Daemon not found in Tama.app"
        @unknown default:
            "Unknown"
        }
    }
}
