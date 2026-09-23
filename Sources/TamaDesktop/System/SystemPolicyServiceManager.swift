import AppKit
@preconcurrency import NetworkExtension
import ServiceManagement
import SystemExtensions

private let networkFilterIdentifier = "ai.wisent.tama.network-filter"

private final class NetworkExtensionActivator: NSObject, OSSystemExtensionRequestDelegate {
    private var continuation: CheckedContinuation<OSSystemExtensionRequest.Result, Error>?
    private var installationContinuation: CheckedContinuation<Bool, Error>?

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

    func deactivate() async throws -> OSSystemExtensionRequest.Result {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = OSSystemExtensionRequest.deactivationRequest(
                forExtensionWithIdentifier: networkFilterIdentifier,
                queue: .main
            )
            request.delegate = self
            OSSystemExtensionManager.shared.submitRequest(request)
        }
    }
    func isInstalled() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            installationContinuation = continuation
            let request = OSSystemExtensionRequest.propertiesRequest(
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
        foundProperties properties: [OSSystemExtensionProperties]
    ) {
        installationContinuation?.resume(returning: !properties.isEmpty)
        installationContinuation = nil
    }

    func request(
        _ request: OSSystemExtensionRequest,
        didFinishWithResult result: OSSystemExtensionRequest.Result
    ) {
        continuation?.resume(returning: result)
        continuation = nil
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        if let continuation {
            continuation.resume(throwing: error)
            self.continuation = nil
        } else {
            installationContinuation?.resume(throwing: error)
            installationContinuation = nil
        }
    }
}

struct SystemPolicyServiceManager: Sendable {
    private static let plistName = "ai.wisent.tama.system-policy.plist"

    func status() async -> String {
        let daemon = SMAppService.daemon(plistName: Self.plistName)
        let daemonStatus = Self.label(for: daemon.status)
        var systemExtensionInstalled = false
        var systemExtensionStatusError: String?
        do {
            systemExtensionInstalled = try await NetworkExtensionActivator().isInstalled()
        } catch {
            systemExtensionStatusError = error.localizedDescription
        }
        do {
            let manager = NEFilterManager.shared()
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                manager.loadFromPreferences { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
            if daemon.status == .enabled {
                if let systemExtensionStatusError {
                    return "System Extension status unavailable: \(systemExtensionStatusError)"
                }
                guard systemExtensionInstalled else {
                    return "Partial setup: daemon enabled; System Extension not installed"
                }
                return manager.isEnabled
                    ? "Enabled"
                    : "Network filter requires approval"
            }
            if manager.isEnabled
                || manager.providerConfiguration != nil
                || systemExtensionInstalled {
                return "Partial setup: \(daemonStatus); network policy remains configured"
            }
            if let systemExtensionStatusError {
                return "\(daemonStatus); System Extension status unavailable: \(systemExtensionStatusError)"
            }
            return daemonStatus
        } catch {
            let extensionDetail = systemExtensionStatusError.map {
                "; System Extension status unavailable: \($0)"
            } ?? ""
            return "\(daemonStatus); network status unavailable: \(error.localizedDescription)\(extensionDetail)"
        }
    }

    func register() async throws -> String {
        let daemon = SMAppService.daemon(plistName: Self.plistName)
        switch daemon.status {
        case .notFound, .notRegistered:
            try daemon.register()
        case .enabled, .requiresApproval:
            break
        @unknown default:
            try daemon.register()
        }
        let activator = NetworkExtensionActivator()
        let activationResult = try await activator.activate()
        try await configureNetworkFilter()
        if activationResult == .willCompleteAfterReboot {
            return "Restart required to finish System Extension activation"
        }
        return await status()
    }

    func unregister() async throws -> String {
        var failures: [String] = []
        var restartRequired = false

        do {
            let manager = NEFilterManager.shared()
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                manager.loadFromPreferences { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
            if manager.providerConfiguration != nil || manager.isEnabled {
                manager.isEnabled = false
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Void, Error>) in
                    manager.saveToPreferences { error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: ())
                        }
                    }
                }
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Void, Error>) in
                    manager.removeFromPreferences { error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: ())
                        }
                    }
                }
            }
        } catch {
            failures.append("Network filter preferences: \(error.localizedDescription)")
        }

        do {
            let daemon = SMAppService.daemon(plistName: Self.plistName)
            switch daemon.status {
            case .enabled, .requiresApproval:
                try await daemon.unregister()
            case .notFound, .notRegistered:
                break
            @unknown default:
                try await daemon.unregister()
            }
        } catch {
            failures.append("Privileged daemon: \(error.localizedDescription)")
        }

        do {
            let activator = NetworkExtensionActivator()
            if try await activator.isInstalled() {
                restartRequired = try await activator.deactivate()
                    == .willCompleteAfterReboot
            }
        } catch {
            failures.append("System Extension: \(error.localizedDescription)")
        }

        guard failures.isEmpty else {
            throw SystemPolicyServiceError.deactivationFailed(
                failures.joined(separator: "; ")
            )
        }
        if restartRequired {
            return "Restart required to finish System Extension removal"
        }
        return await status()
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
            "Not registered"
        @unknown default:
            "Unknown"
        }
    }
}

private enum SystemPolicyServiceError: LocalizedError {
    case deactivationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .deactivationFailed(message):
            "Tama could not fully deactivate local policy components: \(message)"
        }
    }
}
