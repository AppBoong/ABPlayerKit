import Foundation

enum ABControlsLocalization {
    static func string(_ key: String, localization: String? = nil) -> String {
        let bundle: Bundle
        if let localization,
           let path = Bundle.module.path(forResource: localization, ofType: "lproj"),
           let localizedBundle = Bundle(path: path) {
            bundle = localizedBundle
        } else {
            bundle = .module
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: string(key),
            locale: Locale.current,
            arguments: arguments
        )
    }

    static func spokenTime(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.calendar = Calendar.autoupdatingCurrent
        formatter.allowedUnits = interval >= 3_600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.unitsStyle = .spellOut
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: max(0, interval)) ?? "0"
    }
}
