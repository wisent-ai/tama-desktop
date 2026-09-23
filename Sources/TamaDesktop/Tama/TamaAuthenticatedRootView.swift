import AppKit
import SwiftUI
import WisentAuth
import WisentDesktopUpdate
import WisentDesignSystem

struct TamaAuthenticatedRootView: View {
    @StateObject private var model: AppModel
    @StateObject private var violations: ViolationsModel
    @AppStorage("tama.hasCompletedSetup") private var hasCompletedSetup = false
    @StateObject private var firstUseJourney = TamaFirstUseJourney()
    let bypassesSetup: Bool

    init(authorization: ControlAuthorization, bypassesSetup: Bool) {
        _model = StateObject(
            wrappedValue: AppModel(authorization: authorization)
        )
        _violations = StateObject(
            wrappedValue: ViolationsModel(authorization: authorization)
        )
        self.bypassesSetup = bypassesSetup
    }

    var body: some View {
        Group {
            if bypassesSetup || hasCompletedSetup {
                RootView(
                    model: model,
                    violations: violations,
                    journey: firstUseJourney,
                    continueToSignIn: nil
                )
                    .overlay(alignment: .bottom) {
                        if firstUseJourney.isAwaitingFirstSession {
                            firstSessionHint
                        }
                    }
            } else if firstUseJourney.isLoading {
                ZStack {
                    WisentCanvasBackground()
                    // The onboarding card that lands here: eyebrow, title, two
                    // lines of detail, then the skip and continue buttons.
                    WisentSkeletonGroup(
                        label: "Loading setup",
                        spacing: WisentDesign.Space.x4
                    ) {
                        WisentSkeleton(.pill, width: 96)
                        WisentSkeleton(.heading, width: 340)
                        WisentSkeleton(.line)
                        WisentSkeleton(.line, width: 420)
                        HStack(spacing: WisentDesign.Space.x3) {
                            WisentSkeleton(.pill, width: 150)
                            Spacer(minLength: 0)
                            WisentSkeleton(.pill, width: 110)
                        }
                    }
                    // The canvas is the design system's own ramp, the same
                    // surface every other screen puts skeletons on, so the
                    // automatic tone already tracks light and dark here.
                    .frame(maxWidth: 520)
                    .padding(WisentDesign.Space.x6)
                }
            } else {
                RootView(
                    model: model,
                    violations: violations,
                    journey: firstUseJourney,
                    continueToSignIn: nil
                )
                    .task(id: firstUseJourney.currentScreen?.screenId) {
                        guard firstUseJourney.isAtSetup,
                              await firstUseJourney.completeSetup() else { return }
                        hasCompletedSetup = true
                    }
                    .overlay(alignment: .bottom) {
                        if firstUseJourney.isAwaitingFirstSession {
                            firstSessionHint
                        }
                    }
            }
        }
        .task {
            await firstUseJourney.start()
            if hasCompletedSetup && !firstUseJourney.isCompleted {
                await firstUseJourney.reconcileCompletedSetup()
            }
            if !model.agentSessions.isEmpty {
                await firstUseJourney.observeSupervisedSession()
            }
        }
        .onChange(of: model.agentSessions.isEmpty) { _, isEmpty in
            guard !isEmpty else { return }
            Task { await firstUseJourney.observeSupervisedSession() }
        }
        .onAppear {
            model.startControlMonitoring()
        }
        .onDisappear {
            model.stopControlMonitoring()
            violations.cancelAllOperations()
        }
    }

    /// Waiting for the first supervised session is not a fault, so it is a quiet
    /// strip at the foot of the window rather than an alert.
    private var firstSessionHint: some View {
        HStack(spacing: WisentDesign.Space.x3) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WisentDesign.brand)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                Text(firstUseJourney.currentTitle)
                    .font(WisentTypeScale.bodyStrong())
                    .foregroundStyle(WisentDesign.ink)
                Text(firstUseJourney.currentBody)
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(WisentDesign.Space.x4)
        .frame(maxWidth: TamaOnboardingView.maximumWidth)
        .background(
            WisentDesign.surface,
            in: RoundedRectangle(cornerRadius: WisentDesign.Radius.medium)
        )
        .overlay {
            RoundedRectangle(cornerRadius: WisentDesign.Radius.medium)
                .stroke(WisentDesign.border, lineWidth: WisentDesign.hairline)
        }
        .padding(WisentDesign.Space.x4)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}
