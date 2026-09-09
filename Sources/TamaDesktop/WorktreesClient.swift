import Foundation

/// One linked worktree, exactly as git reports it.
///
/// A linked worktree is a checkout whose `.git` is a file naming the owning
/// repository: on this machine
/// `~/Documents/CodingProjects/Wisent/.worktrees/brama-stub-purge/.git` reads
/// `gitdir: /Users/lukaszbartoszcze/Documents/CodingProjects/Wisent/brama/.git/worktrees/brama-stub-purge`.
/// That is the noun `git worktree list --porcelain` enumerates and the only
/// noun this screen removes.
struct WorktreeRecord: Decodable, Identifiable, Sendable {
    let path: String
    let branch: String?
    let head: String
    let dirty: Bool
    let locked: Bool
    let prunable: Bool

    var id: String { path }

    /// A worktree checked out at a bare commit has no branch, and `detached
    /// HEAD` is what git calls that state.
    var branchLabel: String { branch ?? "detached HEAD" }

    var shortHead: String { shortIdentifier(head) }

    /// Every mark that changes what removal does here. Dirty and locked are the
    /// two the backend refuses on; prunable means git has already lost the
    /// directory it recorded.
    var marks: [String] {
        var marks: [String] = []
        if dirty { marks.append("Uncommitted changes") }
        if locked { marks.append("Locked") }
        if prunable { marks.append("Prunable") }
        return marks
    }

    /// The rows a bare `remove` would refuse, which is what the operator has to
    /// settle before applying anything.
    var isRefusedWithoutForce: Bool { dirty || locked }
}

/// The worktrees of one owning repository. Git is the authority on which
/// repository owns which worktree, so the document arrives already grouped and
/// the screen never re-derives ownership from a path prefix.
struct WorktreeRepository: Decodable, Identifiable, Sendable {
    let repository: String
    let worktrees: [WorktreeRecord]

    var id: String { repository }

    var name: String { URL(fileURLWithPath: repository).lastPathComponent }

    var dirtyCount: Int { worktrees.filter(\.dirty).count }

    var lockedCount: Int { worktrees.filter(\.locked).count }
}

struct WorktreeListing: Decodable, Sendable {
    let schemaVersion: Int
    let roots: [String]
    let repositories: [WorktreeRepository]
    let worktreeCount: Int

    /// Flattened once, because the table ranks worktrees across repositories
    /// while the rail counts them per repository.
    var allWorktrees: [WorktreeRecord] { repositories.flatMap(\.worktrees) }

    var dirtyCount: Int { allWorktrees.filter(\.dirty).count }

    var lockedCount: Int { allWorktrees.filter(\.locked).count }
}

/// Why one worktree was not removed. The two reasons are the two the CLI
/// refuses the whole pass on.
enum WorktreeRefusalReason: String, Decodable, Sendable {
    case uncommittedChanges = "uncommitted-changes"
    case locked
}

struct WorktreeRefusal: Decodable, Identifiable, Sendable {
    let path: String
    let reason: WorktreeRefusalReason

    var id: String { path }

    /// The CLI's own refusal, byte-identical, because an operator who reads it
    /// here and then reads it in a terminal is reading the same product.
    var sentence: String {
        switch reason {
        case .uncommittedChanges:
            "Refusing to remove \(path): it carries uncommitted changes. Commit them in that worktree, or pass --force to discard them."
        case .locked:
            "Refusing to remove \(path): git reports it locked. Unlock it with git worktree unlock, or pass --force."
        }
    }
}

struct WorktreeRemoval: Decodable, Sendable {
    let schemaVersion: Int
    let roots: [String]
    let repositories: [WorktreeRepository]
    let worktreeCount: Int
    let applied: Bool
    let removed: [String]
    let refused: [WorktreeRefusal]
    /// The worktrees `--except` kept out of this pass. A document that omits
    /// the key excepted nothing, which is an empty list and not a decode
    /// failure: the field is younger than the route.
    let excepted: [String]?

    /// Kept is stated separately from refused everywhere on the screen, so the
    /// absent key is resolved once, here.
    var exceptedPaths: [String] { excepted ?? [] }
}

/// The two worktree routes on the local backend. `TamaClient` prepends `/v1`,
/// so the paths here are the leaves and never the full route.
struct WorktreesClient: Sendable {
    private static let listOperation = "The worktree scan"
    private static let removeOperation = "The worktree removal"

    func list(roots: [String]) async throws -> WorktreeListing {
        let paths = try validatedRoots(roots)
        return try await client().post(
            "worktrees/list",
            body: ["roots": paths],
            as: WorktreeListing.self,
            operation: Self.listOperation
        )
    }

    /// `except` carries the worktrees the operator marked to keep. It is
    /// optional on the route and empty means "nothing kept", so the same
    /// request shape serves both.
    func remove(
        roots: [String],
        except: [String],
        apply: Bool,
        force: Bool
    ) async throws -> WorktreeRemoval {
        let paths = try validatedRoots(roots)
        return try await client().post(
            "worktrees/remove",
            body: ["roots": paths, "except": except, "apply": apply, "force": force],
            as: WorktreeRemoval.self,
            operation: Self.removeOperation
        )
    }

    private func client() async throws -> TamaClient {
        TamaClient(baseURL: try await TamaBackend.shared.endpoint())
    }

    /// No roots is a refusal here as well as in the CLI, and a root that is not
    /// an existing absolute directory is one the walk cannot start from.
    private func validatedRoots(_ roots: [String]) throws -> [String] {
        guard !roots.isEmpty else { throw WorktreesError.rootRequired }
        let manager = FileManager.default
        return try roots.map { value in
            guard value.hasPrefix("/") else { throw WorktreesError.invalidRoot(value) }
            let root = URL(fileURLWithPath: value, isDirectory: true)
                .resolvingSymlinksInPath()
                .standardizedFileURL
            var isDirectory = ObjCBool(false)
            guard
                manager.fileExists(atPath: root.path, isDirectory: &isDirectory),
                isDirectory.boolValue
            else {
                throw WorktreesError.invalidRoot(root.path)
            }
            return root.path
        }
    }
}

enum WorktreesError: LocalizedError {
    case rootRequired
    case invalidRoot(String)

    /// The CLI's refusal, byte-identical. There is deliberately no default
    /// root: `~/Documents/CodingProjects/Wisent` alone holds 519 GB and
    /// `~/.stado/work` holds 1568 entries, none of which Tama owns.
    static let rootRequiredSentence =
        "tama worktrees needs at least one --root; a machine-wide default would walk directories Tama does not own."

    var errorDescription: String? {
        switch self {
        case .rootRequired:
            Self.rootRequiredSentence
        case let .invalidRoot(path):
            "Choose an existing absolute directory to scan for worktrees: \(path)"
        }
    }
}
