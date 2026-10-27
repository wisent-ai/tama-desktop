import AppKit
import SwiftUI
import WisentDesignSystem

/// The shell: one sidebar of decisions, one screen at a time.
///
/// The baseline shipped two divergent shells — a control shell and a read-only
/// shell whose sidebar mapped `justifications` and `violations` back onto
/// Overview, so the same tag showed different content depending on how the
/// window had been opened. There is one shell here; authorization removes
/// destinations instead of quietly rewriting them.
struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var violations: ViolationsModel
    @ObservedObject var journey: TamaFirstUseJourney
    let continueToSignIn: (() -> Void)?

    @StateObject private var inspection = InspectionModel()
    @StateObject private var worktrees = WorktreesModel()
    @StateObject private var copies = CopiesModel()
    @StateObject private var contributions = ContributionsModel()
    @StateObject private var reviews = ReviewsModel()
    @State var selection: SidebarDestination = .posture

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .toolbar { toolbarContent }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(
            minWidth: WisentAppLayout.minimumWindowWidth,
            minHeight: WisentAppLayout.minimumWindowHeight
        )
        .tint(WisentDesign.brand)
        .overlay {
            if journey.isPresentingWalkthrough {
                TamaOnboardingView(journey: journey, model: model)
            }
        }
        .onAppear { model.startControlMonitoring() }
        .onDisappear {
            model.stopControlMonitoring()
            violations.cancelAllOperations()
        }
    }

    /// Stated once, in the one place on screen from every destination. The
    /// baseline repeated the boundary on three screens, which is how a boundary
    /// turns into wallpaper.
    var boundaryFooter: some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
            Divider()
            // Read-only inspection monitors nothing local, so it says so rather
            // than reporting a policy state it never read. The badge is also the
            // way back to a signed-in window.
            if model.allowsControl {
                Button {
                    selection = .posture
                } label: {
                    WisentBadge(
                        protectionBadge,
                        symbol: model.areHooksDisabled
                            ? "exclamationmark.octagon.fill"
                            : "checkmark.shield.fill",
                        tone: model.areHooksDisabled ? .danger : .success
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, WisentDesign.Space.x4)
            } else {
                Button {
                    continueToSignIn?()
                } label: {
                    WisentBadge(
                        "Repository inspection",
                        symbol: "eye.fill",
                        tone: .neutral
                    )
                }
                .buttonStyle(.plain)
                .disabled(continueToSignIn == nil)
                .help("Sign in to monitor sessions and change local policy")
                .padding(.horizontal, WisentDesign.Space.x4)
            }
        }
        .padding(.bottom, WisentDesign.Space.x4)
        .accessibilityElement(children: .contain)
    }

    private var protectionBadge: String {
        switch model.hooksDisabledState {
        case true?: "Emergency bypass"
        case false?: "Policy active"
        case nil: "Protection unreadable"
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .posture:
            PostureView(model: model, onNavigate: { selection = $0 })
        case .hooks:
            HooksView(model: model)
        case .session:
            SessionView(model: model)
        case .standing:
            StandingView()
        case .violations:
            ViolationsView(model: violations, hasScope: !violations.repoPath.isEmpty)
        case .worktrees:
            WorktreesView(model: worktrees)
        case .copies:
            CopiesView(model: copies)
        case .contributions:
            ContributionsView(model: contributions)
        case .reviews:
            ReviewsView(model: reviews)
        case .builds:
            BuildsView()
        case .learning:
            LearningView()
        case .justifications:
            if let snapshot = model.snapshot {
                JustificationsView(
                    collections: snapshot.justifications,
                    isRefreshing: model.isRefreshing
                )
            } else {
                WisentEmptyPanel(
                    title: "Policy not read",
                    detail: "Justifications are read with the policy snapshot; refresh the policy to read them.",
                    symbol: "text.badge.checkmark"
                )
            }
        case .coverage:
            CoverageView(inspection: inspection)
        case .installPlan:
            InstallPlanView(inspection: inspection)
        case .settings:
            SettingsView(
                model: model,
                journey: journey,
                continueToSignIn: continueToSignIn
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await model.refresh() }
            } label: {
                Label("Refresh Policy", systemImage: "arrow.clockwise")
            }
            .disabled(model.isRefreshing)
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh policy and justifications")
        }
    }
}
