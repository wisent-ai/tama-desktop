import SwiftUI
import WisentDesignSystem

extension SessionView {
    @ViewBuilder
    func adapterStatus(_ session: AgentSessionRecord) -> some View {
        if session.agentId == "omp" {
            if let digest = session.runtime?.adapterDigest {
                WisentField(label: "Loaded OMP adapter", value: digest)
            } else {
                WisentAlertPanel(
                    tone: .warning,
                    title: "Loaded adapter identity unavailable",
                    detail:
                        "This session does not report its JavaScript adapter digest. Its policy release alone does not prove that the adapter has been updated."
                )
            }
            if session.runtime?.adapterReloadSupported != true {
                WisentAlertPanel(
                    tone: .warning,
                    title: "Remote adapter reload unavailable",
                    detail:
                        "Use tama_reload_hook_runtime in this existing OMP terminal. The Reload adapter action will refuse until the loaded extension supports session control."
                )
            }
            if let error = session.runtime?.lastReloadError {
                WisentAlertPanel(
                    tone: .danger,
                    title: "Last runtime or adapter reload failed",
                    detail: error
                )
            }
            if let editors = session.runtime?.gitEditors, !editors.configured {
                if let error = editors.error {
                    WisentAlertPanel(
                        tone: .danger,
                        title: "Agent Git editors not configured",
                        detail:
                            "\(error) Ordinary tool calls are refused until `tama hook pre-bash --git-environment` succeeds for this session."
                    )
                } else {
                    WisentAlertPanel(
                        tone: .danger,
                        title: "Agent Git editors not configured",
                        detail:
                            "The adapter reported a failed Git editor configuration without its cause, which breaks its status contract; `tama sessions --json` shows the record it published."
                    )
                }
            } else if session.runtime?.gitEditors == nil {
                WisentAlertPanel(
                    tone: .warning,
                    title: "Agent Git editors not reported",
                    detail:
                        "This session's adapter predates managed Git editors, so a Git command that opens an editor can wait for a keyboard. Reload adapter (`tama sessions reload --session ID`) loads the installed one."
                )
            }
        }
    }
}
