import Foundation

/// The label/value rows a plan or model-service document is rendered as.
extension PolicyInspectionClient {
    static func flatten(name: String, value: Any?) -> [InstallPlanField] {
        switch value {
        case let text as String:
            return [InstallPlanField(label: humanized(name), value: text)]
        case is NSNull, .none:
            // A target the plan reports as null is unconfigured, and saying so
            // is the fact; omitting the row would hide it.
            return [InstallPlanField(label: humanized(name), value: "Not configured")]
        case let number as NSNumber:
            // A boolean and a number share one Objective-C type, and the Swift
            // bridge reads any non-zero number as `true`, so the encoded type
            // is checked rather than the cast.
            return [
                InstallPlanField(
                    label: humanized(name),
                    value: CFGetTypeID(number) == CFBooleanGetTypeID()
                        ? (number.boolValue ? "yes" : "no")
                        : number.stringValue
                )
            ]
        case let list as [Any]:
            let joined = list.compactMap { $0 as? String }.joined(separator: ", ")
            guard !joined.isEmpty else { return [] }
            return [InstallPlanField(label: humanized(name), value: joined)]
        case let nested as [String: Any]:
            return nested.keys.sorted().flatMap { key in
                flatten(name: key, value: nested[key])
            }
        default:
            return []
        }
    }

    /// `codexSettings` reads as CODEX SETTINGS in a field label; the plan's own
    /// camel case would read as a variable name the operator never typed.
    static func humanized(_ name: String) -> String {
        var words: [String] = []
        var current = ""
        for character in name {
            if character.isUppercase, !current.isEmpty {
                words.append(current)
                current = String(character)
            } else if character == "-" || character == "_" {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words.joined(separator: " ")
    }
}
