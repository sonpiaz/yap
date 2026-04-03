import Foundation

/// Simple local usage counter. No server, no analytics SDK.
/// Counts transcriptions per month, stored in UserDefaults.
enum UsageTracker {
    private static let defaults = UserDefaults.standard
    private static let monthlyKey = "usage_"

    /// Call after each successful transcription.
    static func recordTranscription() {
        let key = currentMonthKey()
        let count = defaults.integer(forKey: key) + 1
        defaults.set(count, forKey: key)
    }

    /// Returns transcription count for current month.
    static var currentMonthCount: Int {
        defaults.integer(forKey: currentMonthKey())
    }

    /// Returns usage stats for display.
    static var stats: [(month: String, count: Int)] {
        let allKeys = defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(monthlyKey) }
            .sorted()
            .reversed()
        return allKeys.prefix(12).map { key in
            let month = String(key.dropFirst(monthlyKey.count))
            return (month: month, count: defaults.integer(forKey: key))
        }
    }

    private static func currentMonthKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return monthlyKey + f.string(from: Date())
    }
}
