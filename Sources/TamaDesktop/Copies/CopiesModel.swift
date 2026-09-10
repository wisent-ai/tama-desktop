import Foundation

/// The repository copies under the roots the operator named, and the one
/// destructive verb that removes them.
///
/// The two routes are injected so the screen's refusals can be driven without
/// a backend: the no-root refusal in particular has to be provable to issue no
/// request at all. What the screen reads off this model lives in
/// `CopiesModelReads`; the state and the routes are here.
@MainActor
final class CopiesModel: ObservableObject {
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

    typealias List = @Sendable ([String]) async throws -> CopyListing
    typealias Remove = @Sendable ([String], [String], [String], Bool, Bool) async throws
        -> CopyRemoval

    @Published private(set) var roots: [String] = []
    @Published private(set) var scanState: ScanState = .idle
    @Published private(set) var listing: CopyListing?
    @Published private(set) var removalState: RemovalState = .idle
    @Published private(set) var preview: CopyRemoval?

    /// What the last applied pass actually deleted. Kept after the re-read
    /// because the re-read is a tree in which those directories are gone, and
    /// the operator still has to be able to see what went.
    @Published private(set) var removed: [String] = []

    /// `--force` on the command line: off until the operator turns it on,
    /// because it is the difference between a refusal and deleted history.
    @Published private(set) var overridesRefusals = false

    /// `--except`: the copies the operator marked to keep. A kept copy is
    /// neither removed nor refused — kept is the operator's choice, refused is
    /// the product's, and the screen never conflates the two.
    @Published private(set) var keptPaths: Set<String> = []

    /// `--only`: the copies the operator claimed. Claiming answers the one
    /// question the pass cannot answer for itself — whether losing a directory
    /// that is the sole checkout of its repository here loses anything they
    /// want — and narrows the pass to exactly those paths. Sparing and
    /// narrowing cannot travel together, so a claim clears the kept marks.
    @Published private(set) var claimedPaths: Set<String> = []

    private let listRoute: List
    private let removeRoute: Remove

    init(
        list: @escaping List = { try await CopiesClient().list(roots: $0) },
        remove: @escaping Remove = {
            try await CopiesClient().remove(
                roots: $0,
                except: $1,
                only: $2,
                apply: $3,
                force: $4
            )
        }
    ) {
        listRoute = list
        removeRoute = remove
    }

    // MARK: - Scope and marks

    /// Adding or dropping a root discards the listing and the preview: both
    /// describe the set of roots they were read from, and leaving them beside
    /// a different set invites the operator to remove the wrong directory.
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

    /// Turning the override on or off changes what applying does, so the
    /// preview it invalidates is dropped instead of left on screen describing
    /// a pass that would no longer happen.
    func setOverridesRefusals(_ enabled: Bool) {
        guard enabled != overridesRefusals else { return }
        overridesRefusals = enabled
        preview = nil
        removalState = .idle
    }

    func setKept(_ path: String, _ kept: Bool) {
        guard self.kept.contains(path) != kept else { return }
        if kept {
            keptPaths.insert(path)
            claimedPaths.remove(path)
        } else {
            keptPaths.remove(path)
        }
        preview = nil
        removalState = .idle
    }

    /// Claiming narrows the pass, so it clears every kept mark: the route
    /// refuses a request carrying both, and a screen that sent both would be
    /// asking which one it meant.
    func setClaimed(_ path: String, _ claimed: Bool) {
        guard claimedPaths.contains(path) != claimed else { return }
        if claimed {
            claimedPaths.insert(path)
            keptPaths.removeAll()
        } else {
            claimedPaths.remove(path)
        }
        preview = nil
        removalState = .idle
    }

    func toggleKept(_ record: CopyRecord) { setKept(record.path, !isKept(record)) }

    func toggleClaimed(_ record: CopyRecord) { setClaimed(record.path, !isClaimed(record)) }

    // MARK: - Read

    func list() async {
        guard scanState != .scanning else { return }
        guard !roots.isEmpty else {
            scanState = .failed(CopiesError.rootRequiredSentence)
            return
        }
        let roots = roots
        let route = listRoute
        scanState = .scanning
        do {
            let document = try await Task.detached(priority: .userInitiated) {
                try await route(roots)
            }.value
            listing = document
            // A directory this walk no longer reports is not one the pass can
            // spare or claim, and both flags refuse a path they do not know.
            let paths = Set(document.copies.map(\.path))
            keptPaths.formIntersection(paths)
            claimedPaths.formIntersection(paths)
            scanState = .done
        } catch {
            scanState = .failed(Self.sentence(error))
            TamaFailureReporting.reportSurfaced(
                failurePoint: "tama.copies.list",
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
            removalState = .failed(CopiesError.rootRequiredSentence)
            return
        }
        let roots = roots
        let only = claimedPaths.sorted()
        let except = only.isEmpty ? keptPaths.sorted() : []
        let force = overridesRefusals
        let route = removeRoute
        removalState = apply ? .applying : .previewing
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try await route(roots, except, only, apply, force)
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
                    "Nothing was removed: \(counted(result.refused.count, "copy")) refused removal."
                )
                return
            }
            removalState = .applied(Self.summary(result))
            // Nothing was refused, so this document describes directories that
            // no longer exist: it is re-read rather than left on screen.
            preview = nil
            await list()
        } catch {
            removalState = .failed(Self.sentence(error))
            TamaFailureReporting.reportSurfaced(
                failurePoint: apply ? "tama.copies.remove" : "tama.copies.preview",
                error: error,
                sentence: Self.sentence(error)
            )
        }
    }

    private func invalidate() {
        listing = nil
        preview = nil
        removed = []
        keptPaths = []
        claimedPaths = []
        scanState = .idle
        removalState = .idle
    }

    private static func summary(_ result: CopyRemoval) -> String {
        guard !result.removed.isEmpty else {
            return "No copy was removed."
        }
        return "Removed \(counted(result.removed.count, "copy")), \(result.sizeLabel): "
            + result.removed.joined(separator: ", ")
    }

    private static func sentence(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
