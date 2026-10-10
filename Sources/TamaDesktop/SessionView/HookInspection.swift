import SwiftUI
import WisentDesignSystem

extension SessionView {
    @ViewBuilder
    func hookInspection(_ session: AgentSessionRecord) -> some View {
        WisentAlertPanel(
            tone: .warning, title: "Hook ownership",
            detail: "Inspect supervisor lifetime ownership and any legacy orphan diagnostics.",
            actions: [
                WisentAction(
                    "Inspect hooks and end orphans", kind: .secondary,
                    isEnabled: !model.isPolicyMutationInProgress
                ) {
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
                    title: hook.hookId,
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
        var lines = ["Hook pid \(hook.hookPid), core pid \(hook.corePid)"]
        if let ownership = hook.ownershipState {
            lines.append(ownership)
        }
        if let alive = hook.hookAlive {
            lines.append("Hook alive: \(alive)")
        } else {
            lines.append("Hook liveness was not established")
        }
        if let alive = hook.coreAlive {
            lines.append("Core alive: \(alive)")
        } else {
            lines.append("Core process was not separately inspected")
        }
        if let descendants = hook.waitingOn {
            lines.append(contentsOf: descendants.map { "Waiting on \($0.pid): \($0.command)" })
        }
        if let termination = hook.orphanTermination {
            if termination.sent {
                lines.append("Orphan termination signal sent")
            } else if let error = termination.error {
                lines.append("Termination refused: \(error)")
            } else {
                lines.append(
                    "Invalid runtime inspection: orphanTermination.sent is false but error is missing; termination cannot be confirmed."
                )
            }
        }
        return lines.joined(separator: "\n")
    }
}
