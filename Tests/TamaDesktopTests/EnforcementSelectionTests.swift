import Foundation
import Testing
@testable import TamaDesktop

struct EnforcementSelectionTests {
    @Test
    func onlyModeReportsSelectedRowsAsEnforcing() throws {
        let data = Data(#"{"mode":"only","enabled":["pre-write-edit"],"emergencyDisabled":false}"#.utf8)
        let selection = try JSONDecoder().decode(EnforcementSelection.self, from: data)

        #expect(selection.includes("pre-write-edit"))
        #expect(selection.enforces("pre-write-edit"))
        #expect(!selection.includes("block-inline-execution"))
        #expect(!selection.enforces("block-inline-execution"))
    }

    @Test
    func emergencyBypassOverridesMachineSelection() throws {
        let data = Data(#"{"mode":"all","enabled":[],"emergencyDisabled":true}"#.utf8)
        let selection = try JSONDecoder().decode(EnforcementSelection.self, from: data)

        #expect(selection.includes("pre-write-edit"))
        #expect(!selection.enforces("pre-write-edit"))
    }
}
