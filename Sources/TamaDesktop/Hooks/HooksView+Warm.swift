import SwiftUI
import WisentDesignSystem

extension HooksView {
    /// What this machine's gates cost to start, and the button that pays it.
    ///
    /// The panel exists because that cost lands inside a live event: on
    /// 2026-09-20 a stop hook's first execution spent 147 seconds in the
    /// operating system's signature assessment, and back then the engine
    /// killed it at ten seconds and called that a refusal. The engine waits
    /// now, so the same first run would be 147 seconds somebody sits through.
    /// Running each binary once here moves that cost out of the next live
    /// event, and the measurements say which binary cost the most and which
    /// cannot run at all.
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
                            tone: report.unusable > 0 ? .danger : .success
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
                Text("A binary that has never run pays the operating system's first-run check inside the next hook event, where the whole turn waits for it. Running each one here pays that once and reports what it cost.")
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
