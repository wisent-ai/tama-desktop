import Foundation
import Testing
@testable import TamaDesktop

/// The worktrees screen drives two routes and refuses three things before it
/// reaches either. Those refusals are the contract, so they are asserted
/// through the view model with both routes recorded instead of performed.
@MainActor
struct WorktreesModelTests {
    // The routes run off the main actor, so every fixture the closures read is
    // nonisolated: they are immutable strings and counts, shared as such.
    private nonisolated static let rootRefusal =
        "tama worktrees needs at least one --root; a machine-wide default would walk directories Tama does not own."
    private nonisolated static let root = "/roots/wisent"
    private nonisolated static let dirtyWorktree = "/roots/wisent/.worktrees/brama-stub-purge"
    private nonisolated static let lockedWorktree = "/roots/wisent/.worktrees/brama-docs"
    private nonisolated static let cleanWorktree = "/roots/wisent/.worktrees/weles-eval"
    // The document's schema version and its worktree count, named here so the
    // fixtures below carry no bare numbers.
    private nonisolated static let schema = 1
    private nonisolated static let listedWorktrees = 3

    private actor Calls {
        private(set) var lists: [[String]] = []
        private(set) var removes: [(roots: [String], apply: Bool, force: Bool)] = []

        func list(_ roots: [String]) { lists.append(roots) }

        func remove(_ roots: [String], _ apply: Bool, _ force: Bool) {
            removes.append((roots, apply, force))
        }
    }

    @Test
    func refusesBothRoutesWithoutARootAndSendsNothing() async throws {
        let calls = Calls()
        let model = Self.model(calls: calls)

        await model.list()
        await model.previewRemoval()

        #expect(model.scanState == .failed(Self.rootRefusal))
        #expect(model.removalState == .failed(Self.rootRefusal))
        #expect(await calls.lists.isEmpty)
        #expect(await calls.removes.isEmpty)
        #expect(!model.canScan)
        #expect(!model.canApply)
    }

    @Test
    func listGroupsWorktreesUnderTheirRepositoriesAndMarksThem() async throws {
        let calls = Calls()
        let model = Self.model(calls: calls)
        model.add(root: Self.root)

        await model.list()

        #expect(model.scanState == .done)
        #expect(await calls.lists == [[Self.root]])
        #expect(model.repositories.map(\.repository) == [
            "/roots/wisent/brama",
            "/roots/wisent/weles",
        ])
        #expect(model.worktreeCount == Self.listedWorktrees)

        let brama = try #require(model.repositories.first)
        #expect(brama.name == "brama")
        #expect(brama.worktrees.map(\.path) == [Self.dirtyWorktree, Self.lockedWorktree])
        #expect(brama.dirtyCount == 1)
        #expect(brama.lockedCount == 1)

        let dirty = try #require(brama.worktrees.first)
        #expect(dirty.marks == ["Uncommitted changes"])
        #expect(dirty.branchLabel == "stub-purge")
        #expect(dirty.isRefusedWithoutForce)

        let locked = try #require(brama.worktrees.last)
        #expect(locked.marks == ["Locked"])
        // The porcelain reports no branch for a worktree checked out at a bare
        // commit, and git's own word for that state is what the row shows.
        #expect(locked.branchLabel == "detached HEAD")

        let clean = try #require(model.repositories.last?.worktrees.first)
        #expect(clean.path == Self.cleanWorktree)
        #expect(clean.marks.isEmpty)
        #expect(!clean.isRefusedWithoutForce)
    }

    @Test
    func previewMutatesNothingAndCarriesTheRefusalSentences() async throws {
        let calls = Calls()
        let model = Self.model(calls: calls)
        model.add(root: Self.root)
        await model.list()

        await model.previewRemoval()

        let removes = await calls.removes
        #expect(removes.map(\.apply) == [false])
        #expect(removes.map(\.force) == [false])
        #expect(model.removalState == .previewed)

        let dirty = try #require(model.refusals.first)
        #expect(dirty.sentence == "Refusing to remove \(Self.dirtyWorktree): it carries uncommitted changes. Commit them in that worktree, or pass --force to discard them.")
        let locked = try #require(model.refusals.last)
        #expect(locked.sentence == "Refusing to remove \(Self.lockedWorktree): git reports it locked. Unlock it with git worktree unlock, or pass --force.")

        // A refusal stands until it is settled: applying is not merely disabled
        // in the view, the model sends no apply request at all.
        #expect(!model.canApply)
        await model.applyRemoval()
        #expect(await calls.removes.map(\.apply) == [false])
    }

    @Test
    func discardingIsExplicitAndOnlyThenDoesApplyReachTheRoute() async throws {
        let calls = Calls()
        let model = Self.model(calls: calls)
        model.add(root: Self.root)
        await model.list()
        await model.previewRemoval()

        model.setDiscardsUncommittedChanges(true)

        // Turning discarding on invalidates the preview it contradicts.
        #expect(model.refusals.isEmpty)
        #expect(!model.canApply)

        await model.previewRemoval()
        #expect(model.canApply)
        await model.applyRemoval()

        let removes = await calls.removes
        #expect(removes.map(\.apply) == [false, false, true])
        #expect(removes.map(\.force) == [false, true, true])
        #expect(model.removed == [
            Self.dirtyWorktree,
            Self.lockedWorktree,
            Self.cleanWorktree,
        ])
        #expect(model.removalState == .applied(
            "Removed \(Self.listedWorktrees) worktrees: \(Self.dirtyWorktree), \(Self.lockedWorktree), \(Self.cleanWorktree)"
        ))
    }

    // MARK: - Fixtures

    /// The two documents the backend returns, decoded through the same types
    /// the screen decodes, with both routes recorded instead of performed.
    private static func model(calls: Calls) -> WorktreesModel {
        WorktreesModel(
            list: { roots in
                await calls.list(roots)
                return try JSONDecoder().decode(
                    WorktreeListing.self,
                    from: Data(listingDocument.utf8)
                )
            },
            remove: { roots, apply, force in
                await calls.remove(roots, apply, force)
                return try JSONDecoder().decode(
                    WorktreeRemoval.self,
                    from: Data((force ? forcedDocument : refusedDocument).utf8)
                )
            }
        )
    }

    /// The walk both routes report: the remove document is the list document
    /// plus its own three fields, so the repositories block is shared here the
    /// way the backend shares it.
    private nonisolated static let walk = """
          "schemaVersion": \(schema),
          "roots": ["\(root)"],
          "repositories": [
            {
              "repository": "/roots/wisent/brama",
              "worktrees": [
                {
                  "path": "\(dirtyWorktree)",
                  "branch": "stub-purge",
                  "head": "7f3c1d9ab2e455667788990011223344556677aa",
                  "dirty": true,
                  "locked": false,
                  "prunable": false
                },
                {
                  "path": "\(lockedWorktree)",
                  "branch": null,
                  "head": "aa11bb22cc33dd44ee55ff6677889900aabbccdd",
                  "dirty": false,
                  "locked": true,
                  "prunable": false
                }
              ]
            },
            {
              "repository": "/roots/wisent/weles",
              "worktrees": [
                {
                  "path": "\(cleanWorktree)",
                  "branch": "eval",
                  "head": "0f1e2d3c4b5a69788796a5b4c3d2e1f000112233",
                  "dirty": false,
                  "locked": false,
                  "prunable": false
                }
              ]
            }
          ],
          "worktreeCount": \(listedWorktrees)
        """

    private nonisolated static let listingDocument = "{\n\(walk)\n}"

    private nonisolated static let refusedDocument = """
        {
        \(walk),
          "applied": false,
          "removed": [],
          "refused": [
            {"path": "\(dirtyWorktree)", "reason": "uncommitted-changes"},
            {"path": "\(lockedWorktree)", "reason": "locked"}
          ]
        }
        """

    private nonisolated static let forcedDocument = """
        {
        \(walk),
          "applied": true,
          "removed": [
            "\(dirtyWorktree)",
            "\(lockedWorktree)",
            "\(cleanWorktree)"
          ],
          "refused": []
        }
        """
}
