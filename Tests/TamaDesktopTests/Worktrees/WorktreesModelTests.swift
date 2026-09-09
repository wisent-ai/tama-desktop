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
    // The document's schema version and its worktree count, so no fixture
    // below carries a bare number.
    private nonisolated static let schema = 1
    private nonisolated static let listedWorktrees = 3

    private actor Calls {
        private(set) var lists: [[String]] = []
        private(set) var removes: [(roots: [String], except: [String], apply: Bool, force: Bool)] = []

        func list(_ roots: [String]) { lists.append(roots) }

        func remove(_ roots: [String], _ except: [String], _ apply: Bool, _ force: Bool) {
            removes.append((roots, except, apply, force))
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
        #expect(model.repositories.map(\.repository) == ["/roots/wisent/brama", "/roots/wisent/weles"])
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
        // Nothing was marked kept, so `except` goes out empty, not absent.
        #expect(removes.map(\.except) == [[]])
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
        #expect(model.removed == [Self.dirtyWorktree, Self.lockedWorktree, Self.cleanWorktree])
        #expect(model.removalState == .applied(
            "Removed \(Self.listedWorktrees) worktrees: \(Self.dirtyWorktree), \(Self.lockedWorktree), \(Self.cleanWorktree)"
        ))
    }

    /// `--except` on the screen: a marked worktree is what the request keeps
    /// out of the pass, and the apply that follows never deletes it.
    @Test
    func keepingAWorktreeSendsItAsExceptAndNeverRemovesIt() async throws {
        let calls = Calls()
        let model = Self.model(calls: calls)
        model.add(root: Self.root)
        await model.list()
        model.setKept(Self.cleanWorktree, true)
        model.setDiscardsUncommittedChanges(true)
        await model.previewRemoval()

        #expect(model.kept == [Self.cleanWorktree])
        #expect(model.removableWorktrees.map(\.path) == [Self.dirtyWorktree, Self.lockedWorktree])
        #expect(model.removableCount == Self.listedWorktrees - 1)
        #expect(model.canApply)

        await model.applyRemoval()

        #expect(await calls.removes.map(\.except) == [[Self.cleanWorktree], [Self.cleanWorktree]])
        #expect(model.removed == [Self.dirtyWorktree, Self.lockedWorktree])
        #expect(model.removalState == .applied("Removed 2 worktrees: \(Self.dirtyWorktree), \(Self.lockedWorktree)"))
        // The mark outlives the re-read, because the checkout it names does.
        #expect(model.kept == [Self.cleanWorktree])
    }

    /// The document is the authority on what the pass excepted, so an
    /// `excepted` array this screen never marked still reads as kept — and
    /// kept is not refused: one is the operator's choice, the other the
    /// product's.
    @Test
    func decodedExceptedRendersAsKeptAndNotAsRefused() async throws {
        let calls = Calls()
        let model = WorktreesModel(
            list: { await calls.list($0); return try Self.listing() },
            remove: { roots, except, apply, force in
                await calls.remove(roots, except, apply, force)
                return try Self.removal(except: [Self.dirtyWorktree], apply: apply, force: force)
            }
        )
        model.add(root: Self.root)
        await model.list()
        await model.previewRemoval()

        let view = WorktreesView(model: model)
        let dirty = try #require(model.worktrees.first)
        #expect(model.isKept(dirty))
        #expect(view.passLabel(dirty) == "Kept")
        #expect(!model.refusals.contains { $0.path == Self.dirtyWorktree })

        let locked = try #require(model.worktrees.dropFirst().first)
        #expect(view.passLabel(locked) == "Refused")
        let clean = try #require(model.worktrees.last)
        #expect(view.passLabel(clean) == "Removable")
        #expect(model.removableWorktrees.map(\.path) == [Self.lockedWorktree, Self.cleanWorktree])
        // A kept worktree loses nothing, so the confirmation does not warn
        // about discarding it either.
        #expect(model.worktreesNeedingForce.map(\.path) == [Self.lockedWorktree])
    }

    /// Marking or unmarking a worktree changes which checkouts an apply would
    /// delete, so it drops the preview exactly as the discard switch does.
    @Test
    func changingTheKeptSetDropsThePreview() async throws {
        let calls = Calls()
        let model = Self.model(calls: calls)
        model.add(root: Self.root)
        await model.list()
        model.setDiscardsUncommittedChanges(true)
        await model.previewRemoval()
        #expect(model.canApply)

        model.setKept(Self.cleanWorktree, true)

        #expect(model.preview == nil)
        #expect(model.removalState == .idle)
        #expect(!model.canApply)
        // No apply reaches the route against the plan the mark invalidated.
        await model.applyRemoval()
        #expect(await calls.removes.map(\.apply) == [false])

        await model.previewRemoval()
        #expect(model.canApply)
        model.setKept(Self.cleanWorktree, false)
        #expect(model.kept.isEmpty)
        #expect(!model.canApply)
    }

    // MARK: - Fixtures

    /// The two documents the backend returns, decoded through the same types
    /// the screen decodes, with both routes recorded instead of performed.
    private static func model(calls: Calls) -> WorktreesModel {
        WorktreesModel(
            list: { await calls.list($0); return try listing() },
            remove: { roots, except, apply, force in
                await calls.remove(roots, except, apply, force)
                return try removal(except: except, apply: apply, force: force)
            }
        )
    }

    private nonisolated static func listing() throws -> WorktreeListing {
        try JSONDecoder().decode(WorktreeListing.self, from: Data(listingDocument.utf8))
    }

    /// The remove document. An excepted worktree is left completely alone, so
    /// it is neither refused nor removed, and it comes back in `excepted`.
    private nonisolated static func removal(except: [String], apply: Bool, force: Bool) throws -> WorktreeRemoval {
        let removable = [dirtyWorktree, lockedWorktree, cleanWorktree]
            .filter { !except.contains($0) }
        let reasons = [dirtyWorktree: "uncommitted-changes", lockedWorktree: "locked"]
        let refused: [String] = force ? [] : removable.compactMap { path in
            reasons[path].map { "{\"path\": \"\(path)\", \"reason\": \"\($0)\"}" }
        }
        let applied = apply && refused.isEmpty
        let document = """
            {
            \(walk),
              "excepted": [\(quoted(except))],
              "applied": \(applied),
              "removed": [\(quoted(applied ? removable : []))],
              "refused": [\(refused.joined(separator: ", "))]
            }
            """
        return try JSONDecoder().decode(WorktreeRemoval.self, from: Data(document.utf8))
    }

    private nonisolated static func quoted(_ paths: [String]) -> String {
        paths.map { "\"\($0)\"" }.joined(separator: ", ")
    }

    /// One porcelain worktree as both routes report it, so the walk below
    /// reads as the tree it describes rather than as forty lines of JSON.
    private nonisolated static func worktree(_ path: String, _ branch: String, _ head: String, dirty: Bool = false, locked: Bool = false) -> String {
        """
        {"path": "\(path)", "branch": \(branch), "head": "\(head)", \
        "dirty": \(dirty), "locked": \(locked), "prunable": false}
        """
    }

    /// The walk both routes report: the remove document is the list document
    /// plus its own fields, shared here the way the backend shares it.
    private nonisolated static let walk = """
          "schemaVersion": \(schema),
          "roots": ["\(root)"],
          "repositories": [
            {"repository": "/roots/wisent/brama", "worktrees": [
              \(worktree(dirtyWorktree, "\"stub-purge\"", "7f3c1d9ab2e455667788990011223344556677aa", dirty: true)),
              \(worktree(lockedWorktree, "null", "aa11bb22cc33dd44ee55ff6677889900aabbccdd", locked: true))
            ]},
            {"repository": "/roots/wisent/weles", "worktrees": [
              \(worktree(cleanWorktree, "\"eval\"", "0f1e2d3c4b5a69788796a5b4c3d2e1f000112233"))
            ]}
          ],
          "worktreeCount": \(listedWorktrees)
        """

    private nonisolated static let listingDocument = "{\n\(walk)\n}"
}
