import Foundation
import Testing
@testable import TamaDesktop

/// What both removal screens say when the walk behind them could not read the
/// whole tree.
///
/// On 2026-09-12 a worktrees pass over a tree it could not list answered that
/// the machine holds no second checkouts, and that answer was quoted as proof.
/// The CLI now names every directory it could not read and exits non-zero; a
/// screen that showed the same empty table with no warning would repeat the
/// failure in a nicer font, so each model here is held to carrying the gaps.
@MainActor
struct WalkGapTests {
    private nonisolated static let root = "/roots/wisent"
    private nonisolated static let sealed = "/roots/wisent/sealed"
    private nonisolated static let reason = "Operation not permitted (os error 1)"
    private nonisolated static let schema = 1
    /// The empty walk every fixture below describes: no worktrees, no copies,
    /// no bytes.
    private nonisolated static let nothing = 0

    @Test
    func theWorktreesScreenNamesEveryDirectoryTheWalkCouldNotRead() async throws {
        let model = WorktreesModel(
            list: { _ in try Self.worktreeListing(gaps: true) },
            remove: { _, _, _, _ in try Self.worktreeRemoval() }
        )
        model.add(root: Self.root)

        await model.list()

        #expect(model.scanState == .done)
        #expect(model.worktreeCount == .zero)
        let gap = try #require(model.walkGaps.first)
        #expect(model.walkGaps.count == 1)
        #expect(gap.path == Self.sealed)
        #expect(gap.reason == Self.reason)
        #expect(gap.name == "sealed")
        #expect(gap.sentence == "could not read \(Self.sealed): \(Self.reason)")
        #expect(
            walkGapSummary(model.walkGaps)
                == "This pass could not read 1 directory under the roots, so it cannot say what they hold; nothing was removed."
        )
    }

    /// A backend older than the field reports nothing about its walk, and the
    /// screen has to keep working: an absent key is an empty report, never a
    /// decode failure that takes the whole screen down.
    @Test
    func aDocumentWithoutTheReportIsAnEmptyReport() async throws {
        let model = WorktreesModel(
            list: { _ in try Self.worktreeListing(gaps: false) },
            remove: { _, _, _, _ in try Self.worktreeRemoval() }
        )
        model.add(root: Self.root)

        await model.list()

        #expect(model.scanState == .done)
        #expect(model.walkGaps.isEmpty)
    }

    @Test
    func theCopiesScreenNamesEveryDirectoryTheWalkCouldNotRead() async throws {
        let model = CopiesModel(
            list: { _ in try Self.copyListing() },
            remove: { _, _, _, _, _ in try Self.copyRemoval() }
        )
        model.add(root: Self.root)

        await model.list()

        #expect(model.copies.isEmpty)
        let gap = try #require(model.walkGaps.first)
        #expect(gap.path == Self.sealed)
        #expect(gap.reason == Self.reason)
    }

    // MARK: - Fixtures

    private nonisolated static let gapDocument = """
        {"path": "\(sealed)", "reason": "\(reason)"}
        """

    private nonisolated static func worktreeListing(gaps: Bool) throws -> WorktreeListing {
        let report = gaps ? ",\n  \"unreadableDirectories\": [\(gapDocument)]" : ""
        let document = """
            {
              "schemaVersion": \(schema),
              "roots": ["\(root)"],
              "repositories": [],
              "worktreeCount": \(nothing)\(report)
            }
            """
        return try JSONDecoder().decode(WorktreeListing.self, from: Data(document.utf8))
    }

    private nonisolated static func worktreeRemoval() throws -> WorktreeRemoval {
        let document = """
            {
              "schemaVersion": \(schema),
              "roots": ["\(root)"],
              "repositories": [],
              "worktreeCount": \(nothing),
              "applied": false,
              "removed": [],
              "refused": [],
              "unreadableDirectories": [\(gapDocument)],
              "excepted": []
            }
            """
        return try JSONDecoder().decode(WorktreeRemoval.self, from: Data(document.utf8))
    }

    private nonisolated static let copyWalk = """
          "schemaVersion": \(schema),
          "roots": ["\(root)"],
          "copies": [],
          "copyCount": \(nothing),
          "bytes": \(nothing),
          "linkedWorktrees": [],
          "twins": [],
          "unreadable": [],
          "unreadableDirectories": [\(gapDocument)]
        """

    private nonisolated static func copyListing() throws -> CopyListing {
        try JSONDecoder().decode(CopyListing.self, from: Data("{\n\(copyWalk)\n}".utf8))
    }

    private nonisolated static func copyRemoval() throws -> CopyRemoval {
        let document = """
            {
            \(copyWalk),
              "excepted": [],
              "applied": false,
              "removed": [],
              "refused": []
            }
            """
        return try JSONDecoder().decode(CopyRemoval.self, from: Data(document.utf8))
    }
}
