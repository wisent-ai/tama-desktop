import Foundation

/// The linked worktrees under the roots the operator named, and the one
/// destructive verb that removes them.
///
/// The two routes are injected so the screen's refusals can be driven without a
/// backend: the no-root refusal in particular has to be provable to issue no
/// request at all.
@MainActor
final class WorktreesModel: ObservableObject {
    enum ScanState: Equatable {
        case idle
        case scanning
        case done
        case failed(String)
    }

    enum RemovalState: Equatable {
        case idle
        case previewing
        case previewed
        case applying
        case applied(String)
        case failed(String)
    }

    typealias List = @Sendable ([String]) async throws -> WorktreeListing
    typealias Remove = @Sendable ([String], Bool, Bool) async throws -> WorktreeRemoval

    @Published private(set) var roots: [String] = []
    @Published private(set) var scanState: ScanState = .idle
    @Published private(set) var listing: WorktreeListing?
    @Published private(set) var removalState: RemovalState = .idle
    @Published private(set) var preview: WorktreeRemoval?

    /// What the last applied pass actually deleted. Kept after the re-read
    /// because the re-read is a tree in which those checkouts are gone, and
    /// the operator still has to be able to see what went.
    @Published private(set) var removed: [String] = []

    /// `--force` on the CLI: off until the operator turns it on, because it is
    /// the difference between a refusal and discarded work.
    @Published private(set) var discardsUncommittedChanges = false

    private let listRoute: List
    private let removeRoute: Remove

    init(
        list: @escaping List = { try await WorktreesClient().list(roots: $0) },
        remove: @escaping Remove = {
            try await WorktreesClient().remove(roots: $0, apply: $1, force: $2)
        }
    ) {
        listRoute = list
        removeRoute = remove
    }

    // MARK: - Roots

    /// The screen reports the preview when there is one, because it is the same
    /// walk the removal makes, and the scan otherwise.
    var repositories: [WorktreeRepository] {
        preview?.repositories ?? listing?.repositories ?? []
    }

    var worktrees: [WorktreeRecord] { repositories.flatMap(\.worktrees) }

    var worktreeCount: Int { preview?.worktreeCount ?? listing?.worktreeCount ?? .zero }

    var refusals: [WorktreeRefusal] { preview?.refused ?? [] }

    var isBusy: Bool {
        scanState == .scanning || removalState == .previewing || removalState == .applying
    }

    var canScan: Bool { !roots.isEmpty && !isBusy }

    var canPreview: Bool { canScan && worktreeCount > .zero }

    /// A preview whose refusals are all settled is the only thing that unlocks
    /// applying; with a refusal outstanding the backend refuses the whole pass
    /// anyway, and saying so before the request is the honest order.
    var canApply: Bool {
        guard let preview else { return false }
        return refusals.isEmpty && preview.worktreeCount > .zero && !isBusy
    }

    /// A worktree that would be discarded rather than removed cleanly, which is
    /// what the confirmation has to say out loud.
    var worktreesNeedingForce: [WorktreeRecord] {
        worktrees.filter(\.isRefusedWithoutForce)
    }

    /// Adding or dropping a root discards the listing and the preview: both
    /// describe the set of roots they were read from, and leaving them beside a
    /// different set invites the operator to remove the wrong checkout.
    func add(root path: String) {
        guard !roots.contains(path) else { return }
        roots.append(path)
        invalidate()
    }

    func remove(root path: String) {
        guard let index = roots.firstIndex(of: path) else { return }
        roots.remove(at: index)
        invalidate()
    }

    /// Turning the discard option on or off changes what applying does, so the
    /// preview it invalidates is dropped instead of left on screen describing a
    /// pass that would no longer happen.
    func setDiscardsUncommittedChanges(_ enabled: Bool) {
        guard enabled != discardsUncommittedChanges else { return }
        discardsUncommittedChanges = enabled
        preview = nil
        removalState = .idle
    }

    // MARK: - Read

    func list() async {
        guard scanState != .scanning else { return }
        guard !roots.isEmpty else {
            scanState = .failed(WorktreesError.rootRequiredSentence)
            return
        }
        let roots = roots
        let route = listRoute
        scanState = .scanning
        do {
            listing = try await Task.detached(priority: .userInitiated) {
                try await route(roots)
            }.value
            scanState = .done
        } catch {
            scanState = .failed(Self.sentence(error))
            TamaFailureReporting.reportSurfaced(
                failurePoint: "tama.worktrees.list",
                error: error,
                sentence: Self.sentence(error)
            )
        }
    }

    // MARK: - Removal

    /// The preview is the same request the removal makes, with `apply` false:
    /// it reports what would be removed and what would be refused, and it
    /// deletes nothing.
    func previewRemoval() async {
        await runRemoval(apply: false)
    }

    /// Only this call deletes, and only the confirmed dialog calls it.
    func applyRemoval() async {
        guard canApply else { return }
        await runRemoval(apply: true)
    }

    private func runRemoval(apply: Bool) async {
        guard removalState != .previewing, removalState != .applying else { return }
        guard !roots.isEmpty else {
            removalState = .failed(WorktreesError.rootRequiredSentence)
            return
        }
        let roots = roots
        let force = discardsUncommittedChanges
        let route = removeRoute
        removalState = apply ? .applying : .previewing
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try await route(roots, apply, force)
            }.value
            preview = result
            guard apply else {
                removalState = .previewed
                return
            }
            removed = result.removed
            // A refused pass answers with the same document and deletes
            // nothing, so it is reported as the refusal it is; the refused
            // list carries the command's sentence for every path in it.
            guard result.refused.isEmpty else {
                removalState = .failed(
                    "Nothing was removed: \(counted(result.refused.count, "worktree")) refused removal."
                )
                return
            }
            removalState = .applied(Self.summary(result))
            // Nothing was refused, so this document describes checkouts that no
            // longer exist: it is re-read rather than left on screen.
            preview = nil
            await list()
        } catch {
            removalState = .failed(Self.sentence(error))
            TamaFailureReporting.reportSurfaced(
                failurePoint: apply ? "tama.worktrees.remove" : "tama.worktrees.preview",
                error: error,
                sentence: Self.sentence(error)
            )
        }
    }

    private func invalidate() {
        listing = nil
        preview = nil
        removed = []
        scanState = .idle
        removalState = .idle
    }

    private static func summary(_ result: WorktreeRemoval) -> String {
        guard !result.removed.isEmpty else {
            return "No worktree was removed."
        }
        return "Removed \(counted(result.removed.count, "worktree")): "
            + result.removed.joined(separator: ", ")
    }

    private static func sentence(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
