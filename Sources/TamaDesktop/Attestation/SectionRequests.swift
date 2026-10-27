import AppKit

/// A section that runs one `tama request` at a time: the label it shows
/// while the request runs and the sentence Tama refused it with.
@MainActor
protocol SectionRequests: AnyObject {
    var working: String? { get set }
    var failure: String? { get set }
}

extension SectionRequests {
    /// Runs `work` unless a request of this section is already running; a
    /// refusal is kept as the sentence Tama gave.
    func run(_ label: String, _ work: @escaping @MainActor () async throws -> Void) {
        guard working == nil else { return }
        working = label
        failure = nil
        Task { @MainActor in
            do {
                try await work()
            } catch let error as LocalizedError {
                self.failure = error.errorDescription
            } catch {
                self.failure = error.localizedDescription
            }
            self.working = nil
        }
    }
}

/// The directory the person picks, or nil when they cancel the panel.
@MainActor
func chooseDirectory() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK else { return nil }
    return panel.url
}
