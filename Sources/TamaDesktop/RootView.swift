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
    let continueToSignIn: (() -> Void)?

    @StateObject private var inspection = InspectionModel()
    @State private var selection: SidebarDestination = .posture

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
        .onAppear { model.startControlMonitoring() }
        .onDisappear {
            model.stopControlMonitoring()
            violations.cancelAllOperations()
        }
    }

    // MARK: - Sidebar

    /// Rows are `Button`s, not `NavigationLink`s inside a `List`.
    ///
    /// The recorded defect in the sibling application: a click on a `List` row
    /// did not change the destination, and the shell was navigable by keyboard
    /// only. A `Button` carries one unambiguous action.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader
            Divider()
            if model.allowsControl { repositoryScope }
            ScrollView {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
                    ForEach(SidebarDestination.Group.allCases) { group in
                        let destinations = SidebarDestination.destinations(
                            controlEnabled: model.allowsControl,
                            in: group
                        )
                        if !destinations.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.rawValue.uppercased())
                                    .font(WisentTypeScale.eyebrow())
                                    .tracking(0.8)
                                    .foregroundStyle(WisentDesign.muted)
                                    .padding(.horizontal, WisentDesign.Space.x4)
                                    .padding(.bottom, WisentDesign.Space.x1)
                                ForEach(destinations) { destinationRow($0) }
                            }
                        }
                    }
                }
                .padding(.vertical, WisentDesign.Space.x4)
            }
            Spacer(minLength: 0)
            boundaryFooter
        }
        .frame(
            minWidth: WisentAppLayout.sidebarWidth,
            idealWidth: WisentAppLayout.sidebarWidth
        )
        .background(WisentDesign.canvasMuted)
        .navigationSplitViewColumnWidth(
            min: WisentAppLayout.sidebarWidth,
            ideal: WisentAppLayout.sidebarWidth
        )
    }

    private var brandHeader: some View {
        HStack(spacing: WisentDesign.Space.x3) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: WisentDesign.Space.x4, weight: .semibold))
                .foregroundStyle(WisentDesign.brandStrong)
                .frame(width: WisentDesign.Space.x10, height: WisentDesign.Space.x10)
                .background(
                    WisentDesign.brandSoft,
                    in: RoundedRectangle(cornerRadius: WisentDesign.Radius.medium)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                Text("Tama")
                    .font(WisentTypography.heading(17))
                    .foregroundStyle(WisentDesign.ink)
                Text(model.allowsControl ? "AGENT POLICY CONTROL" : "READ-ONLY INSPECTOR")
                    .font(WisentTypography.monoMedium(9))
                    .tracking(0.7)
                    .foregroundStyle(WisentDesign.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(WisentDesign.Space.x4)
    }

    /// The repository under repair is scope, not a destination.
    ///
    /// Violations and its report both read it, and as a text field inside one
    /// screen it left the operator unsure which tree the counts described.
    private var repositoryScope: some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
            Text("REPOSITORY IN VIEW")
                .font(WisentTypography.monoSemibold(8))
                .tracking(0.6)
                .foregroundStyle(WisentDesign.muted)
            HStack(spacing: WisentDesign.Space.x2) {
                Button {
                    chooseRepository()
                } label: {
                    Text(scopeLabel)
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(WisentDesign.ink)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                if !violations.repoPath.isEmpty {
                    Button {
                        violations.resetRepoPath()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(WisentDesign.muted)
                    }
                    .buttonStyle(.plain)
                    .help("Clear the repository scope")
                }
            }
        }
        .padding(WisentDesign.Space.x3)
        .background(
            WisentDesign.surface,
            in: RoundedRectangle(cornerRadius: WisentDesign.Radius.medium)
        )
        .overlay {
            RoundedRectangle(cornerRadius: WisentDesign.Radius.medium)
                .stroke(WisentDesign.border, lineWidth: WisentDesign.hairline)
        }
        .padding(.horizontal, WisentDesign.Space.x3)
        .padding(.vertical, WisentDesign.Space.x3)
        .accessibilityIdentifier("tama.repository-scope")
    }

    private var scopeLabel: String {
        guard !violations.repoPath.isEmpty else { return "Choose a repository" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return violations.repoPath.hasPrefix(home)
            ? "~" + violations.repoPath.dropFirst(home.count)
            : violations.repoPath
    }

    /// A directory chooser, not a free-text field: the scanner refuses a
    /// relative path, a non-repository and a tree owned by somebody else, and
    /// three of those four refusals are avoidable before the command runs.
    private func chooseRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use repository"
        panel.message = "Choose a Git repository you own. Tama scans it read-only."
        if !violations.repoPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: violations.repoPath, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        violations.select(repository: url.path)
    }

    private func destinationRow(_ destination: SidebarDestination) -> some View {
        Button {
            selection = destination
        } label: {
            HStack(spacing: WisentDesign.Space.x3) {
                Image(systemName: destination.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        selection == destination ? WisentDesign.brand : WisentDesign.muted
                    )
                    .frame(width: 16)
                Text(destination.title)
                    .font(
                        selection == destination
                            ? WisentTypography.bodyMedium(13)
                            : WisentTypography.body(13)
                    )
                    .foregroundStyle(
                        selection == destination ? WisentDesign.ink : WisentDesign.secondary
                    )
                Spacer(minLength: WisentDesign.Space.x2)
                indicator(for: destination)
            }
            .padding(.horizontal, WisentDesign.Space.x3)
            .padding(.vertical, WisentDesign.Space.x2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if selection == destination {
                    RoundedRectangle(cornerRadius: WisentDesign.Radius.small)
                        .fill(WisentDesign.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: WisentDesign.Radius.small)
                                .stroke(WisentDesign.border, lineWidth: WisentDesign.hairline)
                        }
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, WisentDesign.Space.x2)
        .accessibilityLabel(destination.title)
        .accessibilityIdentifier("tama.destination.\(destination.rawValue)")
        .accessibilityAddTraits(selection == destination ? [.isSelected] : [])
    }

    /// A count only where it changes what the operator does next, and a fault
    /// glyph only while the fault is live.
    @ViewBuilder
    private func indicator(for destination: SidebarDestination) -> some View {
        switch destination {
        case .violations where violations.hasViolations:
            Text((violations.report?.totals.violations ?? .zero).formatted(.number))
                .font(WisentTypography.monoSemibold(9))
                .foregroundStyle(WisentDesign.warning)
                .monospacedDigit()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(WisentDesign.warning.opacity(0.12), in: Capsule())
        case .session where model.sessionError != nil:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WisentDesign.danger)
                .accessibilityLabel("Session control unavailable")
        case .posture where model.areHooksDisabled:
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WisentDesign.danger)
                .accessibilityLabel("All hooks disabled")
        default:
            EmptyView()
        }
    }

    /// Stated once, in the one place on screen from every destination. The
    /// baseline repeated the boundary on three screens, which is how a boundary
    /// turns into wallpaper.
    private var boundaryFooter: some View {
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
                        model.areHooksDisabled ? "Emergency bypass" : "Policy active",
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
                        "Read-only inspection",
                        symbol: "eye.fill",
                        tone: .neutral
                    )
                }
                .buttonStyle(.plain)
                .disabled(continueToSignIn == nil)
                .help("Sign in to monitor sessions and change local policy")
                .padding(.horizontal, WisentDesign.Space.x4)
            }
            HStack(spacing: WisentDesign.Space.x2) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WisentDesign.brand)
                    .accessibilityHidden(true)
                Text("Bundled snapshot only")
                    .font(WisentTypography.bodyMedium(11))
                    .foregroundStyle(WisentDesign.secondary)
            }
            .padding(.horizontal, WisentDesign.Space.x4)
            Text("Tama reads the catalog snapshot sealed into this build. The app does not import logs, credentials, settings, or caches.")
                .font(WisentTypography.body(10))
                .foregroundStyle(WisentDesign.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, WisentDesign.Space.x4)
                .padding(.bottom, WisentDesign.Space.x4)
        }
        .accessibilityElement(children: .contain)
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
        case .violations:
            ViolationsView(model: violations, hasScope: !violations.repoPath.isEmpty)
        case .justifications:
            JustificationsView(
                collections: model.snapshot?.justifications ?? [],
                isRefreshing: model.isRefreshing
            )
        case .coverage:
            CoverageView(inspection: inspection)
        case .installPlan:
            InstallPlanView(inspection: inspection)
        case .settings:
            SettingsView(model: model, continueToSignIn: continueToSignIn)
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
            .help("Re-read the bundled catalog and the local justification registries")
        }
    }
}
