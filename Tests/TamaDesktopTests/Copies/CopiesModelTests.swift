import Foundation
import Testing
@testable import TamaDesktop

/// The copies screen drives two routes and decides, before either is called,
/// what a pass would delete. Those decisions are the contract, so they are
/// asserted through the view model with both routes recorded instead of
/// performed.
@MainActor
struct CopiesModelTests {
    // The routes run off the main actor, so every fixture the closures read is
    // nonisolated: they are immutable strings and counts, shared as such.
    private nonisolated static let rootRefusal =
        "tama copies needs at least one --root; a machine-wide default would walk directories Tama does not own."
    private nonisolated static let root = "/roots/wisent"
    private nonisolated static let canonical = "/roots/wisent/brama"
    /// A clean copy of a checkout that is also under the root: removable.
    private nonisolated static let cleanCopy = "/roots/wisent/brama/.work/pull"
    /// A copy with commits on no remote: refused, and no mark changes that.
    private nonisolated static let unpushedCopy = "/roots/wisent/weles/.work/scan"
    /// The sole checkout of its repository here: refused until claimed.
    private nonisolated static let loneCopy = "/roots/wisent/weles/vendor/pyreft"
    private nonisolated static let worktree = "/roots/wisent/.worktrees/brama-stub-purge"
    private nonisolated static let twinCopy = "/roots/wisent/wisent-compute"
    private nonisolated static let twinOriginal = "/roots/wisent/stado"
    /// The document's schema version, its copy count and the apparent size of
    /// each copy, so no fixture below carries a bare number.
    private nonisolated static let schema = 1
    private nonisolated static let listedCopies = 3
    private nonisolated static let cleanBytes = 1_073_741_824
    private nonisolated static let unpushedBytes = 52_428_800
    private nonisolated static let loneBytes = 141_557_760
    private nonisolated static let listedBytes = cleanBytes + unpushedBytes + loneBytes

    private actor Calls {
        private(set) var lists: [[String]] = []
        private(set) var removes:
            [(roots: [String], except: [String], only: [String], apply: Bool, force: Bool)] = []

        func list(_ roots: [String]) { lists.append(roots) }

        func remove(
            _ roots: [String],
            _ except: [String],
            _ only: [String],
            _ apply: Bool,
            _ force: Bool
        ) {
            removes.append((roots, except, only, apply, force))
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
    func listReportsEachCopyWithTheCheckoutItDuplicates() async throws {
        let calls = Calls()
        let model = Self.model(calls: calls)
        model.add(root: Self.root)

        await model.list()

        #expect(model.scanState == .done)
        #expect(await calls.lists == [[Self.root]])
        #expect(model.copies.map(\.path) == [Self.cleanCopy, Self.unpushedCopy, Self.loneCopy])
        #expect(model.copyCount == Self.listedCopies)
        #expect(model.bytes == Self.listedBytes)

        let clean = try #require(model.copies.first)
        #expect(clean.owner == Self.canonical)
        #expect(clean.marks.isEmpty)
        #expect(!clean.isRefusedWithoutClaim)
        #expect(clean.sizeLabel == "1.0 GiB")

        let lone = try #require(model.copies.last)
        #expect(lone.owner == nil)
        #expect(lone.marks == ["Only checkout here"])
        #expect(!lone.carriesWorkNowhereElse)
    }

    @Test
    func aKeptCopyTravelsAsExceptAndIsNeitherRemovedNorRefused() async throws {
        let calls = Calls()
        let model = Self.model(calls: calls)
        model.add(root: Self.root)
        await model.list()

        model.setKept(Self.unpushedCopy, true)
        model.setKept(Self.loneCopy, true)
        await model.previewRemoval()

        let sent = try #require(await calls.removes.last)
        #expect(sent.except == [Self.unpushedCopy, Self.loneCopy], "sent sorted")
        #expect(sent.only.isEmpty)
        #expect(!sent.apply)
        #expect(model.removalState == .previewed)
        #expect(model.removableCopies.map(\.path) == [Self.cleanCopy])
        #expect(model.refusals.isEmpty)
        #expect(model.canApply)
    }

    @Test
    func claimingASoleCheckoutNarrowsThePassAndClearsEveryKeptMark() async throws {
        let calls = Calls()
        let model = Self.model(calls: calls)
        model.add(root: Self.root)
        await model.list()

        model.setKept(Self.cleanCopy, true)
        model.setClaimed(Self.loneCopy, true)
        await model.previewRemoval()

        let sent = try #require(await calls.removes.last)
        #expect(sent.only == [Self.loneCopy])
        #expect(sent.except.isEmpty, "narrowing and sparing cannot travel together")
        #expect(model.kept.isEmpty)
        #expect(model.removableCopies.map(\.path) == [Self.loneCopy])
        #expect(model.refusals.isEmpty)
    }

    @Test
    func anOutstandingRefusalCarriesTheCommandSentenceAndBlocksApplying() async throws {
        let calls = Calls()
        let model = Self.model(calls: calls)
        model.add(root: Self.root)
        await model.list()

        // Nothing spared: the copy with commits on no remote refuses the pass.
        await model.previewRemoval()

        #expect(model.refusals.map(\.path) == [Self.unpushedCopy, Self.loneCopy])
        #expect(
            model.refusals.first?.sentence
                == "\(Self.unpushedCopy) holds commits that are on no remote; push them from there, then run the pass again."
        )
        #expect(!model.canApply, "an outstanding refusal is stated before a request is sent")

        await model.applyRemoval()

        #expect(await calls.removes.allSatisfy { !$0.apply }, "no apply reached the route")
        #expect(model.removed.isEmpty)
    }

    @Test
    func aTwinCheckoutIsReportedAndNeverRemovable() async throws {
        let calls = Calls()
        let model = Self.model(calls: calls)
        model.add(root: Self.root)

        await model.list()

        let twin = try #require(model.twins.first)
        #expect(twin.path == Self.twinCopy)
        #expect(twin.twin == Self.twinOriginal)
        #expect(!model.copies.map(\.path).contains(twin.path))
        #expect(model.linkedWorktrees == [Self.worktree])
    }

    // MARK: - Fixtures

    /// The two documents the backend returns, decoded through the same types
    /// the screen decodes, with both routes recorded instead of performed.
    private static func model(calls: Calls) -> CopiesModel {
        CopiesModel(
            list: { await calls.list($0); return try listing() },
            remove: { roots, except, only, apply, force in
                await calls.remove(roots, except, only, apply, force)
                return try removal(except: except, only: only, apply: apply, force: force)
            }
        )
    }

    private nonisolated static func listing() throws -> CopyListing {
        try JSONDecoder().decode(CopyListing.self, from: Data(listingDocument.utf8))
    }

    /// The remove document. An excepted copy is left completely alone, a
    /// claimed one narrows the pass, and the sole-checkout refusal is the one
    /// a claim answers.
    private nonisolated static func removal(
        except: [String],
        only: [String],
        apply: Bool,
        force: Bool
    ) throws -> CopyRemoval {
        let all = [cleanCopy, unpushedCopy, loneCopy]
        let selected = only.isEmpty
            ? all.filter { !except.contains($0) }
            : all.filter(only.contains)
        let reasons = [unpushedCopy: "commits-not-on-remote", loneCopy: "no-canonical-checkout"]
        let refused: [String] = force ? [] : selected.compactMap { path in
            guard let reason = reasons[path] else { return nil }
            // A claimed path answers exactly the sole-checkout question.
            if reason == "no-canonical-checkout", only.contains(path) { return nil }
            return "{\"path\": \"\(path)\", \"reason\": \"\(reason)\"}"
        }
        let applied = apply && refused.isEmpty
        let document = """
            {
            \(walk),
              "excepted": [\(quoted(except))],
              "applied": \(applied),
              "removed": [\(quoted(applied ? selected : []))],
              "refused": [\(refused.joined(separator: ", "))]
            }
            """
        return try JSONDecoder().decode(CopyRemoval.self, from: Data(document.utf8))
    }

    private nonisolated static func quoted(_ paths: [String]) -> String {
        paths.map { "\"\($0)\"" }.joined(separator: ", ")
    }

    /// One copy as both routes report it, so the walk below reads as the tree
    /// it describes rather than as forty lines of JSON.
    private nonisolated static func copy(
        _ path: String,
        owner: String?,
        bytes: Int,
        unpublished: Bool = false
    ) -> String {
        """
        {"path": "\(path)", "owner": \(owner.map { "\"\($0)\"" } ?? "null"), \
        "origin": "https://github.com/wisent-ai/brama.git", "bytes": \(bytes), \
        "dirty": false, "unpublished": \(unpublished), "ownsWorktrees": false, \
        "named": false}
        """
    }

    /// The walk both routes report: the remove document is the list document
    /// plus its own fields, shared here the way the backend shares it.
    private nonisolated static let walk = """
          "schemaVersion": \(schema),
          "roots": ["\(root)"],
          "copies": [
            \(copy(cleanCopy, owner: canonical, bytes: cleanBytes)),
            \(copy(unpushedCopy, owner: canonical, bytes: unpushedBytes, unpublished: true)),
            \(copy(loneCopy, owner: nil, bytes: loneBytes))
          ],
          "copyCount": \(listedCopies),
          "bytes": \(listedBytes),
          "linkedWorktrees": ["\(worktree)"],
          "twins": [
            {"path": "\(twinCopy)", "twin": "\(twinOriginal)", \
        "origin": "github.com/wisent-ai/stado"}
          ],
          "unreadable": []
        """

    private nonisolated static let listingDocument = "{\n\(walk)\n}"
}
