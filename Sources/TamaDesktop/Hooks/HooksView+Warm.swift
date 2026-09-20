import SwiftUI
import WisentDesignSystem

extension HooksView {
    /// What this machine's gates cost to start, and the button that pays it.
    ///
    /// The panel exists because a hook timeout is indistinguishable, from the
    /// outside, from a policy refusal: on 2026-09-20 a stop hook whose first
    /// execution spent 147 seconds in the operating system's signature
    /// assessment blocked a finished turn with `timed out after 10s`. Running
    /// each binary once here moves that cost out of the next live event, and
    /// the measurements say which binaries were slow and which cannot run.
    var warmPanel: some View {
        WisentPanel {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                HStack(spacing: WisentDesign.Space.x3) {
                    Text("HOOK BINARIES")
                        .font(WisentTypeScale.eyebrow())
                        .tracking(0.6)
                        .foregroundStyle(WisentDesign.muted)
                    if let report = warmModel.report {
                        WisentStatusChip(
                            text: "\(report.warmed) warmed",
                            tone: report.unusable > 0 ? .danger
                                : (report.cold > 0 ? .warning : .success)
                        )
                    } else {
                        WisentStatusChip(text: "Not measured", tone: .neutral)
                    }
                    Spacer(minLength: WisentDesign.Space.x2)
                    WisentActionButton(
                        action: WisentAction(
                            "Warm hook binaries",
                            symbol: "bolt.horizontal",
                            kind: .secondary,
                            isEnabled: !warmModel.isWorking
                        ) {
                            warmModel.warm()
                        }
                    )
                }
                Text("A binary that has never run pays the operating system's first-run check inside the next hook event, where it reads as a timeout and refuses the turn. Running each one here pays that once and reports what it cost.")
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(warmModel.attention) { row in
                    HStack(spacing: WisentDesign.Space.x2) {
                        Text(row.id)
                            .font(WisentTypeScale.identifierSmall())
                            .foregroundStyle(WisentDesign.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        WisentStatusChip(
                            text: row.isUsable ? "First run \(row.elapsedMs) ms" : row.state,
                            tone: row.isUsable ? .warning : .danger
                        )
                        Text(row.path)
                            .font(WisentTypeScale.caption())
                            .foregroundStyle(WisentDesign.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(height: WisentAppLayout.tableRowHeight, alignment: .leading)
                }
                WisentMutationBar(outcome: warmModel.outcome) {
                    warmModel.clearOutcome()
                }
            }
        }
    }
}
