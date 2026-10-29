import Foundation

struct WatchUser: Codable, Identifiable, Hashable {
    let id: Int
    let email: String
}

struct WatchKey: Codable, Identifiable {
    let id: Int
    let name: String
}

struct UsageScope: Codable, Equatable {
    var userID: Int?
    var email: String?
    var keyID: Int?
    var keyName: String?

    var title: String { keyName ?? (userID == nil ? "全部用户" : "全部 Key") }
    var subtitle: String { email ?? "全站统计" }
}

struct QuotaWindow: Codable {
    let remainingPercent: Double?
    let resetsAt: String?

    var percent: Double? {
        guard let value = remainingPercent, value.isFinite else { return nil }
        return min(100, max(0, value))
    }
}

struct PoolAccount: Codable, Identifiable {
    let id: Int
    let name: String
    let status: String
    let stale: Bool
    let updatedAt: String?
    let fiveHour: QuotaWindow
    let sevenDay: QuotaWindow
}

struct AccountsResponse: Codable {
    let accounts: [PoolAccount]
    let fetchedAt: String
}

struct DailyUsage: Codable {
    struct Tokens: Codable {
        let total: Int64
        let input: Int64
        let output: Int64
        let cacheRead: Int64
        let cacheCreation: Int64
    }

    let date: String
    let timezone: String
    let userId: Int?
    let apiKeyId: Int?
    let requests: Int64
    let tokens: Tokens
    let updatedAt: String

    var isToday: Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: timezone) ?? TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return date == formatter.string(from: Date())
    }
}

enum WatchFormat {
    static func timestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    static func compact(_ value: Int64) -> (number: String, unit: String) {
        if value >= 1_000_000 { return (String(format: "%.2f", Double(value) / 1_000_000), "M") }
        if value >= 1_000 { return (String(format: "%.1f", Double(value) / 1_000), "K") }
        return (String(value), "")
    }
}
