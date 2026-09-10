import Foundation

/// Everything the copies screen reads without changing anything: which
/// document answers a question, which rows a pass would delete, and which
/// verbs are available. Split from `CopiesModel` when the two halves together
/// crossed the three-hundred-line limit; nothing here mutates.
@MainActor
extension CopiesModel {
    /// The preview when there is one, because it is the same walk the removal
    /// makes, and the scan otherwise.
    var copies: [CopyRecord] { preview?.copies ?? listing?.copies ?? [] }

    var copyCount: Int { preview?.copyCount ?? listing?.copyCount ?? .zero }

    var bytes: Int { preview?.bytes ?? listing?.bytes ?? .zero }

    var sizeLabel: String { copiedSize(bytes) }

    var twins: [CopyTwin] { preview?.twins ?? listing?.twins ?? [] }

    var linkedWorktrees: [String] { preview?.linkedWorktrees ?? listing?.linkedWorktrees ?? [] }

    var unreadable: [String] { preview?.unreadable ?? listing?.unreadable ?? [] }

    var refusals: [CopyRefusal] { preview?.refused ?? [] }

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
    var kept: Set<String> { keptPaths.union(preview?.excepted ?? []) }

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
