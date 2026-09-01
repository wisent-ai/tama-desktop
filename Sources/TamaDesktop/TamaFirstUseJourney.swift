import Foundation
import SwiftUI
import WisentDesignSystem
import WisentOnboarding

@MainActor
final class TamaFirstUseJourney: ObservableObject {
    @Published private(set) var currentScreen: JourneyScreen?
    @Published private(set) var status: JourneyProgressStatus = .inProgress
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var isReplaying = false

    private var client: JourneyClient?
    private var hasStarted = false
    private let evidenceRevision = "tama-first-use-2026-08-04"

    var isAtSetup: Bool { currentScreen?.screenKind == "setup_handoff" }
    var isCompleted: Bool { status == .completed }
    var isAwaitingFirstSession: Bool { currentScreen?.screenKind == "first_success" && !isCompleted }

    /// The walkthrough owns the screens ahead of the setup handoff — the ones a
    /// first run put on screen before it handed over to the shell — so it closes
    /// by itself once the journey moves past them, exactly as the first-run gate
    /// used to drop it.
    var isPresentingWalkthrough: Bool {
        isReplaying && !isAtSetup && currentScreen?.transitions.isEmpty == false
    }

    var currentTitle: String {
        currentScreen?.presentation.text("title") ?? currentScreen?.titleKey ?? "Observe one supervised session"
    }
    var currentBody: String {
        currentScreen?.presentation.text("body") ?? currentScreen?.bodyKey ?? ""
    }

    func start() async {
        guard client == nil else { return }
        do {
            let client = try Self.makeClient()
            self.client = client
            let (_, progress) = try await client.start(evidenceRevision: evidenceRevision)
            hasStarted = true
            currentScreen = await client.currentScreen
            status = progress.status
            try? await client.flush()
        } catch {
            errorMessage = "Tama could not load its signed first-use journey. \(error.localizedDescription)"
        }
        isLoading = false
    }

    /// Settings asking for the first-use journey a second time.
    ///
    /// Tama gates its first run on `tama.hasCompletedSetup`, and nothing ever
    /// turned that back off, so the walkthrough was readable exactly once per
    /// machine. The attempt is reset through the same client that recorded it —
    /// Echo sees one `onboarding_reset` for this subject, not a second parallel
    /// attempt — and the walkthrough goes back on screen in this session rather
    /// than waiting for a launch that would not show it either. The failure is
    /// thrown instead of being folded into `errorMessage`, because the settings
    /// row states it where the operator pressed.
    func showWalkthroughAgain() async throws {
        let client: JourneyClient
        if let existing = self.client {
            client = existing
        } else {
            client = try Self.makeClient()
            self.client = client
        }
        if !hasStarted {
            _ = try await client.start(evidenceRevision: evidenceRevision)
            hasStarted = true
        }
        try await client.reset(evidenceRevision: evidenceRevision)
        errorMessage = nil
        isReplaying = true
        await refresh()
    }

    private static func makeClient() throws -> JourneyClient {
        guard let url = Bundle.main.url(
            forResource: "tama-first-use",
            withExtension: "json"
        ) ?? Bundle.module.url(
            forResource: "tama-first-use",
            withExtension: "json"
        ) else {
            throw JourneyClientError.storage
        }
        let fallback = try JourneyRouter.makeBundle(
            canonicalDefinition: String(contentsOf: url, encoding: .utf8),
            journeyVersionId: UUID(uuidString: "11000000-0000-4000-8000-000000000003")!
        )
        return try JourneyClient(
            productId: "tama",
            journeyId: "first-use",
            subjectHash: JourneySubject.scoped([
                NSUserName(),
                Host.current().localizedName ?? "unknown-host",
                "tama-first-use",
            ]),
            scope: .device,
            transport: EnvironmentJourneyTransport(
                tokenEnvironmentKey: "TAMA_STADO_INTEGRATION_TOKEN"
            ),
            storage: UserDefaultsJourneyStorage(namespace: "tama.onboarding.v1"),
            fallback: fallback
        )
    }

    func dismissError() {
        errorMessage = nil
    }

    func expose() async {
        try? await client?.expose(evidenceRevision: evidenceRevision)
    }

    func advance() async {
        guard let client else { return }
        do {
            guard try await client.advance(
                evidence: [:],
                evidenceRevision: evidenceRevision
            ) != nil else { return }
            await refresh()
        } catch {
            errorMessage = "The published journey could not advance. \(error.localizedDescription)"
        }
    }

    func skipExplanation() async {
        guard let client else { return }
        do {
            try await client.skip(evidenceRevision: evidenceRevision)
            while let screen = await client.currentScreen, !screen.transitions.isEmpty {
                guard try await client.advance(
                    evidence: [:],
                    evidenceRevision: evidenceRevision
                ) != nil else { break }
            }
            try await client.resume(evidenceRevision: evidenceRevision)
            await refresh()
        } catch {
            errorMessage = "Tama could not preserve the skipped journey. \(error.localizedDescription)"
        }
    }

    func reconcileCompletedSetup() async {
        guard let client else { return }
        do {
            while let screen = await client.currentScreen,
                  screen.screenKind != "setup_handoff",
                  !screen.transitions.isEmpty {
                guard try await client.advance(
                    evidence: [:],
                    evidenceRevision: evidenceRevision
                ) != nil else { return }
            }
            if await client.currentScreen?.screenKind == "setup_handoff" {
                _ = try await client.advance(
                    evidence: ["visible_matching_setup": .boolean(true)],
                    evidenceRevision: evidenceRevision
                )
            }
            await refresh()
        } catch {
            errorMessage = "Tama could not reconcile the existing setup. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func completeSetup() async -> Bool {
        guard let client else { return false }
        do {
            let advanced = try await client.advance(
                evidence: ["visible_matching_setup": .boolean(true)],
                evidenceRevision: evidenceRevision
            ) != nil
            await refresh()
            return advanced && isAwaitingFirstSession
        } catch {
            errorMessage = "Tama could not record the verified setup handoff. \(error.localizedDescription)"
            return false
        }
    }

    func observeSupervisedSession() async {
        guard let client, isAwaitingFirstSession else { return }
        do {
            _ = try await client.complete(
                evidence: ["supervised_session_observed": .boolean(true)],
                evidenceRevision: evidenceRevision
            )
            await refresh()
        } catch {
            errorMessage = "Tama observed the session but could not record first success. \(error.localizedDescription)"
        }
    }

    private func refresh() async {
        guard let client else { return }
        currentScreen = await client.currentScreen
        status = await client.progress?.status ?? .inProgress
    }
}

struct TamaOnboardingView: View {
    @ObservedObject var journey: TamaFirstUseJourney

    static let maximumWidth: CGFloat = 820

    var body: some View {
        ZStack {
            WisentCanvasBackground()

            VStack(alignment: .leading, spacing: WisentDesign.Space.x5) {
                // Onboarding is the second of the two places a hero header is
                // allowed: the operator has nothing else on screen to read.
                WisentPanel(padding: WisentDesign.Space.x8) {
                    VStack(alignment: .leading, spacing: WisentDesign.Space.x6) {
                        WisentPageHeader(
                            eyebrow: "Policy control",
                            title: journey.currentScreen.flatMap {
                                $0.presentation.text("title")
                            } ?? journey.currentScreen?.titleKey ?? "Welcome to Tama",
                            detail: journey.currentScreen.flatMap {
                                $0.presentation.text("body")
                            } ?? journey.currentScreen?.bodyKey ?? "Prepare local policy enforcement for your coding agents.",
                            symbol: "checkmark.shield.fill"
                        )

                        Divider()

                        HStack(spacing: WisentDesign.Space.x3) {
                            Button("Skip Explanation") {
                                Task { await journey.skipExplanation() }
                            }
                            .buttonStyle(WisentSecondaryButtonStyle())

                            Spacer()

                            Button("Continue") {
                                Task { await journey.advance() }
                            }
                            .buttonStyle(WisentPrimaryButtonStyle())
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                }
                // A journey that will not load is a failure of this screen, so
                // it is stated on it rather than in a modal that leaves nothing
                // behind.
                if let errorMessage = journey.errorMessage {
                    WisentAlertPanel(
                        tone: .danger,
                        title: "Onboarding is unavailable",
                        detail: errorMessage,
                                                actions: [
                            WisentAction("Dismiss", kind: .secondary) {
                                journey.dismissError()
                            }
                        ]
                    )
                }
            }
            .frame(maxWidth: Self.maximumWidth)
            .padding(WisentDesign.Space.x8)
        }
        .task(id: journey.currentScreen?.screenId) {
            await journey.expose()
        }
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func text(_ key: String) -> String? {
        guard case let .string(value)? = self[key] else { return nil }
        return value
    }
}
