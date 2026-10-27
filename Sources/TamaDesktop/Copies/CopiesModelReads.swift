import Foundation

/// What a copies walk found, as both the scan and the removal preview carry it.
protocol CopyWalk {
    var copies: [CopyRecord] { get }
    var copyCount: Int { get }
    var bytes: Int { get }
    var twins: [CopyTwin] { get }
    var linkedWorktrees: [String] { get }
    var unreadable: [String] { get }
    var walkGaps: [WalkGap] { get }
}

extension CopyListing: CopyWalk {}
extension CopyRemoval: CopyWalk {}

/// Everything the copies screen reads without changing anything: which
/// document answers a question, which rows a pass would delete, and which
/// verbs are available. Split from `CopiesModel` when the two halves together
/// crossed the three-hundred-line limit; nothing here mutates.
@MainActor
extension CopiesModel {
    /// The walk that answers: the preview when there is one, because it is the
    /// same walk the removal makes, and the scan otherwise. Before any scan
    /// there is none, and the screen has found nothing yet.
    var walk: (any CopyWalk)? {
        if let preview { return preview }
        return listing
    }

    var copies: [CopyRecord] {
        guard let walk else { return [] }
        return walk.copies
    }

    var copyCount: Int {
        guard let walk else { return .zero }
        return walk.copyCount
    }

    var bytes: Int {
        guard let walk else { return .zero }
        return walk.bytes
    }

    var sizeLabel: String { copiedSize(bytes) }

    var twins: [CopyTwin] {
        guard let walk else { return [] }
        return walk.twins
    }

    var linkedWorktrees: [String] {
        guard let walk else { return [] }
        return walk.linkedWorktrees
    }

    var unreadable: [String] {
        guard let walk else { return [] }
        return walk.unreadable
    }

    /// Directories the walk could not read. The screen shows these beside the
    /// count, because a table of no copies from a pass that could not look is
    /// not the same answer as one checkout per repository.
    var walkGaps: [WalkGap] {
        guard let walk else { return [] }
        return walk.walkGaps
    }

    /// What the backend refused; only a removal preview refuses anything.
    var refusals: [CopyRefusal] {
        guard let preview else { return [] }
        return preview.refused
    }

    var isBusy: Bool {
        scanState == .scanning || removalState == .previewing || removalState == .applying
    }

    var canScan: Bool { !roots.isEmpty && !isBusy }

    var canPreview: Bool { canScan && removableCount > .zero }

    /// A preview whose refusals are all settled is the only thing that unlocks
    /// applying; with a refusal outstanding the backend refuses the whole pass
    /// anyway, and saying so before the request is the honest order.
    var canApply: Bool {
        guard preview != nil else { return false }
        return refusals.isEmpty && removableCount > .zero && !isBusy
    }

    /// What the operator marked here, plus what the document reported back as
    /// excepted: a path in either is kept out of the pass.
    var kept: Set<String> {
        guard let preview else { return keptPaths }
        return keptPaths.union(preview.excepted)
    }

    var claimed: Set<String> { claimedPaths }

    func isKept(_ record: CopyRecord) -> Bool { kept.contains(record.path) }

    func isClaimed(_ record: CopyRecord) -> Bool { claimed.contains(record.path) }

    func isRefused(_ record: CopyRecord) -> Bool {
        refusals.contains { $0.path == record.path }
    }

    /// The rows this pass would actually delete: the claimed ones when the
    /// operator narrowed it, everything not kept otherwise.
    var removableCopies: [CopyRecord] {
        guard claimed.isEmpty else { return copies.filter { claimed.contains($0.path) } }
        return copies.filter { !kept.contains($0.path) }
    }

    var removableCount: Int { removableCopies.count }

    var removableBytes: Int { removableCopies.reduce(.zero) { $0 + $1.bytes } }

    /// A row that would lose work existing nowhere else if the override were
    /// on, which is what the confirmation has to say out loud.
    var copiesLosingWork: [CopyRecord] {
        removableCopies.filter(\.carriesWorkNowhereElse)
    }
}
