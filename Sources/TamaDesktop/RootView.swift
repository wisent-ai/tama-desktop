import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var violationsModel: ViolationsModel
    @State private var isShowingDisableConfirmation = false
    @State private var isShowingEnableConfirmation = false

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                Label("Overview", systemImage: "shield.lefthalf.filled")
                    .tag(SidebarSelection.overview)
                Label("Hook catalog", systemImage: "list.bullet.rectangle")
                    .tag(SidebarSelection.hooks)
                Label("Justifications", systemImage: "text.badge.checkmark")
                    .tag(SidebarSelection.justifications)
                Label("Snapshot validation", systemImage: "checkmark.seal")
                    .tag(SidebarSelection.validation)
                Label("Repository hooks", systemImage: "point.3.connected.trianglepath.dotted")
                    .tag(SidebarSelection.repositories)
                Label("Violations", systemImage: "ladybug")
                    .tag(SidebarSelection.violations)
            }
            .navigationTitle("Tama")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            VStack(spacing: 0) {
                if model.areHooksDisabled {
                    emergencyBanner
                }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(contentTitle)
        }
        .toolbar {
            ToolbarItem {
                if model.isChangingHookState {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Updating installed hooks")
                } else if model.areHooksDisabled {
                    Button {
                        isShowingEnableConfirmation = true
                    } label: {
                        Label("Re-enable all hooks", systemImage: "power.circle.fill")
                    }
                    .labelStyle(.titleAndIcon)
                    .tint(.green)
                    .help("Restore all Tama-managed hook dispatchers")
                    .disabled(model.isPolicyMutationInProgress)
                } else {
                    Button {
                        isShowingDisableConfirmation = true
                    } label: {
                        Label("Disable all hooks", systemImage: "exclamationmark.octagon.fill")
                    }
                    .labelStyle(.titleAndIcon)
                    .tint(.red)
                    .help("Emergency bypass for all Tama-managed hooks")
                    .disabled(model.isPolicyMutationInProgress)
                }
            }
            ToolbarItemGroup {
                Button("Reveal bundled release", systemImage: "folder") {
                    model.revealHookRelease()
                }
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
                .disabled(model.isRefreshing)
            }
        }
        .onAppear {
            model.startControlMonitoring()
        }
        .onDisappear {
            model.stopControlMonitoring()
            violationsModel.cancelAllOperations()
        }
        .overlay {
            if model.isRefreshing, model.snapshot == nil {
                ProgressView("Loading the Tama catalog…")
            }
        }
        .confirmationDialog(
            "Disable all hooks?",
            isPresented: $isShowingDisableConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disable all hooks", role: .destructive) {
                model.setHooksDisabled(true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Agent, editor, and Git hook dispatchers will bypass all hooks until you re-enable them.")
        }
        .confirmationDialog(
            "Re-enable every managed hook?",
            isPresented: $isShowingEnableConfirmation,
            titleVisibility: .visible
        ) {
            Button("Install approved release and re-enable") {
                model.setHooksDisabled(false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Tama will integrity-check and install its bundled hook release, restore "
                    + "managed dispatchers, then resume supervised sessions. Blocking "
                    + "policy becomes active again."
            )
        }
        .alert(
            "Tama couldn’t update hooks",
            isPresented: Binding(
                get: { model.snapshot != nil && model.errorMessage != nil },
                set: { if !$0 { model.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) {
                model.clearError()
            }
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }

    private var emergencyBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
            Text("ALL HOOKS DISABLED")
                .fontWeight(.bold)
            Text("Agent, editor, and Git hook dispatchers are bypassed.")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Re-enable all hooks") {
                isShowingEnableConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(model.isPolicyMutationInProgress)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .foregroundStyle(.red)
        .background(Color.red.opacity(0.12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("All hooks disabled")
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage = model.errorMessage, model.snapshot == nil {
            ContentUnavailableView(
                "Catalog unavailable",
                systemImage: "exclamationmark.shield",
                description: Text(errorMessage)
            )
        } else if let snapshot = model.snapshot {
            switch model.selection ?? .overview {
            case .overview:
                OverviewView(
                    model: model,
                    snapshot: snapshot,
                    installedHookReleaseID: model.installedHookReleaseID,
                    allowsMutations: true
                )
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
            ContentUnavailableView("Loading", systemImage: "shield")
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
            List(selection: $selection) {
                Label("Overview", systemImage: "shield.lefthalf.filled")
                    .tag(SidebarSelection.overview)
                Label("Hook catalog", systemImage: "list.bullet.rectangle")
                    .tag(SidebarSelection.hooks)
                Label("Snapshot validation", systemImage: "checkmark.seal")
                    .tag(SidebarSelection.validation)
                Label("Repository hooks", systemImage: "point.3.connected.trianglepath.dotted")
                    .tag(SidebarSelection.repositories)
            }
            .navigationTitle("Tama")
        } detail: {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(contentTitle)
        }
        .toolbar {
            ToolbarItem {
                Button("Sign in for controls", systemImage: "person.badge.key") {
                    continueToSignIn()
                }
                .buttonStyle(.borderedProminent)
            }
            ToolbarItemGroup {
                Button("Reveal bundled release", systemImage: "folder") {
                    model.revealHookRelease()
                }
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
                .disabled(model.isRefreshing)
            }
        }
        .overlay {
            if model.isRefreshing, model.snapshot == nil {
                ProgressView("Loading the Tama catalog…")
            }
        }
        .alert(
            "Tama couldn’t load its bundled policy",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) {
                model.clearError()
            }
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage = model.errorMessage, model.snapshot == nil {
            ContentUnavailableView(
                "Catalog unavailable",
                systemImage: "exclamationmark.shield",
                description: Text(errorMessage)
            )
        } else if let snapshot = model.snapshot {
            switch selection ?? .overview {
            case .overview, .justifications, .violations:
                OverviewView(
                    model: model,
                    snapshot: snapshot,
                    installedHookReleaseID: model.installedHookReleaseID,
                    allowsMutations: false
                )
            case .hooks:
                HookCatalogPane(model: model, allowsSessionControl: false)
            case .validation:
                ValidationView(result: snapshot.validation)
            case .repositories:
                RepositoryHooksView(hooks: snapshot.catalog.repoGitHooks)
            }
        } else {
            ContentUnavailableView("Loading", systemImage: "shield")
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
                .frame(minWidth: 340, idealWidth: 420)
            if let hook = model.selectedHook {
                HookDetailView(
                    model: model,
                    hook: hook,
                    revealSource: model.revealSelectedSource,
                    allowsSessionControl: allowsSessionControl
                )
                    .frame(maxWidth: .infinity)
            } else {
                ContentUnavailableView(
                    "Select a hook",
                    systemImage: "list.bullet.rectangle"
                )
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

    private var blockingCount: Int {
        snapshot.catalog.hooks.filter(\.isBlocking).count
    }

    private var categories: Int {
        Set(snapshot.catalog.hooks.map(\.category)).count
    }

    private var buildIdentity: BuildIdentity {
        .current
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    MetricCard(
                        title: "Catalog hooks",
                        value: snapshot.catalog.hooks.count.formatted(),
                        symbol: "list.bullet.rectangle"
                    )
                    MetricCard(
                        title: "Blocking hooks",
                        value: blockingCount.formatted(),
                        symbol: "hand.raised.fill"
                    )
                    MetricCard(
                        title: "Categories",
                        value: categories.formatted(),
                        symbol: "square.grid.2x2"
                    )
                }

                GroupBox("Product build") {
                    LabeledContent("Version", value: buildIdentity.productVersion)
                    Divider()
                    LabeledContent("Channel", value: buildIdentity.channel.capitalized)
                    Divider()
                    LabeledContent("Source revision") {
                        Text(buildIdentity.displayedRevision)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    if let hookRelease = buildIdentity.hookRelease {
                        Divider()
                        LabeledContent("Bundled hook release") {
                            Text(hookRelease.releaseId)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                        Divider()
                        LabeledContent("Hook source revision") {
                            Text(
                                hookRelease.sourceDirty
                                    ? "\(hookRelease.sourceRevision) (dirty source)"
                                    : hookRelease.sourceRevision
                            )
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        }
                    }
                    Divider()
                    LabeledContent(
                        "Target",
                        value: "\(buildIdentity.platform) · \(buildIdentity.architecture)"
                    )
                    Divider()
                    LabeledContent("Built", value: buildIdentity.builtAt)
                }

                if allowsMutations {
                GroupBox("Local setup") {
                    VStack(alignment: .leading) {
                        LabeledContent(
                            "Local runtime",
                            value: installedHookReleaseID == nil
                                ? "Not installed"
                                : "Installed"
                        )
                        if model.isInstallingLocalRuntime {
                            ProgressView("Installing integrity-checked runtime…")
                        } else {
                            Button("Install local runtime") {
                                isConfirmingRuntimeInstall = true
                            }
                            .disabled(
                                !snapshot.validation.ok
                                    || model.isLocalSetupOperationInProgress
                            )
                        }
                        if installedHookReleaseID != nil {
                            Divider()
                            LabeledContent(
                                "Node version",
                                value: model.installedNodeVersion ?? "Not recorded"
                            )
                            LabeledContent("Node executable") {
                                Text(model.installedNodeExecutable ?? "Not recorded")
                                    .textSelection(.enabled)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        Divider()
                        LabeledContent(
                            "Privileged backend",
                            value: model.systemPolicyServiceStatus
                        )
                        if model.isRegisteringSystemPolicyService {
                            ProgressView("Registering privileged backend…")
                        } else if model.systemPolicyServiceStatus != "Enabled" {
                            Button("Register privileged backend") {
                                isConfirmingBackendRegistration = true
                            }
                            .disabled(model.isLocalSetupOperationInProgress)
                        }
                        if installedHookReleaseID != nil
                            || model.systemPolicyServiceStatus != "Not registered" {
                            Divider()
                            if model.isDeactivatingLocalSetup {
                                ProgressView("Deactivating local policy…")
                            } else {
                                Button("Deactivate local setup", role: .destructive) {
                                    isConfirmingLocalDeactivation = true
                                }
                                .disabled(model.isLocalSetupOperationInProgress)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                }

                GroupBox("Current posture") {
                    LabeledContent("Snapshot structure") {
                        StatusLabel(
                            text: snapshot.validation.ok ? "Valid" : "Invalid",
                            isHealthy: snapshot.validation.ok
                        )
                    }
                    if allowsMutations {
                        Divider()
                        LabeledContent(
                            "Installed hooks",
                            value: installedHookReleaseID.map {
                                String($0.prefix(Int("12")!))
                            } ?? "Not installed by Tama"
                        )
                    }
                    Divider()
                    LabeledContent("Warnings", value: snapshot.validation.warnings.count.formatted())
                    Divider()
                    LabeledContent("Errors", value: snapshot.validation.errors.count.formatted())
                    Divider()
                    LabeledContent("Orphan sources", value: snapshot.catalog.orphanSources.count.formatted())
                }

                GroupBox("Boundary") {
                    Text("Tama displays a catalog snapshot generated from hooks-rotator at build time. Re-enable verifies and installs the integrity-sealed hook release bundled with the current Tama build, preserves non-hook settings, updates every managed dispatcher, then restarts and resumes supervised sessions. The app does not import logs, credentials, settings, or caches.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .confirmationDialog(
            "Install the local Tama runtime?",
            isPresented: $isConfirmingRuntimeInstall,
            titleVisibility: .visible
        ) {
            Button("Install runtime") {
                model.installLocalRuntime()
            }
            .disabled(model.isPolicyMutationInProgress)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Tama will verify its bundled hook release, then update managed files "
                    + "under Application Support and the documented per-user agent paths. "
                    + "Existing unrelated settings are preserved."
            )
        }
        .confirmationDialog(
            "Register privileged macOS policy components?",
            isPresented: $isConfirmingBackendRegistration,
            titleVisibility: .visible
        ) {
            Button("Register backend") {
                Task { await model.installSystemPolicyService() }
            }
            .disabled(model.isPolicyMutationInProgress)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "macOS will request approval for Tama's daemon, System Extension, "
                    + "Network filter, and Full Disk Access where required."
            )
        }
        .confirmationDialog(
            "Deactivate Tama's local policy setup?",
            isPresented: $isConfirmingLocalDeactivation,
            titleVisibility: .visible
        ) {
            Button("Disable hooks and unregister backend", role: .destructive) {
                model.deactivateLocalSetup()
            }
            .disabled(model.isPolicyMutationInProgress)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Tama will disable managed hook dispatchers, unregister privileged macOS "
                    + "components, and preserve recovery files. Stop supervised sessions "
                    + "before using this action."
            )
        }
    }
}

private struct HookListView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Hook filter", selection: $model.hookFilter) {
                ForEach(HookFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            List(model.filteredHooks, selection: $model.selectedHookID) { hook in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(hook.id)
                            .font(.headline)
                        Spacer()
                        if hook.isBlocking {
                            Label("Blocking", systemImage: "hand.raised.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(hook.category)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(hook.eventNames)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
                .padding(.vertical, 4)
                .tag(hook.id)
            }
            .searchable(text: $model.searchText, prompt: "Hook, category, or event")
        }
    }
}

private struct HookDetailView: View {
    @ObservedObject var model: AppModel
    let hook: HookRecord
    let revealSource: () -> Void
    let allowsSessionControl: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading) {
                        Text(hook.id)
                            .font(.title2.bold())
                            .textSelection(.enabled)
                        Text(hook.category)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusLabel(text: hook.status.capitalized, isHealthy: hook.status == "active")
                    Text(hook.type)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                if let description = hook.description {
                    DetailSection(title: "What it does", text: description)
                }
                if let why = hook.why {
                    DetailSection(title: "Why it exists", text: why)
                }
                if let sideEffects = hook.sideEffects {
                    DetailSection(title: "Side effects", text: sideEffects)
                }
                if allowsSessionControl {
                    SessionHookControlView(model: model, hook: hook)
                }

                GroupBox("Events") {
                    VStack(alignment: .leading) {
                        ForEach(hook.events) { event in
                            HStack(alignment: .firstTextBaseline) {
                                Image(systemName: event.blocking ? "hand.raised.fill" : "arrow.right.circle")
                                    .foregroundStyle(event.blocking ? .orange : .secondary)
                                VStack(alignment: .leading) {
                                    Text(event.event)
                                        .font(.body.monospaced())
                                    Text(event.blocking ? "Blocking" : "Non-blocking")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(event.timeout)s")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            if event.id != hook.events.last?.id {
                                Divider()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Source") {
                    VStack(alignment: .leading) {
                        Text(hook.sourcePath ?? "No archived source path")
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                        Text(hook.command)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button("Reveal source", systemImage: "folder") {
                            revealSource()
                        }
                        .disabled(hook.sourcePath == nil)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .navigationTitle("Hook")
    }
}

private struct SessionHookControlView: View {
    @ObservedObject var model: AppModel
    let hook: HookRecord
    @State private var isConfirmingEnableHook = false
    @State private var isConfirmingEnableAll = false
    @State private var isConfirmingBackendRegistration = false

    var body: some View {
        GroupBox("Session control") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Privileged backend") {
                    StatusLabel(
                        text: model.systemPolicyServiceStatus,
                        isHealthy: model.systemPolicyServiceStatus == "Enabled"
                    )
                }
                if model.systemPolicyServiceStatus != "Enabled" {
                    HStack {
                        Button("Register backend") {
                            isConfirmingBackendRegistration = true
                        }
                        .disabled(model.isPolicyMutationInProgress)
                        Button("Open approval settings") {
                            model.openSystemPolicyApprovalSettings()
                        }
                        Button("Open Full Disk Access") {
                            model.openFullDiskAccessSettings()
                        }
                    }
                }
                if let sessionErrorMessage = model.sessionErrorMessage {
                    Label(sessionErrorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                if model.agentSessions.isEmpty {
                    Label("No active agent sessions", systemImage: "terminal")
                        .foregroundStyle(.secondary)
                    Text("Tama refuses to start an agent unless the platform has a ready kernel-enforcement backend. Unsupported platforms must add a real backend and submit a support pull request.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let supportURL = URL(string: "https://github.com/wisent-ai/tama-desktop/compare") {
                        Link("Submit platform support pull request", destination: supportURL)
                            .font(.caption)
                    }
                    Button("Refresh sessions", systemImage: "arrow.clockwise") {
                        Task { await model.refreshAgentSessions() }
                    }
                } else {
                    Picker("Session", selection: $model.selectedAgentSessionID) {
                        ForEach(model.agentSessions) { session in
                            Text(session.displayName)
                                .tag(Optional(session.id))
                        }
                    }
                    if let session = model.selectedAgentSession,
                       let isEnabled = model.isHookEnabledInSelectedSession(hook.id) {
                        LabeledContent("Agent", value: session.agentDisplayName)
                        LabeledContent("Session ID") {
                            Text(session.sessionId)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .lineLimit(1)
                        }
                        LabeledContent("Project") {
                            Text(session.cwd)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .lineLimit(1)
                        }
                        if let semanticRuntime = session.semanticRuntime {
                            LabeledContent(
                                "Semantic events",
                                value: String(semanticRuntime.eventSequence)
                            )
                            if let lastEvent = semanticRuntime.recentEvents.last {
                                LabeledContent("Last event", value: lastEvent.event)
                            }
                        }
                        if let systemPolicy = session.systemPolicy {
                            LabeledContent("System policy") {
                                StatusLabel(
                                    text: systemPolicy.ready ? "Kernel-gated" : "Unavailable",
                                    isHealthy: systemPolicy.ready && systemPolicy.mode == "kernel-gated"
                                )
                            }
                            if let backend = systemPolicy.backend {
                                LabeledContent("Policy backend", value: backend)
                            }
                            if !systemPolicy.capabilities.isEmpty {
                                LabeledContent(
                                    "Backend capabilities",
                                    value: systemPolicy.capabilities.joined(separator: ", ")
                                )
                            }
                            if let error = systemPolicy.error {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                            }
                            if let rawURL = systemPolicy.supportPullRequestURL,
                               let supportURL = URL(string: rawURL) {
                                Link("Submit platform support pull request", destination: supportURL)
                                    .font(.caption)
                            }
                        } else {
                            LabeledContent("System policy") {
                                StatusLabel(text: "Backend status unavailable", isHealthy: false)
                            }
                        }
                        if let runtime = session.runtime {
                            LabeledContent("Hook runtime") {
                                StatusLabel(
                                    text: runtime.registryLoadError != nil
                                        ? "Load failed"
                                        : ((runtime.reloadPending ?? false)
                                            ? "Reload scheduled"
                                            : (runtime.reloadRequired ? "Reload required" : "Loaded")),
                                    isHealthy: runtime.registryLoadError == nil
                                        && ((runtime.reloadPending ?? false) || !runtime.reloadRequired)
                                )
                            }
                            LabeledContent("Release") {
                                Text(
                                    "\(runtime.loadedReleaseId.prefix(12)) loaded / "
                                        + "\(runtime.installedReleaseId?.prefix(12) ?? "none") installed"
                                )
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            }
                            LabeledContent(
                                "Hooks",
                                value: "\(runtime.loadedHookCount) loaded / \(runtime.registeredHookCount) registered"
                            )
                            if let checksum = runtime.catalogChecksum {
                                LabeledContent("Catalog checksum") {
                                    Text(checksum)
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                        .lineLimit(1)
                                }
                            }
                            if !runtime.unknownHookIds.isEmpty {
                                LabeledContent(
                                    "Unknown hook IDs",
                                    value: runtime.unknownHookIds.joined(separator: ", ")
                                )
                            }
                            if let error = runtime.registryLoadError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                            }
                        }
                        HStack {
                            StatusLabel(
                                text: isEnabled ? "Enabled in this session" : "Not enabled in this session",
                                isHealthy: isEnabled
                            )
                            Spacer()
                            if model.isPolicyMutationInProgress {
                                ProgressView()
                                    .controlSize(.small)
                            } else if !isEnabled {
                                Button("Enable for this session") {
                                    isConfirmingEnableHook = true
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                            }
                            if !model.isPolicyMutationInProgress {
                                Button("Enable all hooks and reload") {
                                    isConfirmingEnableAll = true
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .tint(.green)
                            }
                        }
                        Text(
                            session.globallyDisabled
                                ? "All hooks are globally disabled. Enabling creates an allowlist entry only for this agent session."
                                : "The session override is stored for this agent session and restored when the same session is resumed."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog(
            "Enable this hook?",
            isPresented: $isConfirmingEnableHook,
            titleVisibility: .visible
        ) {
            Button("Enable for this session") {
                isConfirmingEnableHook = false
                model.enableSelectedSessionHook(hook.id)
            }
            .disabled(model.isPolicyMutationInProgress)
            Button("Cancel", role: .cancel) {
                isConfirmingEnableHook = false
            }
        } message: {
            Text(
                "This changes only hook \(hook.id) in \(model.selectedAgentSession?.agentDisplayName ?? "agent") session \(model.selectedAgentSession?.sessionId ?? "unknown"). Other sessions are unaffected."
            )
        }
        .confirmationDialog(
            "Enable every hook and reload this session?",
            isPresented: $isConfirmingEnableAll,
            titleVisibility: .visible
        ) {
            Button("Enable all hooks") {
                isConfirmingEnableAll = false
                model.enableAllHooksInSelectedSession()
            }
            .disabled(model.isPolicyMutationInProgress)
            Button("Cancel", role: .cancel) {
                isConfirmingEnableAll = false
            }
        } message: {
            Text(
                "One approved operation enables every registered hook, persists the override only in "
                    + "\(model.selectedAgentSession?.agentDisplayName ?? "agent") session "
                    + "\(model.selectedAgentSession?.sessionId ?? "unknown"). "
                    + "Other sessions are unaffected."
            )
        }
        .confirmationDialog(
            "Register privileged macOS policy components?",
            isPresented: $isConfirmingBackendRegistration,
            titleVisibility: .visible
        ) {
            Button("Register backend") {
                Task { await model.installSystemPolicyService() }
            }
            .disabled(model.isPolicyMutationInProgress)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "macOS will request approval for Tama's daemon, System Extension, "
                    + "Network filter, and Full Disk Access where required."
            )
        }
    }
}

private struct ValidationView: View {
    let result: ValidationResult

    var body: some View {
        List {
            Section {
                LabeledContent("Status") {
                    StatusLabel(
                        text: result.ok ? "Structurally valid" : "Invalid",
                        isHealthy: result.ok
                    )
                }
                LabeledContent("Catalog hooks", value: result.hookCount.formatted())
                LabeledContent("Orphan sources", value: result.orphanSourceCount.formatted())
            } header: {
                Text("Bundled snapshot")
            } footer: {
                Text(
                    "Tama validates snapshot structure. High-entropy and live runtime drift checks remain in the hooks-rotator CLI."
                )
            }
            Section("Errors") {
                if result.errors.isEmpty {
                    Label("No validation errors", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ForEach(result.errors, id: \.self) { error in
                        Label(error, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            Section("Warnings") {
                if result.warnings.isEmpty {
                    Label("No warnings", systemImage: "checkmark.circle")
                } else {
                    ForEach(result.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                    }
                }
            }
        }
    }
}

private struct RepositoryHooksView: View {
    let hooks: [RepoGitHook]

    var body: some View {
        List(hooks) { hook in
            VStack(alignment: .leading) {
                HStack {
                    Text(hook.project)
                        .font(.headline)
                    Spacer()
                    Text(hook.event)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(hook.sourcePath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
}


private struct MetricCard: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        GroupBox {
            HStack {
                Image(systemName: symbol)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text(value)
                        .font(.title.bold())
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DetailSection: View {
    let title: String
    let text: String

    var body: some View {
        GroupBox(title) {
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}

private struct StatusLabel: View {
    let text: String
    let isHealthy: Bool

    var body: some View {
        Label(text, systemImage: isHealthy ? "checkmark.circle.fill" : "xmark.octagon.fill")
            .foregroundStyle(isHealthy ? .green : .red)
    }
}
