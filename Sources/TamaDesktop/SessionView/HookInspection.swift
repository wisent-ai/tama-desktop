import SwiftUI
import WisentDesignSystem

extension SessionView {
    @ViewBuilder
    func hookInspection(_ session: AgentSessionRecord) -> some View {
        WisentAlertPanel(
            tone: .warning, title: "Hook ownership",
            detail: "Inspect the live runtime and end only identity-proven orphan process groups.",
            actions: [
                WisentAction("Inspect hooks and end orphans", kind: .secondary,
                             isEnabled: !model.isPolicyMutationInProgress) {
                    model.inspectRuntime(in: session)
                }
            ]
        )
        if let progress = session.runtime?.hookProgress, !progress.isEmpty {
            WisentAlertPanel(tone: .warning, title: "Hook progress", detail: progress)
        }
        if let inspection = session.runtime?.runningHooks {
            ForEach(inspection.running, id: \.hookPid) { hook in
                WisentAlertPanel(
                    tone: .warning,
                    title: "\(hook.hookId) — \(hook.coreAlive ? "owned" : "orphaned")",
                    detail: hookInspectionDetail(hook)
                )
            }
            if let errors = inspection.errors, !errors.isEmpty {
                WisentAlertPanel(
                    tone: .warning, title: "Hook inspection failed",
                    detail: errors.joined(separator: "\n")
                )
            }
        }
    }

    private func hookInspectionDetail(_ hook: RunningHookRecord) -> String {
        var lines = [
            "Hook pid \(hook.hookPid), core pid \(hook.corePid), hook alive: \(hook.hookAlive)"
        ]
        lines.append(contentsOf: hook.waitingOn.map { "Waiting on \($0.pid): \($0.command)" })
        if let termination = hook.orphanTermination {
            if termination.sent {
                lines.append("Orphan termination signal sent")
            } else if let error = termination.error {
                lines.append("Termination refused: \(error)")
            } else {
                lines.append("Invalid runtime inspection: orphanTermination.sent is false but error is missing; termination cannot be confirmed.")
            }
        }
        return lines.joined(separator: "\n")
    }
}
