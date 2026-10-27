import Combine
import Foundation
import XCTest
@testable import TamaDesktop

final class UnjudgedSelectionTests: XCTestCase, @unchecked Sendable {
    private var checkout: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .resolvingSymlinksInPath()
    }

    @MainActor
    private func settle(_ model: UnjudgedCommitsModel) async {
        for await state in model.$working.values {
            if state == nil { return }
        }
    }

    @MainActor
    private func retain(_ model: UnjudgedCommitsModel, at target: URL) throws {
        var observation: [String: Any] = [:]
        if let repository = model.repository { observation["selectedRepository"] = repository.path }
        if let report = model.report { observation["reportedRepository"] = report.repository }
        if let failure = model.failure { observation["failure"] = failure }
        observation["hasReport"] = model.report != nil
        observation["hasFailure"] = model.failure != nil
        try JSONSerialization.data(withJSONObject: observation, options: [.prettyPrinted, .sortedKeys])
            .write(to: target)
    }

    @MainActor
    func testSelectingAnotherCheckoutRemovesTheActuallyReadReport() async throws {
        let (client, root, _) = try fixture()
        let model = UnjudgedCommitsModel(command: client.command)
        model.repository = checkout
        model.read()
        await settle(model)
        try retain(model, at: root.appendingPathComponent("selected-report.json"))
        XCTAssertNil(model.failure)
        let report = try XCTUnwrap(model.report)
        XCTAssertEqual(URL(fileURLWithPath: report.repository).resolvingSymlinksInPath(), checkout)
        model.repository = root.appendingPathComponent("home")
        try retain(model, at: root.appendingPathComponent("changed-selection.json"))
        XCTAssertNil(model.report, "A real previous report must not describe the new selection")
        XCTAssertNil(model.failure)
    }

    @MainActor
    func testSelectingACheckoutClearsTheActualMissingDirectoryFailure() async throws {
        let (client, root, _) = try fixture()
        let model = UnjudgedCommitsModel(command: client.command)
        let removed = root.appendingPathComponent("removed-selection")
        try FileManager.default.createDirectory(at: removed, withIntermediateDirectories: true)
        model.repository = removed
        try FileManager.default.removeItem(at: removed)
        model.read()
        await settle(model)
        try retain(model, at: root.appendingPathComponent("missing-directory-failure.json"))
        XCTAssertNil(model.report)
        let failure = try XCTUnwrap(model.failure,
            "The actual backend must refuse the directory removed after selection")
        try Data(failure.utf8).write(to: root.appendingPathComponent("missing-directory-failure.txt"))
        model.repository = checkout
        try retain(model, at: root.appendingPathComponent("selection-after-failure.json"))
        XCTAssertNil(model.report)
        XCTAssertNil(model.failure, "The old directory's failure must not describe the new checkout")
        model.read()
        await settle(model)
        try retain(model, at: root.appendingPathComponent("read-after-selection.json"))
        XCTAssertNil(model.failure)
        let report = try XCTUnwrap(model.report)
        XCTAssertEqual(URL(fileURLWithPath: report.repository).resolvingSymlinksInPath(), checkout)
    }

    @MainActor
    func testPendingReadCannotPublishForThePreviousSelection() async throws {
        let (client, root, _) = try fixture()
        let model = UnjudgedCommitsModel(command: client.command)
        model.repository = checkout
        model.read()
        model.repository = root.appendingPathComponent("home")
        await settle(model)
        try retain(model, at: root.appendingPathComponent("retired-pending-read.json"))
        XCTAssertEqual(model.repository, root.appendingPathComponent("home"))
        XCTAssertNil(model.report, "A completed request for the old selection must not publish here")
        XCTAssertNil(model.failure, "An old selection's request failure must not publish here")
    }

    @MainActor
    func testPendingMissingDirectoryFailureCannotReplaceTheNewSelection() async throws {
        let (client, root, _) = try fixture()
        let removed = root.appendingPathComponent("retired-missing-directory")
        try FileManager.default.createDirectory(at: removed, withIntermediateDirectories: true)
        let model = UnjudgedCommitsModel(command: client.command)
        model.repository = removed
        try FileManager.default.removeItem(at: removed)
        model.read()
        model.repository = checkout
        await settle(model)
        try retain(model, at: root.appendingPathComponent("retired-pending-failure.json"))
        XCTAssertEqual(model.repository, checkout)
        XCTAssertNil(model.report)
        XCTAssertNil(model.failure, "The retired directory's failure must not describe this checkout")
    }
}
