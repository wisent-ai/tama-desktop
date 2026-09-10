import Foundation

/// One second full checkout under the named roots.
///
/// A repository copy is a checkout with its own `.git` *directory* below
/// another checkout — what a clone of a local path or a recursive copy
/// produces. Git knows nothing about it from the original, which is why
/// `tama worktrees` never saw one and this screen exists.
struct CopyRecord: Decodable, Identifiable, Sendable {
    let path: String
    /// The canonical checkout of the same repository under the roots, when the
    /// pass found one. `nil` means this directory is the only checkout of that
    /// repository here, which is a refusal until the operator claims it.
    let owner: String?
    let origin: String?
    let bytes: Int
    let dirty: Bool
    let unpublished: Bool
    let ownsWorktrees: Bool
    /// Echoed back by a pass the operator narrowed with `--only`.
    let named: Bool

    var id: String { path }

    var ownerLabel: String { owner ?? "no canonical checkout" }

    var originLabel: String { origin ?? "no origin remote" }

    /// Apparent size, the same number the command prints, because the reason
    /// this screen exists is a full boot volume.
    var sizeLabel: String { copiedSize(bytes) }

    /// Every mark that changes what removal does here. Each one is a refusal
    /// the command raises before deleting anything.
    var marks: [String] {
        var marks: [String] = []
        if dirty { marks.append("Uncommitted changes") }
        if unpublished { marks.append("Commits on no remote") }
        if origin == nil { marks.append("No origin") }
        if owner == nil { marks.append("Only checkout here") }
        if ownsWorktrees { marks.append("Owns worktrees") }
        return marks
    }

    /// A row a bare pass refuses. The missing owner is the one an operator can
    /// answer for themselves by claiming the path; the rest are history.
    var isRefusedWithoutClaim: Bool { !marks.isEmpty }

    var carriesWorkNowhereElse: Bool { dirty || unpublished || origin == nil }
}

/// Two checkouts of one repository, both directly under a root. Reported,
/// never removed: which of the two to keep is the operator's call.
struct CopyTwin: Decodable, Identifiable, Sendable {
    let path: String
    let twin: String
    let origin: String

    var id: String { path }

    var sentence: String {
        "\(path) and \(twin) are both checkouts of \(origin); this pass removes neither, because which one you keep is your call."
    }
}

struct CopyListing: Decodable, Sendable {
    let schemaVersion: Int
    let roots: [String]
    let copies: [CopyRecord]
    let copyCount: Int
    let bytes: Int
    /// Linked worktrees the walk crossed. `tama worktrees` owns those, and
    /// naming them keeps a clean copies pass from reading as one checkout per
    /// repository when it is not.
    let linkedWorktrees: [String]
    let twins: [CopyTwin]
    /// Candidates the walk found a `.git` for and git then refused to answer
    /// for: reported rather than dropped.
    let unreadable: [String]

    var sizeLabel: String { copiedSize(bytes) }
}

/// Why one copy was not removed. The five reasons are the five the command
/// refuses the whole pass on.
enum CopyRefusalReason: String, Decodable, Sendable {
    case uncommittedChanges = "uncommitted-changes"
    case commitsNotOnRemote = "commits-not-on-remote"
    case noOriginRemote = "no-origin-remote"
    case noCanonicalCheckout = "no-canonical-checkout"
    case ownsLinkedWorktrees = "owns-linked-worktrees"
}

struct CopyRefusal: Decodable, Identifiable, Sendable {
    let path: String
    let reason: CopyRefusalReason

    var id: String { path }

    /// The command's own refusal, byte-identical, because an operator who
    /// reads it here and then reads it in a terminal is reading the same
    /// product.
    var sentence: String {
        switch reason {
        case .uncommittedChanges:
            "\(path) has uncommitted changes; commit them there, then run the pass again."
        case .commitsNotOnRemote:
            "\(path) holds commits that are on no remote; push them from there, then run the pass again."
        case .noOriginRemote:
            "\(path) has no origin remote, so this pass cannot prove its history exists anywhere else."
        case .noCanonicalCheckout:
            "\(path) is the only checkout of its repository under the roots given, so it is not a copy of anything."
        case .ownsLinkedWorktrees:
            "\(path) owns linked worktrees; remove those first with 'tama worktrees remove --root <PATH> --apply'."
        }
    }
}

struct CopyRemoval: Decodable, Sendable {
    let schemaVersion: Int
    let roots: [String]
    let copies: [CopyRecord]
    let copyCount: Int
    let bytes: Int
    let linkedWorktrees: [String]
    let twins: [CopyTwin]
    let unreadable: [String]
    let excepted: [String]
    let applied: Bool
    let removed: [String]
    let refused: [CopyRefusal]

    var sizeLabel: String { copiedSize(bytes) }
}

/// The two copies routes on the local backend. `TamaClient` prepends `/v1`,
/// so the paths here are the leaves and never the full route.
struct CopiesClient: Sendable {
    private static let listOperation = "The repository-copy scan"
    private static let removeOperation = "The repository-copy removal"

    func list(roots: [String]) async throws -> CopyListing {
        let paths = try validatedRoots(roots)
        return try await client().post(
            "copies/list",
            body: ["roots": paths],
            as: CopyListing.self,
            operation: Self.listOperation
        )
    }

    /// `except` spares paths and `only` narrows the pass to paths. The route
    /// refuses a body carrying both, exactly as the command line does, so the
    /// caller sends one or the other.
    func remove(
        roots: [String],
        except: [String],
        only: [String],
        apply: Bool,
        force: Bool
    ) async throws -> CopyRemoval {
        let paths = try validatedRoots(roots)
        return try await client().post(
            "copies/remove",
            body: [
                "roots": paths,
                "except": except,
                "only": only,
                "apply": apply,
                "force": force,
            ],
            as: CopyRemoval.self,
            operation: Self.removeOperation
        )
    }

    private func client() async throws -> TamaClient {
        TamaClient(baseURL: try await TamaBackend.shared.endpoint())
    }

    /// No roots is a refusal here as well as in the command, and a root that
    /// is not an existing absolute directory is one the walk cannot start
    /// from.
    private func validatedRoots(_ roots: [String]) throws -> [String] {
        guard !roots.isEmpty else { throw CopiesError.rootRequired }
        let manager = FileManager.default
        return try roots.map { value in
            guard value.hasPrefix("/") else { throw CopiesError.invalidRoot(value) }
            let root = URL(fileURLWithPath: value, isDirectory: true)
                .resolvingSymlinksInPath()
                .standardizedFileURL
            var isDirectory = ObjCBool(false)
            guard
                manager.fileExists(atPath: root.path, isDirectory: &isDirectory),
                isDirectory.boolValue
            else {
                throw CopiesError.invalidRoot(root.path)
            }
            return root.path
        }
    }
}

enum CopiesError: LocalizedError {
    case rootRequired
    case invalidRoot(String)

    /// The command's refusal, byte-identical. There is deliberately no
    /// default root: it would have to be the home directory, which holds
    /// checkouts Tama does not own.
    static let rootRequiredSentence =
        "tama copies needs at least one --root; a machine-wide default would walk directories Tama does not own."

    var errorDescription: String? {
        switch self {
        case .rootRequired:
            Self.rootRequiredSentence
        case let .invalidRoot(path):
            "Choose an existing absolute directory to scan for repository copies: \(path)"
        }
    }
}

/// Apparent size in the same units the command prints, so a number read on
/// the screen matches a number read in a terminal.
func copiedSize(_ bytes: Int) -> String {
    let mib = 1024.0 * 1024.0
    let gib = mib * 1024.0
    let value = Double(bytes)
    if value >= gib {
        return String(format: "%.1f GiB", value / gib)
    }
    return String(format: "%.1f MiB", value / mib)
}
