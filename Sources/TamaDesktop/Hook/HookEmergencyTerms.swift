import SwiftUI
import WisentDesignSystem

/// The terms an emergency disable is thrown with: why, and for how many
/// minutes. The switch records them with the account that threw it, and the
/// hooks run again once the minutes have passed, so a guard switched off once
/// does not stay off unseen.
struct HookEmergencyTerms: Equatable {
    var reason = ""
    var minutes = 60

    /// The reason as the switch records it, nil while none is given.
    var statedReason: String? {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Whether the switch may be thrown with these terms.
    var isComplete: Bool { statedReason != nil && minutes > 0 }
}

/// The reason and duration fields a disable dialog asks for.
struct HookEmergencyTermsFields: View {
    @Binding var terms: HookEmergencyTerms

    var body: some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
            TextField("Why every policy must be off", text: $terms.reason)
                .textFieldStyle(.roundedBorder)
            Stepper(value: $terms.minutes, in: 5...1440, step: 5) {
                Text("Policies return by themselves after \(terms.minutes) minutes")
                    .font(WisentTypeScale.body())
            }
            if terms.statedReason == nil {
                Text("The switch records why it was thrown; give a reason to continue.")
                    .font(WisentTypeScale.caption())
                    .foregroundStyle(WisentDesign.secondary)
            }
        }
        .padding(.horizontal, WisentDesign.Space.x4)
    }
}

extension HookEmergencySwitch.Record {
    /// The switch said for a person: who set it, why, since and until when,
    /// and what its record leaves unsaid.
    var sentence: String {
        var parts = ["Every Tama hook is off on this machine"]
        if let setBy { parts.append("set by \(setBy)") }
        if let changedAt { parts.append("since \(changedAt)") }
        if let reason { parts.append("because \(reason)") }
        if let expiresAt { parts.append("until \(expiresAt), when it lifts itself") }
        var text = parts.joined(separator: ", ") + "."
        if !gaps.isEmpty {
            text += " Its record \(gaps.joined(separator: ", "))."
        }
        return text
    }
}
