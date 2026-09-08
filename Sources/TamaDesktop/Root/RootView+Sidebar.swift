import AppKit
import SwiftUI
import WisentDesignSystem

/// The shell's sidebar: the destination rows, the repository scope beside them
/// and the per-destination indicator.
///
/// Moved out of RootView unchanged so that file stays inside the three hundred
/// line limit the operator's own gate enforces and can carry the worktrees
/// destination. Behaviour and member names are unchanged; only the file
/// boundary moves, which is what block-oversized-files asks for when a view
/// outgrows the limit, and the sub-folder is what block-crowded-folders asks
/// for.
extension RootView {
    // MARK: - Sidebar

    /// Rows are `Button`s, not `NavigationLink`s inside a `List`.
    ///
    /// The recorded defect in the sibling application: a click on a `List` row
    /// did not change the destination, and the shell was navigable by keyboard
    /// only. A `Button` carries one unambiguous action.
    var sidebar: some View {
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
        panel.message = "Choose a Git repository owned by your account."
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
                .accessibilityLabel("Policy protection off")
        default:
            EmptyView()
        }
    }

}
