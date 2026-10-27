import Foundation

/// What the Settings rows show where a record is absent: each says which
/// record names nothing, rather than a value standing in for it.
extension SettingsView {
    var installedReleaseLabel: String {
        guard let release = model.installedHookReleaseID else { return "Not installed by Tama" }
        return release
    }

    var policyBundlesCount: String {
        guard let listing = model.policyBundles else { return "not listed" }
        return "\(listing.bundles.count) inactive"
    }

    var bundledReleaseLabel: String {
        guard let release = buildIdentity.hookRelease else { return "Not recorded" }
        return release.releaseId
    }

    var bundledRevisionLabel: String {
        guard let release = buildIdentity.hookRelease else { return "Not recorded" }
        return release.sourceDirty
            ? "\(release.sourceRevision) (dirty source)" : release.sourceRevision
    }
}
