import SwiftUI
import WisentDesignSystem

struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var violationsModel: ViolationsModel
    @State private var isShowingDisableConfirmation = false
    @State private var isShowingEnableConfirmation = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                if model.areHooksDisabled { emergencyBanner }
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background { WisentCanvasBackground() }
            .navigationTitle(contentTitle)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.isChangingHookState {
                    ProgressView().controlSize(.small).accessibilityLabel("Updating installed hooks")
                } else if model.areHooksDisabled {
                    Button {
                        isShowingEnableConfirmation = true
                    } label: {
                        Label("Re-enable all hooks", systemImage: "power.circle.fill")
                    }
                    .help("Restore all Tama-managed hook dispatchers")
                    .disabled(model.isPolicyMutationInProgress)
                } else {
                    Button {
                        isShowingDisableConfirmation = true
                    } label: {
                        Label("Disable all hooks", systemImage: "exclamationmark.octagon.fill")
                    }
                    .help("Emergency bypass for all Tama-managed hooks")
                    .disabled(model.isPolicyMutationInProgress)
                }
                Button("Reveal bundled release", systemImage: "folder") { model.revealHookRelease() }
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                    .disabled(model.isRefreshing)
            }
        }
        .onAppear { model.startControlMonitoring() }
        .onDisappear {
            model.stopControlMonitoring()
            violationsModel.cancelAllOperations()
        }
        .overlay {
            if model.isRefreshing, model.snapshot == nil {
                ProgressView("Loading the Tama catalog…")
                    .font(WisentTypography.bodyMedium(13))
            }
        }
        .confirmationDialog("Disable all hooks?", isPresented: $isShowingDisableConfirmation, titleVisibility: .visible) {
            Button("Disable all hooks", role: .destructive) { model.setHooksDisabled(true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Agent, editor, and Git hook dispatchers will bypass all hooks until you re-enable them.")
        }
        .confirmationDialog("Re-enable every managed hook?", isPresented: $isShowingEnableConfirmation, titleVisibility: .visible) {
            Button("Install approved release and re-enable") { model.setHooksDisabled(false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Tama will integrity-check and install its bundled hook release, restore managed dispatchers, then resume supervised sessions. Blocking policy becomes active again.")
        }
        .alert(
            "Tama couldn’t update hooks",
            isPresented: Binding(
                get: { model.snapshot != nil && model.errorMessage != nil },
                set: { if !$0 { model.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            TamaSidebarBrand(subtitle: "Agent policy control")
            Divider()
            List(selection: $model.selection) {
                Section {
                    sidebarItem(.overview, title: "Overview", symbol: "shield.lefthalf.filled")
                    sidebarItem(.hooks, title: "Hook catalog", symbol: "list.bullet.rectangle")
                    sidebarItem(.justifications, title: "Justifications", symbol: "text.badge.checkmark")
                } header: {
                    sidebarSectionLabel("Policy")
                }
                Section {
                    sidebarItem(.validation, title: "Snapshot validation", symbol: "checkmark.seal")
                    sidebarItem(.repositories, title: "Repository hooks", symbol: "point.3.connected.trianglepath.dotted")
                    sidebarItem(.violations, title: "Violations", symbol: "ladybug")
                } header: {
                    sidebarSectionLabel("Operations")
                }
            }
            .font(WisentTypography.bodyMedium(13))
            .scrollContentBackground(.hidden)
            sidebarStatus
        }
        .background(WisentDesign.canvasMuted)
        .navigationSplitViewColumnWidth(min: WisentDesign.Layout.sidebarMinimumWidth, ideal: WisentDesign.Layout.sidebarIdealWidth)
    }

    private func sidebarItem(_ selection: SidebarSelection, title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .padding(.vertical, WisentDesign.Space.x1)
            .tag(selection)
    }

    private func sidebarSectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(WisentTypography.monoSemibold(10))
            .tracking(0.6)
    }

    private var sidebarStatus: some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
            WisentBadge(
                model.areHooksDisabled ? "Emergency bypass" : "Policy active",
                symbol: model.areHooksDisabled ? "exclamationmark.octagon.fill" : "checkmark.shield.fill",
                tone: model.areHooksDisabled ? .danger : .success
            )
            Text(model.systemPolicyServiceStatus)
                .font(WisentTypography.mono(10))
                .foregroundStyle(WisentDesign.secondary)
        }
        .padding(WisentDesign.Space.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WisentDesign.surface)
        .accessibilityElement(children: .combine)
    }

    private var emergencyBanner: some View {
        HStack(spacing: WisentDesign.Space.x3) {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundStyle(WisentDesign.danger)
            VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                Text("ALL HOOKS DISABLED")
                    .font(WisentTypography.monoSemibold(11))
                    .foregroundStyle(WisentDesign.danger)
                Text("Agent, editor, and Git hook dispatchers are bypassed.")
                    .font(WisentTypography.body(12))
                    .foregroundStyle(WisentDesign.secondary)
            }
            Spacer()
            Button("Re-enable all hooks") { isShowingEnableConfirmation = true }
                .buttonStyle(WisentPrimaryButtonStyle())
                .disabled(model.isPolicyMutationInProgress)
        }
        .padding(.horizontal, WisentDesign.Space.x4)
        .padding(.vertical, WisentDesign.Space.x2)
        .background(WisentTone.danger.softColor)
        .overlay(alignment: .bottom) { Rectangle().fill(WisentDesign.danger.opacity(0.18)).frame(height: WisentDesign.hairline) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("All hooks disabled")
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage = model.errorMessage, model.snapshot == nil {
            WisentEmptyState(title: "Catalog unavailable", detail: errorMessage, symbol: "exclamationmark.shield")
        } else if let snapshot = model.snapshot {
            switch model.selection ?? .overview {
            case .overview:
                OverviewView(model: model, snapshot: snapshot, installedHookReleaseID: model.installedHookReleaseID, allowsMutations: true)
            case .hooks:
                HookCatalogPane(model: model, allowsSessionControl: true)
            case .justifications:
                JustificationsView(collections: snapshot.justifications)
            case .validation:
                ValidationView(result: snapshot.validation)
            case .repositories:
                RepositoryHooksView(hooks: snapshot.catalog.repoGitHooks)
            case .violations:
                ViolationsView(model: violationsModel)
            }
        } else {
            WisentEmptyState(title: "Loading policy", detail: "Reading the integrity-sealed Tama catalog.", symbol: "shield")
        }
    }

    private var contentTitle: String {
        switch model.selection ?? .overview {
        case .overview: "Overview"
        case .hooks: "Hook catalog"
        case .justifications: "Justifications"
        case .validation: "Snapshot validation"
        case .repositories: "Repository hooks"
        case .violations: "Violations"
        }
    }
}

struct ReadOnlyRootView: View {
    @StateObject private var model = AppModel(inspectionOnly: true)
    let continueToSignIn: () -> Void
    @State private var selection: SidebarSelection? = .overview

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                TamaSidebarBrand(subtitle: "Read-only policy inspector")
                Divider()
                List(selection: $selection) {
                    Section {
                        Label("Overview", systemImage: "shield.lefthalf.filled").tag(SidebarSelection.overview)
                        Label("Hook catalog", systemImage: "list.bullet.rectangle").tag(SidebarSelection.hooks)
                        Label("Snapshot validation", systemImage: "checkmark.seal").tag(SidebarSelection.validation)
                        Label("Repository hooks", systemImage: "point.3.connected.trianglepath.dotted").tag(SidebarSelection.repositories)
                    } header: {
                        Text("INSPECTION").font(WisentTypography.monoSemibold(10)).tracking(0.6)
                    }
                }
                .font(WisentTypography.bodyMedium(13))
                .scrollContentBackground(.hidden)
                TamaNotice(title: "Read-only mode", detail: "No session monitoring or policy changes.", symbol: "eye.fill", tone: .info)
                    .padding(WisentDesign.Space.x3)
            }
            .background(WisentDesign.canvasMuted)
            .navigationSplitViewColumnWidth(min: WisentDesign.Layout.sidebarMinimumWidth, ideal: WisentDesign.Layout.sidebarIdealWidth)
        } detail: {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { WisentCanvasBackground() }
                .navigationTitle(contentTitle)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Sign in for controls", systemImage: "person.badge.key") { continueToSignIn() }
                Button("Reveal bundled release", systemImage: "folder") { model.revealHookRelease() }
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                    .disabled(model.isRefreshing)
            }
        }
        .overlay {
            if model.isRefreshing, model.snapshot == nil {
                ProgressView("Loading the Tama catalog…").font(WisentTypography.bodyMedium(13))
            }
        }
        .alert(
            "Tama couldn’t load its bundled policy",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage = model.errorMessage, model.snapshot == nil {
            WisentEmptyState(title: "Catalog unavailable", detail: errorMessage, symbol: "exclamationmark.shield")
        } else if let snapshot = model.snapshot {
            switch selection ?? .overview {
            case .overview, .justifications, .violations:
                OverviewView(model: model, snapshot: snapshot, installedHookReleaseID: model.installedHookReleaseID, allowsMutations: false)
            case .hooks:
                HookCatalogPane(model: model, allowsSessionControl: false)
            case .validation:
                ValidationView(result: snapshot.validation)
            case .repositories:
                RepositoryHooksView(hooks: snapshot.catalog.repoGitHooks)
            }
        } else {
            WisentEmptyState(title: "Loading policy", detail: "Reading the integrity-sealed Tama catalog.", symbol: "shield")
        }
    }

    private var contentTitle: String {
        switch selection ?? .overview {
        case .overview, .justifications, .violations: "Overview"
        case .hooks: "Hook catalog"
        case .validation: "Snapshot validation"
        case .repositories: "Repository hooks"
        }
    }
}

private struct HookCatalogPane: View {
    @ObservedObject var model: AppModel
    let allowsSessionControl: Bool

    var body: some View {
        HSplitView {
            HookListView(model: model)
                .frame(minWidth: TamaLayout.catalogListMinimumWidth, idealWidth: TamaLayout.catalogListIdealWidth)
            if let hook = model.selectedHook {
                HookDetailView(model: model, hook: hook, revealSource: model.revealSelectedSource, allowsSessionControl: allowsSessionControl)
                    .frame(maxWidth: .infinity)
            } else {
                ZStack {
                    WisentCanvasBackground()
                    WisentEmptyState(title: "Select a hook", detail: "Choose an approved policy from the catalog to inspect its behavior and source.", symbol: "list.bullet.rectangle")
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct OverviewView: View {
    @ObservedObject var model: AppModel
    let snapshot: CatalogSnapshot
    let installedHookReleaseID: String?
    let allowsMutations: Bool
    @State private var isConfirmingRuntimeInstall = false
    @State private var isConfirmingBackendRegistration = false
    @State private var isConfirmingLocalDeactivation = false

    private var blockingCount: Int { snapshot.catalog.hooks.filter(\.isBlocking).count }
    private var categories: Int { Set(snapshot.catalog.hooks.map(\.category)).count }
    private var buildIdentity: BuildIdentity { .current }

    var body: some View {
        TamaPage {
            WisentPageHeader(
                eyebrow: allowsMutations ? "Policy operations" : "Read-only inspection",
                title: "Tama posture",
                detail: allowsMutations ? "Inspect the approved catalog, local installation, and active enforcement boundary." : "Inspect the bundled policy identity without changing local enforcement.",
                symbol: "shield.lefthalf.filled",
                tone: snapshot.validation.ok ? .success : .danger
            )

            HStack(spacing: WisentDesign.Space.x3) {
                WisentMetricCard(title: "Catalog hooks", value: snapshot.catalog.hooks.count.formatted(), detail: "Approved policies", symbol: "list.bullet.rectangle")
                WisentMetricCard(title: "Blocking hooks", value: blockingCount.formatted(), detail: "Can stop unsafe work", symbol: "hand.raised.fill", tone: .warning)
                WisentMetricCard(title: "Categories", value: categories.formatted(), detail: "Policy domains", symbol: "square.grid.2x2")
            }

            TamaPanelSection("Product build", detail: "Signed application and bundled hook release identity") {
                LabeledContent("Version", value: buildIdentity.productVersion)
                Divider()
                LabeledContent("Channel", value: buildIdentity.channel.capitalized)
                Divider()
                LabeledContent("Source revision") { selectableMono(buildIdentity.displayedRevision) }
                if let hookRelease = buildIdentity.hookRelease {
                    Divider()
                    LabeledContent("Bundled hook release") { selectableMono(hookRelease.releaseId) }
                    Divider()
                    LabeledContent("Hook source revision") { selectableMono(hookRelease.sourceDirty ? "\(hookRelease.sourceRevision) (dirty source)" : hookRelease.sourceRevision) }
                }
                Divider()
                LabeledContent("Target", value: "\(buildIdentity.platform) · \(buildIdentity.architecture)")
                Divider()
                LabeledContent("Built", value: buildIdentity.builtAt)
            }

            if allowsMutations { localSetup }

            TamaPanelSection("Current posture", detail: "Integrity and installation summary") {
                LabeledContent("Snapshot structure") {
                    WisentBadge(snapshot.validation.ok ? "Valid" : "Invalid", symbol: snapshot.validation.ok ? "checkmark.seal.fill" : "xmark.octagon.fill", tone: snapshot.validation.ok ? .success : .danger)
                }
                if allowsMutations {
                    Divider()
                    LabeledContent("Installed hooks", value: installedHookReleaseID.map { String($0.prefix(12)) } ?? "Not installed by Tama")
                }
                Divider()
                LabeledContent("Warnings", value: snapshot.validation.warnings.count.formatted())
                Divider()
                LabeledContent("Errors", value: snapshot.validation.errors.count.formatted())
                Divider()
                LabeledContent("Orphan sources", value: snapshot.catalog.orphanSources.count.formatted())
            }

            TamaNotice(
                title: "Credential-free catalog boundary",
                detail: "Tama displays a catalog snapshot generated from hooks-rotator at build time. Re-enable verifies and installs the integrity-sealed hook release bundled with this build, preserves non-hook settings, updates every managed dispatcher, then restarts and resumes supervised sessions. The app does not import logs, credentials, settings, or caches.",
                symbol: "hand.raised.fill",
                tone: .info
            )
        }
        .confirmationDialog("Install the local Tama runtime?", isPresented: $isConfirmingRuntimeInstall, titleVisibility: .visible) {
            Button("Install runtime") { model.installLocalRuntime() }.disabled(model.isPolicyMutationInProgress)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Tama will verify its bundled hook release, then update managed files under Application Support and the documented per-user agent paths. Existing unrelated settings are preserved.")
        }
        .confirmationDialog("Register privileged macOS policy components?", isPresented: $isConfirmingBackendRegistration, titleVisibility: .visible) {
            Button("Register backend") { Task { await model.installSystemPolicyService() } }.disabled(model.isPolicyMutationInProgress)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("macOS will request approval for Tama's daemon, System Extension, Network filter, and Full Disk Access where required.")
        }
        .confirmationDialog("Deactivate Tama's local policy setup?", isPresented: $isConfirmingLocalDeactivation, titleVisibility: .visible) {
            Button("Disable hooks and unregister backend", role: .destructive) { model.deactivateLocalSetup() }.disabled(model.isPolicyMutationInProgress)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Tama will disable managed hook dispatchers, unregister privileged macOS components, and preserve recovery files. Stop supervised sessions before using this action.")
        }
    }

    private var localSetup: some View {
        TamaPanelSection("Local setup", detail: "Runtime installation and privileged backend") {
            LabeledContent("Local runtime") {
                WisentBadge(installedHookReleaseID == nil ? "Not installed" : "Installed", symbol: installedHookReleaseID == nil ? "shippingbox" : "checkmark.circle.fill", tone: installedHookReleaseID == nil ? .warning : .success)
            }
            if model.isInstallingLocalRuntime {
                ProgressView("Installing integrity-checked runtime…")
            } else {
                Button("Install local runtime") { isConfirmingRuntimeInstall = true }
                    .buttonStyle(WisentPrimaryButtonStyle())
                    .disabled(!snapshot.validation.ok || model.isLocalSetupOperationInProgress)
            }
            if installedHookReleaseID != nil {
                Divider()
                LabeledContent("Node version", value: model.installedNodeVersion ?? "Not recorded")
                LabeledContent("Node executable") { selectableMono(model.installedNodeExecutable ?? "Not recorded") }
            }
            Divider()
            LabeledContent("Privileged backend") {
                WisentBadge(model.systemPolicyServiceStatus, symbol: model.systemPolicyServiceStatus == "Enabled" ? "checkmark.circle.fill" : "lock.shield", tone: model.systemPolicyServiceStatus == "Enabled" ? .success : .warning)
            }
            if model.isRegisteringSystemPolicyService {
                ProgressView("Registering privileged backend…")
            } else if model.systemPolicyServiceStatus != "Enabled" {
                Button("Register privileged backend") { isConfirmingBackendRegistration = true }
                    .buttonStyle(WisentPrimaryButtonStyle())
                    .disabled(model.isLocalSetupOperationInProgress)
            }
            if installedHookReleaseID != nil || model.systemPolicyServiceStatus != "Not registered" {
                Divider()
                if model.isDeactivatingLocalSetup {
                    ProgressView("Deactivating local policy…")
                } else {
                    Button("Deactivate local setup", role: .destructive) { isConfirmingLocalDeactivation = true }
                        .disabled(model.isLocalSetupOperationInProgress)
                }
            }
        }
    }

    private func selectableMono(_ text: String) -> some View {
        Text(text).font(WisentTypography.mono(11)).textSelection(.enabled)
    }
}

private struct HookListView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                Text("POLICY CATALOG")
                    .font(WisentTypography.monoSemibold(10))
                    .tracking(0.6)
                    .foregroundStyle(WisentDesign.muted)
                Picker("Hook filter", selection: $model.hookFilter) {
                    ForEach(HookFilter.allCases) { filter in Text(filter.rawValue).tag(filter) }
                }
                .pickerStyle(.segmented)
            }
            .padding(WisentDesign.Space.x4)
            Divider()
            List(model.filteredHooks, selection: $model.selectedHookID) { hook in
                VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                    HStack(spacing: WisentDesign.Space.x2) {
                        Text(hook.id).font(WisentTypography.bodyMedium(13)).foregroundStyle(WisentDesign.ink)
                        Spacer()
                        if hook.isBlocking { WisentBadge("Blocking", symbol: "hand.raised.fill", tone: .warning) }
                    }
                    Text(hook.category).font(WisentTypography.body(12)).foregroundStyle(WisentDesign.secondary)
                    Text(hook.eventNames).font(WisentTypography.mono(10)).foregroundStyle(WisentDesign.muted).lineLimit(2)
                }
                .padding(.vertical, WisentDesign.Space.x1)
                .tag(hook.id)
            }
            .font(WisentTypography.body(13))
            .searchable(text: $model.searchText, prompt: "Hook, category, or event")
            .overlay {
                if model.filteredHooks.isEmpty {
                    WisentEmptyState(title: "No matching hooks", detail: "Adjust the search or policy filter.", symbol: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .background(WisentDesign.canvasMuted)
    }
}

private struct HookDetailView: View {
    @ObservedObject var model: AppModel
    let hook: HookRecord
    let revealSource: () -> Void
    let allowsSessionControl: Bool

    var body: some View {
        TamaPage {
            HStack(alignment: .top, spacing: WisentDesign.Space.x4) {
                WisentPageHeader(eyebrow: hook.category, title: hook.id, detail: hook.description ?? "Approved hook policy and runtime contract.", symbol: "checkmark.shield.fill", tone: hook.status == "active" ? .success : .warning)
                Spacer()
                VStack(alignment: .trailing, spacing: WisentDesign.Space.x2) {
                    WisentBadge(hook.status.capitalized, symbol: hook.status == "active" ? "checkmark.circle.fill" : "exclamationmark.circle.fill", tone: hook.status == "active" ? .success : .warning)
                    Text(hook.type).font(WisentTypography.mono(10)).foregroundStyle(WisentDesign.muted)
                }
            }
            .textSelection(.enabled)

            if let description = hook.description { detailSection("What it does", text: description) }
            if let why = hook.why { detailSection("Why it exists", text: why) }
            if let sideEffects = hook.sideEffects { detailSection("Side effects", text: sideEffects) }
            if allowsSessionControl { SessionHookControlView(model: model, hook: hook) }

            TamaPanelSection("Events", detail: "Invocation points and blocking behavior") {
                ForEach(Array(hook.events.enumerated()), id: \.element.id) { index, event in
                    if index > 0 { Divider() }
                    HStack(alignment: .top, spacing: WisentDesign.Space.x3) {
                        Image(systemName: event.blocking ? "hand.raised.fill" : "arrow.right.circle")
                            .foregroundStyle(event.blocking ? WisentDesign.warning : WisentDesign.secondary)
                        VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                            Text(event.event).font(WisentTypography.monoMedium(12))
                            Text(event.blocking ? "Blocking" : "Non-blocking").font(WisentTypography.body(11)).foregroundStyle(WisentDesign.secondary)
                        }
                        Spacer()
                        Text("\(event.timeout)s").font(WisentTypography.mono(11)).foregroundStyle(WisentDesign.secondary)
                    }
                }
            }

            TamaPanelSection("Source", detail: "Archived implementation and invocation command") {
                Text(hook.sourcePath ?? "No archived source path").font(WisentTypography.mono(12)).textSelection(.enabled)
                Text(hook.command).font(WisentTypography.mono(10)).foregroundStyle(WisentDesign.secondary).textSelection(.enabled)
                Button("Reveal source", systemImage: "folder") { revealSource() }
                    .buttonStyle(WisentSecondaryButtonStyle())
                    .disabled(hook.sourcePath == nil)
            }
        }
        .navigationTitle("Hook")
    }

    private func detailSection(_ title: String, text: String) -> some View {
        TamaPanelSection(title) {
            Text(text)
                .font(WisentTypography.body(13))
                .foregroundStyle(WisentDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

private struct SessionHookControlView: View {
    @ObservedObject var model: AppModel
    let hook: HookRecord
    @State private var isConfirmingEnableHook = false
    @State private var isConfirmingEnableAll = false
    @State private var isConfirmingBackendRegistration = false

    var body: some View {
        TamaPanelSection("Session control", detail: "Atomic overrides scoped to one supervised coding-agent session") {
            LabeledContent("Privileged backend") {
                WisentBadge(model.systemPolicyServiceStatus, symbol: model.systemPolicyServiceStatus == "Enabled" ? "checkmark.circle.fill" : "lock.shield", tone: model.systemPolicyServiceStatus == "Enabled" ? .success : .warning)
            }
            if model.systemPolicyServiceStatus != "Enabled" {
                HStack(spacing: WisentDesign.Space.x2) {
                    Button("Register backend") { isConfirmingBackendRegistration = true }
                        .buttonStyle(WisentPrimaryButtonStyle())
                        .disabled(model.isPolicyMutationInProgress)
                    Button("Open approval settings") { model.openSystemPolicyApprovalSettings() }
                        .buttonStyle(WisentSecondaryButtonStyle())
                    Button("Open Full Disk Access") { model.openFullDiskAccessSettings() }
                        .buttonStyle(WisentSecondaryButtonStyle())
                }
            }
            if let sessionErrorMessage = model.sessionErrorMessage {
                TamaNotice(title: "Session control unavailable", detail: sessionErrorMessage, symbol: "exclamationmark.triangle.fill", tone: .danger)
                    .textSelection(.enabled)
            }
            if model.agentSessions.isEmpty {
                TamaNotice(title: "No active agent sessions", detail: "Tama refuses to start an agent unless the platform has a ready kernel-enforcement backend. Unsupported platforms must add a real backend and submit a support pull request.", symbol: "terminal", tone: .neutral)
                if let supportURL = URL(string: "https://github.com/wisent-ai/tama-desktop/compare") {
                    Link("Submit platform support pull request", destination: supportURL).font(WisentTypography.bodyMedium(12))
                }
                Button("Refresh sessions", systemImage: "arrow.clockwise") { Task { await model.refreshAgentSessions() } }
                    .buttonStyle(WisentSecondaryButtonStyle())
            } else {
                Picker("Session", selection: $model.selectedAgentSessionID) {
                    ForEach(model.agentSessions) { session in Text(session.displayName).tag(Optional(session.id)) }
                }
                if let session = model.selectedAgentSession,
                   let isEnabled = model.isHookEnabledInSelectedSession(hook.id) {
                    sessionDetails(session, isEnabled: isEnabled)
                }
            }
        }
        .confirmationDialog("Enable this hook?", isPresented: $isConfirmingEnableHook, titleVisibility: .visible) {
            Button("Enable for this session") {
                isConfirmingEnableHook = false
                model.enableSelectedSessionHook(hook.id)
            }.disabled(model.isPolicyMutationInProgress)
            Button("Cancel", role: .cancel) { isConfirmingEnableHook = false }
        } message: {
            Text("This changes only hook \(hook.id) in \(model.selectedAgentSession?.agentDisplayName ?? "agent") session \(model.selectedAgentSession?.sessionId ?? "unknown"). Other sessions are unaffected.")
        }
        .confirmationDialog("Enable every hook and reload this session?", isPresented: $isConfirmingEnableAll, titleVisibility: .visible) {
            Button("Enable all hooks") {
                isConfirmingEnableAll = false
                model.enableAllHooksInSelectedSession()
            }.disabled(model.isPolicyMutationInProgress)
            Button("Cancel", role: .cancel) { isConfirmingEnableAll = false }
        } message: {
            Text("One approved operation enables every registered hook, persists the override only in \(model.selectedAgentSession?.agentDisplayName ?? "agent") session \(model.selectedAgentSession?.sessionId ?? "unknown"). Other sessions are unaffected.")
        }
        .confirmationDialog("Register privileged macOS policy components?", isPresented: $isConfirmingBackendRegistration, titleVisibility: .visible) {
            Button("Register backend") { Task { await model.installSystemPolicyService() } }.disabled(model.isPolicyMutationInProgress)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("macOS will request approval for Tama's daemon, System Extension, Network filter, and Full Disk Access where required.")
        }
    }

    @ViewBuilder
    private func sessionDetails(_ session: AgentSessionRecord, isEnabled: Bool) -> some View {
        LabeledContent("Agent", value: session.agentDisplayName)
        LabeledContent("Session ID") { monoLine(session.sessionId) }
        LabeledContent("Project") { monoLine(session.cwd) }
        if let semanticRuntime = session.semanticRuntime {
            LabeledContent("Semantic events", value: String(semanticRuntime.eventSequence))
            if let lastEvent = semanticRuntime.recentEvents.last { LabeledContent("Last event", value: lastEvent.event) }
        }
        if let systemPolicy = session.systemPolicy {
            LabeledContent("System policy") {
                WisentBadge(systemPolicy.ready ? "Kernel-gated" : "Unavailable", symbol: systemPolicy.ready ? "lock.shield.fill" : "xmark.shield.fill", tone: systemPolicy.ready && systemPolicy.mode == "kernel-gated" ? .success : .danger)
            }
            if let backend = systemPolicy.backend { LabeledContent("Policy backend", value: backend) }
            if !systemPolicy.capabilities.isEmpty { LabeledContent("Backend capabilities", value: systemPolicy.capabilities.joined(separator: ", ")) }
            if let error = systemPolicy.error {
                TamaNotice(title: "System policy error", detail: error, symbol: "xmark.octagon.fill", tone: .danger).textSelection(.enabled)
            }
            if let rawURL = systemPolicy.supportPullRequestURL, let supportURL = URL(string: rawURL) {
                Link("Submit platform support pull request", destination: supportURL).font(WisentTypography.bodyMedium(12))
            }
        } else {
            LabeledContent("System policy") { WisentBadge("Backend status unavailable", symbol: "questionmark.circle", tone: .warning) }
        }
        if let runtime = session.runtime {
            let runtimeHealthy = runtime.registryLoadError == nil && ((runtime.reloadPending ?? false) || !runtime.reloadRequired)
            LabeledContent("Hook runtime") {
                WisentBadge(runtime.registryLoadError != nil ? "Load failed" : ((runtime.reloadPending ?? false) ? "Reload scheduled" : (runtime.reloadRequired ? "Reload required" : "Loaded")), symbol: runtimeHealthy ? "checkmark.circle.fill" : "exclamationmark.circle.fill", tone: runtimeHealthy ? .success : .warning)
            }
            LabeledContent("Release") { monoLine("\(runtime.loadedReleaseId.prefix(12)) loaded / \(runtime.installedReleaseId?.prefix(12) ?? "none") installed") }
            LabeledContent("Hooks", value: "\(runtime.loadedHookCount) loaded / \(runtime.registeredHookCount) registered")
            if let checksum = runtime.catalogChecksum { LabeledContent("Catalog checksum") { monoLine(checksum) } }
            if !runtime.unknownHookIds.isEmpty { LabeledContent("Unknown hook IDs", value: runtime.unknownHookIds.joined(separator: ", ")) }
            if let error = runtime.registryLoadError {
                TamaNotice(title: "Runtime registry error", detail: error, symbol: "xmark.octagon.fill", tone: .danger).textSelection(.enabled)
            }
        }
        Divider()
        HStack(spacing: WisentDesign.Space.x3) {
            WisentBadge(isEnabled ? "Enabled in this session" : "Not enabled in this session", symbol: isEnabled ? "checkmark.circle.fill" : "minus.circle.fill", tone: isEnabled ? .success : .warning)
            Spacer()
            if model.isPolicyMutationInProgress {
                ProgressView().controlSize(.small)
            } else {
                if !isEnabled {
                    Button("Enable for this session") { isConfirmingEnableHook = true }
                        .buttonStyle(WisentSecondaryButtonStyle())
                }
                Button("Enable all hooks and reload") { isConfirmingEnableAll = true }
                    .buttonStyle(WisentPrimaryButtonStyle())
            }
        }
        Text(session.globallyDisabled ? "All hooks are globally disabled. Enabling creates an allowlist entry only for this agent session." : "The session override is stored for this agent session and restored when the same session is resumed.")
            .font(WisentTypography.body(11))
            .foregroundStyle(WisentDesign.secondary)
    }

    private func monoLine(_ text: String) -> some View {
        Text(text).font(WisentTypography.mono(10)).textSelection(.enabled).lineLimit(1)
    }
}

private struct ValidationView: View {
    let result: ValidationResult

    var body: some View {
        TamaPage {
            WisentPageHeader(eyebrow: "Integrity", title: "Snapshot validation", detail: "Confirm the bundled catalog structure before any local installation or recovery operation.", symbol: "checkmark.seal", tone: result.ok ? .success : .danger)
            TamaPanelSection("Bundled snapshot", detail: "Structural validation of the packaged policy catalog") {
                LabeledContent("Status") {
                    WisentBadge(result.ok ? "Structurally valid" : "Invalid", symbol: result.ok ? "checkmark.seal.fill" : "xmark.octagon.fill", tone: result.ok ? .success : .danger)
                }
                Divider()
                LabeledContent("Catalog hooks", value: result.hookCount.formatted())
                Divider()
                LabeledContent("Orphan sources", value: result.orphanSourceCount.formatted())
            }
            validationMessages(title: "Errors", messages: result.errors, emptyTitle: "No validation errors", symbol: "xmark.octagon.fill", tone: .danger)
            validationMessages(title: "Warnings", messages: result.warnings, emptyTitle: "No warnings", symbol: "exclamationmark.triangle.fill", tone: .warning)
            TamaNotice(title: "Validation boundary", detail: "Tama validates snapshot structure. High-entropy and live runtime drift checks remain in the hooks-rotator CLI.", symbol: "info.circle.fill", tone: .info)
        }
    }

    private func validationMessages(title: String, messages: [String], emptyTitle: String, symbol: String, tone: WisentTone) -> some View {
        TamaPanelSection(title) {
            if messages.isEmpty {
                WisentBadge(emptyTitle, symbol: "checkmark.circle.fill", tone: .success)
            } else {
                ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                    if index > 0 { Divider() }
                    Label(message, systemImage: symbol)
                        .font(WisentTypography.body(12))
                        .foregroundStyle(tone.color)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct RepositoryHooksView: View {
    let hooks: [RepoGitHook]

    var body: some View {
        TamaPage {
            WisentPageHeader(eyebrow: "Git dispatchers", title: "Repository hooks", detail: "Review repository-scoped entrypoints declared by the bundled policy catalog.", symbol: "point.3.connected.trianglepath.dotted")
            if hooks.isEmpty {
                WisentPanel {
                    WisentEmptyState(title: "No repository hooks", detail: "The bundled catalog does not declare repository-scoped Git dispatchers.", symbol: "tray")
                        .frame(maxWidth: .infinity)
                }
            } else {
                WisentPanel(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(hooks.enumerated()), id: \.element.id) { index, hook in
                            if index > 0 { Divider() }
                            HStack(alignment: .top, spacing: WisentDesign.Space.x3) {
                                Image(systemName: "point.3.connected.trianglepath.dotted")
                                    .foregroundStyle(WisentDesign.brand)
                                VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                                    Text(hook.project).font(WisentTypography.bodyMedium(13)).foregroundStyle(WisentDesign.ink)
                                    Text(hook.sourcePath).font(WisentTypography.mono(10)).foregroundStyle(WisentDesign.secondary).textSelection(.enabled)
                                }
                                Spacer()
                                WisentBadge(hook.event, symbol: "arrow.right.circle", tone: .info)
                            }
                            .padding(WisentDesign.Space.x4)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }
}
