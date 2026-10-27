import Foundation
import XCTest

/// App Store Connect and the owner vault are real dependencies. Select this
/// suite only with isolated team/bundle/vault fixtures declared by the runner.
final class ProvisioningTests: XCTestCase {
    struct Field: Decodable, Equatable {
        let name: String
        let sha256: String
    }

    private func fields(_ value: [String: Any]) throws -> [Field] {
        guard let entries = value["fields"] else {
            throw ProvisioningQualificationError(description: "the real item response carries no fields metadata")
        }
        return try JSONDecoder().decode([Field].self,
            from: JSONSerialization.data(withJSONObject: entries))
            .sorted { $0.name < $1.name }
    }

    struct Profile: Decodable {
        let field: String
        let bundle_id: String
        let profile: String
        let origin: String
    }

    private func profiles(_ receipt: [String: Any]) throws -> [Profile] {
        guard let rows = receipt["profiles"] else {
            throw ProvisioningQualificationError(description: "profile acquisition returned no profiles receipt")
        }
        return try JSONDecoder().decode([Profile].self,
            from: JSONSerialization.data(withJSONObject: rows))
    }

    private func associations(_ profiles: [Profile]) throws -> [String: String] {
        var result: [String: String] = [:]
        for profile in profiles {
            guard result.updateValue(profile.bundle_id, forKey: profile.field) == nil else {
                throw ProvisioningQualificationError(description: "profile receipt repeats field \(profile.field)")
            }
        }
        return result
    }

    func testActualAcquisitionReuseAndRefusals() throws {
        let fixture = try ProvisioningFixture()
        var failures: [Error] = []
        var attemptedAcquisition = false
        do {
            guard fixture.appBundle != fixture.extensionBundle else {
                throw ProvisioningQualificationError(description: "the isolated app and extension bundle fixtures must be distinct")
            }
            let manifest = try JSONSerialization.jsonObject(with:
                Data(contentsOf: fixture.root.appendingPathComponent(".wisent-release.json"))) as? [String: Any]
            let platform = try ProvisioningFixture.required("TAMA_TEST_RELEASE_PLATFORM")
            guard let platforms = manifest?["platforms"] as? [String: Any],
                let selected = platforms[platform] as? [String: Any],
                let bindings = selected["secret_env"] as? [String: String] else {
                throw ProvisioningQualificationError(description: "the declared release platform has no secret_env contract")
            }
            func field(_ environmentName: String) throws -> String {
                guard let binding = bindings[environmentName],
                    let separator = binding.firstIndex(of: "#"),
                    !binding[binding.index(after: separator)...].isEmpty else {
                    throw ProvisioningQualificationError(description: "the release manifest has no item#field binding for \(environmentName)")
                }
                return String(binding[binding.index(after: separator)...])
            }
            let profilePairs = [
                try field("TAMA_APP_PROFILE_B64") + "=" + fixture.appBundle,
                try field("TAMA_NETWORK_FILTER_PROFILE_B64") + "=" + fixture.extensionBundle,
            ]
            let names = Set(try [field("TAMA_APP_PROFILE_B64"), field("TAMA_NETWORK_FILTER_PROFILE_B64")])
            guard try field("TAMA_APP_PROFILE_B64") != field("TAMA_NETWORK_FILTER_PROFILE_B64") else {
                throw ProvisioningQualificationError(description: "the manifest must not overwrite the app and extension profiles in one field")
            }
            let inventory = try fixture.command(["credentials", "vault", "items", "--host", fixture.host, "--json"])
            guard let initialItems = inventory["items"] as? [[String: Any]] else {
                throw ProvisioningQualificationError(description: "the real vault inventory returned no items array")
            }
            guard !initialItems.contains(where: { $0["name"] as? String == fixture.item }) else {
                throw ProvisioningQualificationError(description: "the isolated destination item already exists")
            }
            let incomplete = try fixture.command(["credentials", "item", "show", "--host", fixture.host,
                fixture.incompleteKeyItem, "--json"])
            guard !(try fields(incomplete)).contains(where: { $0.name == "private_key_p8_base64" }) else {
                throw ProvisioningQualificationError(description: "TAMA_TEST_INCOMPLETE_API_KEY_ITEM must really lack private_key_p8_base64")
            }
            func acquire(_ key: String) -> [String] {
                ["credentials", "signing-profile", "ensure", "--provider", "apple", "--host", fixture.host,
                    fixture.item, "--credentials", key] + profilePairs.flatMap { ["--profile", $0] } + ["--json"]
            }
            attemptedAcquisition = true
            let first = try fixture.command(acquire(fixture.apiKeyItem))
            let firstProfiles = try profiles(first)
            fixture.report["initial_acquisition"] = first
            let expectedAssociations = [
                try field("TAMA_APP_PROFILE_B64"): fixture.appBundle,
                try field("TAMA_NETWORK_FILTER_PROFILE_B64"): fixture.extensionBundle,
            ]
            XCTAssertEqual(try associations(firstProfiles), expectedAssociations,
                "each persisted field must be associated with its own bundle, not just the same independent sets")
            let stored = try fixture.command(["credentials", "item", "show", "--host", fixture.host, fixture.item, "--json"])
            let before = try fields(stored)
            XCTAssertEqual(Set(before.map(\.name)), names)
            fixture.report["persisted_profiles"] = stored

            let reused = try fixture.command(acquire(fixture.apiKeyItem))
            let reusedProfiles = try profiles(reused)
            fixture.report["repeated_acquisition"] = reused
            XCTAssertEqual(try associations(reusedProfiles), expectedAssociations)
            XCTAssertTrue(reusedProfiles.allSatisfy { $0.origin == "reused" },
                "an active profile must be reused rather than duplicated at the provider")
            let initialNames = Dictionary(grouping: firstProfiles, by: \.field).mapValues { $0.map(\.profile) }
            let repeatedNames = Dictionary(grouping: reusedProfiles, by: \.field).mapValues { $0.map(\.profile) }
            XCTAssertEqual(repeatedNames, initialNames, "reuse must retain the provider profile associated with each field")
            let afterReuse = try fixture.command(["credentials", "item", "show", "--host", fixture.host, fixture.item, "--json"])
            XCTAssertEqual(try fields(afterReuse), before, "reuse must retain the actual stored profile bytes")

            let refused = try fixture.execute(fixture.executable, acquire(fixture.incompleteKeyItem))
            XCTAssertNotEqual(refused.status, EXIT_SUCCESS)
            let cause = refused.output + refused.error
            XCTAssertTrue(cause.contains(fixture.incompleteKeyItem), "the refusal must identify the actual credential item")
            XCTAssertTrue(cause.contains("private_key_p8_base64"), "the refusal must identify the actual missing credential field")
            let afterRefusal = try fixture.command(["credentials", "item", "show", "--host", fixture.host, fixture.item, "--json"])
            XCTAssertEqual(try fields(afterRefusal), before, "a refused acquisition must not replace persisted profiles")
            fixture.report["profiles_after_refusal"] = afterRefusal
            fixture.report["status"] = "observations_recorded"
        } catch {
            failures.append(error)
            fixture.report["status"] = "failed"
            fixture.report["error"] = String(reflecting: error)
        }
        // Only the run's fresh UUID owner item is retired. Team profiles belong
        // to the dedicated persistent qualification fixtures and are reused.
        if attemptedAcquisition {
            do {
                let inventory = try fixture.command(["credentials", "vault", "items", "--host", fixture.host, "--json"])
                guard let items = inventory["items"] as? [[String: Any]] else {
                    throw ProvisioningQualificationError(description: "cleanup inventory returned no items array")
                }
                if items.contains(where: { $0["name"] as? String == fixture.item && $0["state"] as? String == "active" }) {
                    let removed = try fixture.command(["credentials", "item", "delete", "--host", fixture.host, fixture.item, "--json"])
                    XCTAssertEqual(removed["status"] as? String, "deleted")
                }
                let final = try fixture.command(["credentials", "vault", "items", "--host", fixture.host, "--json"])
                guard let items = final["items"] as? [[String: Any]] else {
                    throw ProvisioningQualificationError(description: "final inventory returned no items array")
                }
                XCTAssertFalse(items.contains { $0["name"] as? String == fixture.item && $0["state"] as? String == "active" })
                fixture.report["final_inventory"] = final
            } catch {
                fixture.report["cleanup_error"] = String(reflecting: error)
                fixture.report["status"] = "failed"
                failures.append(error)
            }
        }
        fixture.report["finished_at"] = ISO8601DateFormatter().string(from: Date())
        // The XCTest runner owns the assertion verdict; this report never
        // manufactures a pass when a nonthrowing XCTest assertion failed.
        print("provisioning evidence: \(fixture.evidence.path)")
        try fixture.persist(preserving: failures)
    }
}
