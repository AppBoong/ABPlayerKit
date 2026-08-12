import Foundation

/// Locale-aware formatting for a playback rate value — replaces
/// `String(format: "%g", rate)`, which always renders a `.` decimal
/// separator regardless of locale. A pure value type so it can be table
/// tested against explicit locales; the view supplies `.autoupdatingCurrent`.
struct ABRateFormatter {
    let locale: Locale

    /// `0.5` → `"0.5"` (`en`), `"0,5"` (`de`). Whole numbers drop the
    /// fractional part (`"1"`, not `"1.0"`); at most two fraction digits;
    /// never grouped.
    func string(from rate: Float) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: rate)) ?? "\(rate)"
    }
}
