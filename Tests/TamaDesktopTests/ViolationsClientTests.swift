import Foundation
import Testing
@testable import TamaDesktop

struct ViolationsClientTests {
    @Test
    func parsesAggregateScanReport() throws {
        let json = """
            {
              "repos": [
                {
                  "repo": "/abs/path",
                  "hook": "/abs/hook",
                  "mode": "git",
                  "scannedFiles": 12,
                  "skippedFiles": [{"path": "blob.dat", "reason": "binary content"}],
                  "violations": [
                    {
                      "hook": "pre-write-edit",
                      "rule": "File would be N lines (max N)",
                      "path": "src/a.js",
                      "message": "BLOCKED: File would be 350 lines (max 300). Split it."
                    },
                    {
                      "hook": "pre-write-edit",
                      "rule": "Folder has N files (max N)",
                      "path": "src",
                      "message": "Folder has 9 files (max 5). Move files into sub-folders or consolidate."
                    },
                    {
                      "hook": "pre-write-edit",
                      "rule": "File would be N lines (max N)",
                      "path": "src/b.js",
                      "message": "BLOCKED: File would be 410 lines (max 300). Split it."
                    }
                  ],
                  "errors": [{"path": "src/c.js", "message": "hook exited 1: boom"}],
                  "via": "repo"
                }
              ],
              "problems": [{"owner": "me", "repo": null, "error": "gh not authenticated"}],
              "totals": {"repositories": 1, "violations": 3, "problems": 1}
            }
            """
        let report = try JSONDecoder().decode(ViolationReport.self, from: Data(json.utf8))

        #expect(report.totals == ViolationTotals(repositories: 1, violations: 3, problems: 1))
        #expect(report.scannedFiles == 12)
        #expect(report.skippedFiles == 1)
        #expect(report.scanErrors == 1)
        #expect(report.problems.first?.error == "gh not authenticated")

        let repo = try #require(report.repos.first)
        #expect(repo.id == "/abs/path")
        #expect(repo.errors.first?.message == "hook exited 1: boom")
        #expect(repo.skippedFiles.first?.reason == "binary content")

        let groups = repo.ruleGroups
        #expect(groups.map(\.rule) == [
            "File would be N lines (max N)",
            "Folder has N files (max N)",
        ])
        #expect(groups.first?.violations.map(\.path) == ["src/a.js", "src/b.js"])
        #expect(groups.last?.violations.map(\.path) == ["src"])
    }

    @Test
    func parsesCleanReportWithoutViolations() throws {
        let json = """
            {
              "repos": [
                {
                  "repo": "/abs/path",
                  "hook": "/abs/hook",
                  "mode": "walk",
                  "scannedFiles": 4,
                  "skippedFiles": [],
                  "violations": [],
                  "errors": []
                }
              ],
              "problems": [],
              "totals": {"repositories": 1, "violations": 0, "problems": 0}
            }
            """
        let report = try JSONDecoder().decode(ViolationReport.self, from: Data(json.utf8))

        #expect(report.totals.violations == 0)
        #expect(report.repos.first?.ruleGroups.isEmpty == true)
        #expect(report.scanErrors == 0)
    }
}
