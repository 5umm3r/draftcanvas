import Foundation

enum AccountKind: Equatable {
    case chatgpt, apiKey, amazonBedrock, unauthenticated, unknown

    var japaneseLabel: String {
        switch self {
        case .chatgpt: return "ChatGPT"
        case .apiKey: return String(localized: "APIキー")
        case .amazonBedrock: return "Amazon Bedrock"
        case .unauthenticated: return String(localized: "未ログイン")
        case .unknown: return String(localized: "不明")
        }
    }

    var systemImageName: String {
        switch self {
        case .chatgpt:          return "person.crop.circle.fill"
        case .apiKey:           return "key.fill"
        case .amazonBedrock:    return "cloud.fill"
        case .unauthenticated:  return "person.crop.circle.badge.questionmark"
        case .unknown:          return "questionmark.circle"
        }
    }
}

struct RateLimitsSnapshot: Sendable, Equatable {
    var primaryPercentLabel: String
    var primaryRemainingFraction: Double?
    var primaryResetText: String?
    var primaryResetDate: Date?
    var secondaryPercentLabel: String
    var secondaryRemainingFraction: Double?
    var secondaryResetText: String?
    var secondaryResetDate: Date?

    static func parse(_ params: [String: Any]) -> RateLimitsSnapshot {
        let rateLimits = CodexAccountUsageStatus.preferredRateLimits(from: params)
        let primary = CodexAccountUsageStatus.usageStatus(prefix: "5h", window: rateLimits?["primary"] as? [String: Any])
        let secondary = CodexAccountUsageStatus.usageStatus(prefix: "weekly", window: rateLimits?["secondary"] as? [String: Any])
        return RateLimitsSnapshot(
            primaryPercentLabel: primary.percentLabel,
            primaryRemainingFraction: primary.remainingFraction,
            primaryResetText: primary.resetText,
            primaryResetDate: primary.resetDate,
            secondaryPercentLabel: secondary.percentLabel,
            secondaryRemainingFraction: secondary.remainingFraction,
            secondaryResetText: secondary.resetText,
            secondaryResetDate: secondary.resetDate
        )
    }
}

struct CodexAccountUsageStatus: Equatable {
    var accountLabel: String
    var planLabel: String
    var primaryUsagePrefix: String
    var primaryUsagePercentLabel: String
    var secondaryUsagePrefix: String
    var secondaryUsagePercentLabel: String
    var primaryUsageRemainingFraction: Double?
    var secondaryUsageRemainingFraction: Double?
    var accountEmail: String?
    var accountKind: AccountKind
    var primaryResetText: String?
    var secondaryResetText: String?
    var primaryResetDate: Date?
    var secondaryResetDate: Date?

    static let unavailable = CodexAccountUsageStatus(
        accountLabel: String(localized: "アカウント未取得"),
        planLabel: "-",
        primaryUsagePrefix: "5h",
        primaryUsagePercentLabel: "-",
        secondaryUsagePrefix: "weekly",
        secondaryUsagePercentLabel: "-",
        primaryUsageRemainingFraction: nil,
        secondaryUsageRemainingFraction: nil,
        accountEmail: nil,
        accountKind: .unauthenticated,
        primaryResetText: nil,
        secondaryResetText: nil,
        primaryResetDate: nil,
        secondaryResetDate: nil
    )

    static func parse(accountResponse: [String: Any], rateLimitsResponse: [String: Any]) -> CodexAccountUsageStatus {
        let account = accountResponse["account"] as? [String: Any]
        let accountType = account?["type"] as? String
        let planLabel = (account?["planType"] as? String)
            ?? planType(from: rateLimitsResponse)
            ?? "-"

        let accountKind: AccountKind
        let accountEmail: String?
        let accountLabel: String
        switch accountType {
        case "chatgpt":
            accountKind = .chatgpt
            accountEmail = account?["email"] as? String
            accountLabel = accountEmail ?? "ChatGPT"
        case "apiKey":
            accountKind = .apiKey
            accountEmail = nil
            accountLabel = "API Key"
        case "amazonBedrock":
            accountKind = .amazonBedrock
            accountEmail = nil
            accountLabel = "Amazon Bedrock"
        case .some(let value):
            accountKind = .unknown
            accountEmail = nil
            accountLabel = value
        case .none:
            accountKind = .unauthenticated
            accountEmail = nil
            accountLabel = String(localized: "未ログイン")
        }

        let rateLimits = preferredRateLimits(from: rateLimitsResponse)
        let primaryUsage = usageStatus(prefix: "5h", window: rateLimits?["primary"] as? [String: Any])
        let secondaryUsage = usageStatus(prefix: "weekly", window: rateLimits?["secondary"] as? [String: Any])
        return CodexAccountUsageStatus(
            accountLabel: accountLabel,
            planLabel: planLabel,
            primaryUsagePrefix: primaryUsage.prefix,
            primaryUsagePercentLabel: primaryUsage.percentLabel,
            secondaryUsagePrefix: secondaryUsage.prefix,
            secondaryUsagePercentLabel: secondaryUsage.percentLabel,
            primaryUsageRemainingFraction: primaryUsage.remainingFraction,
            secondaryUsageRemainingFraction: secondaryUsage.remainingFraction,
            accountEmail: accountEmail,
            accountKind: accountKind,
            primaryResetText: primaryUsage.resetText,
            secondaryResetText: secondaryUsage.resetText,
            primaryResetDate: primaryUsage.resetDate,
            secondaryResetDate: secondaryUsage.resetDate
        )
    }

    fileprivate static func preferredRateLimits(from response: [String: Any]) -> [String: Any]? {
        if
            let byID = response["rateLimitsByLimitId"] as? [String: Any],
            let codex = byID["codex"] as? [String: Any]
        {
            return codex
        }
        return response["rateLimits"] as? [String: Any]
    }

    private static func planType(from response: [String: Any]) -> String? {
        preferredRateLimits(from: response)?["planType"] as? String
    }

    fileprivate static func usageStatus(
        prefix: String,
        window: [String: Any]?
    ) -> (prefix: String, percentLabel: String, remainingFraction: Double?, resetText: String?, resetDate: Date?) {
        let resetDate = window.flatMap { parseResetDate(from: $0) }
        let resetText = resetDate.flatMap { formatRelativeReset(to: $0) }
        guard let usedPercent = numericValue(window?["usedPercent"]) else {
            return (prefix, "-", nil, resetText, resetDate)
        }
        let remainingPercent = min(100, max(0, 100 - usedPercent))
        return (prefix, "\(Int(remainingPercent.rounded()))%", remainingPercent / 100, resetText, resetDate)
    }

    private static func parseResetDate(from window: [String: Any]) -> Date? {
        let keys = ["resetsAt", "resetAt", "nextResetAt", "resetsAtUTC", "resetTime"]
        for key in keys {
            guard let value = window[key] else { continue }
            if let str = value as? String {
                for options: ISO8601DateFormatter.Options in [
                    [.withInternetDateTime, .withFractionalSeconds],
                    [.withInternetDateTime]
                ] {
                    let f = ISO8601DateFormatter()
                    f.formatOptions = options
                    if let date = f.date(from: str) { return date }
                }
            }
            if let num = numericValue(value) {
                // > 1e12 ならミリ秒判定、それ以外はUNIX秒
                let ts = num > 1e12 ? num / 1000 : num
                return Date(timeIntervalSince1970: ts)
            }
        }
        return nil
    }

    private static func formatRelativeReset(to target: Date) -> String? {
        // UTC差分秒で計算。タイムゾーン変換不要
        let diff = target.timeIntervalSince(Date())
        if diff <= 60 { return String(localized: "もうすぐ") }
        let totalMin = Int(diff / 60)
        let hours = totalMin / 60
        let mins = totalMin % 60
        if hours < 1 { return String(localized: "あと\(totalMin)m") }
        if hours < 24 { return mins > 0 ? String(localized: "あと\(hours)h\(mins)m") : String(localized: "あと\(hours)h") }
        let days = hours / 24
        let hrs = hours % 24
        return hrs > 0 ? String(localized: "あと\(days)d\(hrs)h") : String(localized: "あと\(days)d")
    }

    private static func numericValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    mutating func apply(_ snapshot: RateLimitsSnapshot) {
        primaryUsagePercentLabel = snapshot.primaryPercentLabel
        primaryUsageRemainingFraction = snapshot.primaryRemainingFraction
        primaryResetText = snapshot.primaryResetText
        primaryResetDate = snapshot.primaryResetDate
        secondaryUsagePercentLabel = snapshot.secondaryPercentLabel
        secondaryUsageRemainingFraction = snapshot.secondaryRemainingFraction
        secondaryResetText = snapshot.secondaryResetText
        secondaryResetDate = snapshot.secondaryResetDate
    }

    var isChatGPTFreePlan: Bool {
        guard accountKind == .chatgpt else { return false }
        let normalized = planLabel.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
        return normalized == "free" || normalized == "freetier" || normalized == "freeplan"
    }

    var isUnsupportedAccountKind: Bool {
        accountKind == .apiKey || accountKind == .amazonBedrock
    }

    var shouldShowUsagePills: Bool {
        accountKind == .chatgpt
    }
}
