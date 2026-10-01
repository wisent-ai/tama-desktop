import Foundation

/// A directory a scan could not read, and the reason the operating system
/// gave for it.
///
/// Both removal screens need it for the same reason the CLI reports it: a
/// worktrees pass over a tree it cannot list at all would answer that the
/// machine holds no second checkouts, and that answer would be quoted as
/// proof. A screen showing the same empty table with no warning would repeat
/// the failure in a nicer font.
struct WalkGap: Decodable, Identifiable, Sendable {
    let path: String
    let reason: String

    var id: String { path }

    var name: String { URL(fileURLWithPath: path).lastPathComponent }

    /// The CLI's own sentence, so an operator who reads it here and then in a
    /// terminal is reading the same product.
    var sentence: String { "could not read \(path): \(reason)" }
}

/// What a pass with gaps in its walk can and cannot claim. One sentence, used
/// by both screens, because both passes make the same promise about the tree.
func walkGapSummary(_ gaps: [WalkGap]) -> String {
    let count = gaps.count
    let plural = count == 1 ? "directory" : "directories"
    return "This pass could not read \(count) \(plural) under the roots, so it cannot say what they hold; nothing was removed."
}
