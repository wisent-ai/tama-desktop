import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    @State private var isShowingDisableConfirmation = false

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
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
                if model.areHooksDisabled {
                    Button {
                        model.setHooksDisabled(false)
                    } label: {
                        Label("Re-enable all hooks", systemImage: "power.circle.fill")
                    }
                    .labelStyle(.titleAndIcon)
                    .tint(.green)
                    .help("Restore all Tama-managed hook dispatchers")
                } else {
                    Button {
                        isShowingDisableConfirmation = true
                    } label: {
                        Label("Disable all hooks", systemImage: "exclamationmark.octagon.fill")
                    }
                    .labelStyle(.titleAndIcon)
                    .tint(.red)
                    .help("Emergency bypass for all Tama-managed hooks")
                }
            }
            ToolbarItemGroup {
                Button("Reveal repository", systemImage: "folder") {
                    model.revealRepository()
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
                model.setHooksDisabled(false)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
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
                OverviewView(snapshot: snapshot)
            case .hooks:
                HookCatalogPane(model: model)
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
        switch model.selection ?? .overview {
        case .overview: "Overview"
        case .hooks: "Hook catalog"
        case .validation: "Snapshot validation"
        case .repositories: "Repository hooks"
        }
    }
}

private struct HookCatalogPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HSplitView {
            HookListView(model: model)
                .frame(minWidth: 340, idealWidth: 420)
            if let hook = model.selectedHook {
                HookDetailView(hook: hook, revealSource: model.revealSelectedSource)
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
    let snapshot: CatalogSnapshot

    private var blockingCount: Int {
        snapshot.catalog.hooks.filter(\.isBlocking).count
    }

    private var categories: Int {
        Set(snapshot.catalog.hooks.map(\.category)).count
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

                GroupBox("Current posture") {
                    LabeledContent("Snapshot structure") {
                        StatusLabel(
                            text: snapshot.validation.ok ? "Valid" : "Invalid",
                            isHealthy: snapshot.validation.ok
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
                    Text("This read-only app ships a catalog snapshot generated from hooks-rotator at build time. It does not install hooks, modify runtime configuration, or import logs, credentials, settings, or caches. Live runtime validation remains in the hooks-rotator CLI.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
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
    let hook: HookRecord
    let revealSource: () -> Void

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
