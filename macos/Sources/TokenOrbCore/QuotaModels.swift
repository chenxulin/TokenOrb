import Foundation

public struct QuotaWindow: Equatable, Sendable {
    public var usedPercent: Double?
    public var windowMinutes: Int?
    public var resetsAt: Date?

    public init(
        usedPercent: Double? = nil,
        windowMinutes: Int? = nil,
        resetsAt: Date? = nil
    ) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }

    public var isMeaningful: Bool {
        usedPercent != nil || windowMinutes != nil || resetsAt != nil
    }

    public var remainingPercent: Double {
        min(100, max(0, 100 - (usedPercent ?? 0)))
    }

    public func merged(with update: QuotaWindow?) -> QuotaWindow {
        guard let update else { return self }
        return QuotaWindow(
            usedPercent: update.usedPercent ?? usedPercent,
            windowMinutes: update.windowMinutes ?? windowMinutes,
            resetsAt: update.resetsAt ?? resetsAt
        )
    }
}

public struct QuotaCredits: Equatable, Sendable {
    public var hasCredits: Bool?
    public var unlimited: Bool?
    public var balance: String?

    public init(
        hasCredits: Bool? = nil,
        unlimited: Bool? = nil,
        balance: String? = nil
    ) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }

    public func merged(with update: QuotaCredits?) -> QuotaCredits {
        guard let update else { return self }
        return QuotaCredits(
            hasCredits: update.hasCredits ?? hasCredits,
            unlimited: update.unlimited ?? unlimited,
            balance: update.balance?.isEmpty == false ? update.balance : balance
        )
    }
}

public struct QuotaSnapshot: Equatable, Sendable {
    private static let fiveHourWindowMinutes = 5 * 60
    private static let weeklyWindowMinutes = 7 * 24 * 60

    public var limitID: String?
    public var limitName: String?
    public var primary: QuotaWindow?
    public var secondary: QuotaWindow?
    public var credits: QuotaCredits?
    public var planType: String?
    public var rateLimitReachedType: String?
    public var spendControlReached: Bool?
    public var capturedAt: Date
    public var source: String
    public var isLive: Bool

    public init(
        limitID: String? = nil,
        limitName: String? = nil,
        primary: QuotaWindow? = nil,
        secondary: QuotaWindow? = nil,
        credits: QuotaCredits? = nil,
        planType: String? = nil,
        rateLimitReachedType: String? = nil,
        spendControlReached: Bool? = nil,
        capturedAt: Date = Date(),
        source: String,
        isLive: Bool
    ) {
        self.limitID = limitID
        self.limitName = limitName
        self.primary = primary
        self.secondary = secondary
        self.credits = credits
        self.planType = planType
        self.rateLimitReachedType = rateLimitReachedType
        self.spendControlReached = spendControlReached
        self.capturedAt = capturedAt
        self.source = source
        self.isLive = isLive
    }

    public var hasQuotaData: Bool {
        primary?.isMeaningful == true
            || secondary?.isMeaningful == true
            || credits != nil
    }

    public var orbDisplayWindow: QuotaWindow? {
        let windows = [primary, secondary]
            .compactMap { $0 }
            .filter { $0.usedPercent != nil }
        let fiveHour = windows.first { $0.windowMinutes == Self.fiveHourWindowMinutes }
        let weekly = windows.first { $0.windowMinutes == Self.weeklyWindowMinutes }

        if let weekly, weekly.remainingPercent <= 0 {
            return weekly
        }
        if let fiveHour {
            return fiveHour
        }
        if let weekly {
            return weekly
        }
        return nil
    }

    public func merged(with update: QuotaSnapshot) -> QuotaSnapshot {
        QuotaSnapshot(
            limitID: update.limitID?.isEmpty == false ? update.limitID : limitID,
            limitName: update.limitName?.isEmpty == false ? update.limitName : limitName,
            primary: primary.map { $0.merged(with: update.primary) } ?? update.primary,
            secondary: secondary.map { $0.merged(with: update.secondary) } ?? update.secondary,
            credits: credits.map { $0.merged(with: update.credits) } ?? update.credits,
            planType: update.planType?.isEmpty == false ? update.planType : planType,
            rateLimitReachedType: update.rateLimitReachedType?.isEmpty == false
                ? update.rateLimitReachedType
                : rateLimitReachedType,
            spendControlReached: update.spendControlReached ?? spendControlReached,
            capturedAt: update.capturedAt,
            source: update.source.isEmpty ? source : update.source,
            isLive: isLive || update.isLive
        )
    }

    public static func demo(now: Date = Date()) -> QuotaSnapshot {
        QuotaSnapshot(
            limitID: "codex",
            primary: QuotaWindow(
                usedPercent: 31,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(2 * 3600 + 27 * 60)
            ),
            secondary: QuotaWindow(
                usedPercent: 54,
                windowMinutes: 10_080,
                resetsAt: now.addingTimeInterval(4 * 86_400 + 7 * 3600)
            ),
            credits: QuotaCredits(
                hasCredits: true,
                unlimited: false,
                balance: "2226.6674375000"
            ),
            planType: "plus",
            capturedAt: now,
            source: "演示数据",
            isLive: true
        )
    }
}

public enum QuotaFormatting {
    private static let weeklyWindowMinutes = 7 * 24 * 60
    private static let weeklyResetInterval: TimeInterval = 7 * 24 * 60 * 60

    public static func roundedPercent(_ value: Double) -> Int {
        Int(value.rounded(.toNearestOrEven))
    }

    public static func windowName(_ window: QuotaWindow?) -> String {
        guard let minutes = window?.windowMinutes else { return "额度" }
        switch minutes {
        case 300:
            return "5小时"
        case 10_080:
            return "7天"
        default:
            if minutes > 0, minutes.isMultiple(of: 1_440) {
                return "\(minutes / 1_440)天"
            }
            if minutes > 0, minutes.isMultiple(of: 60) {
                return "\(minutes / 60)小时"
            }
            return "\(minutes)分钟"
        }
    }

    public static func resolvedReset(_ window: QuotaWindow?, now: Date = Date()) -> Date? {
        guard var reset = window?.resetsAt else { return nil }
        if window?.windowMinutes == weeklyWindowMinutes, reset <= now {
            let elapsed = now.timeIntervalSince(reset)
            let cycles = floor(elapsed / weeklyResetInterval) + 1
            reset = reset.addingTimeInterval(cycles * weeklyResetInterval)
        }
        return reset
    }

    public static func resetDateText(_ window: QuotaWindow?, now: Date = Date()) -> String {
        guard let reset = resolvedReset(window, now: now) else { return "时间未知" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: reset)
    }

    public static func resetCountdownText(
        _ window: QuotaWindow?,
        now: Date = Date()
    ) -> String {
        guard let reset = resolvedReset(window, now: now) else { return "" }
        let remaining = reset.timeIntervalSince(now)
        let days = Int(remaining) / 86_400
        let hours = (Int(remaining) % 86_400) / 3_600
        let minutes = (Int(remaining) % 3_600) / 60
        let seconds = Int(remaining) % 60

        if remaining <= 0 {
            return "等待 Codex 刷新"
        }
        if remaining >= 86_400 {
            return "\(days)天\(hours)小时后"
        }
        if remaining >= 3_600 {
            return "\(hours)小时\(minutes)分后"
        }
        return "\(max(0, minutes))分\(max(0, seconds))秒后"
    }

    public static func planName(_ plan: String?) -> String {
        guard let plan else { return "未知套餐" }
        let normalized = plan.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "未知套餐" }
        switch normalized.lowercased() {
        case "plus":
            return "ChatGPT Plus"
        case "pro":
            return "ChatGPT Pro"
        case "team":
            return "ChatGPT Team"
        case "business":
            return "ChatGPT Business"
        case "enterprise":
            return "ChatGPT Enterprise"
        case "edu":
            return "ChatGPT Edu"
        default:
            return normalized
        }
    }

    public static func credits(_ value: QuotaCredits?) -> String {
        guard let value, value.hasCredits != false else { return "0" }
        if value.unlimited == true {
            return "无限"
        }
        guard let balance = value.balance, !balance.isEmpty else {
            return "可用"
        }
        guard let number = Decimal(string: balance) else {
            return balance
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: number as NSDecimalNumber) ?? balance
    }

    public static func dataSource(_ snapshot: QuotaSnapshot?) -> String {
        snapshot?.isLive == true ? "实时数据" : "本地快照"
    }

    public static func capturedAtText(_ snapshot: QuotaSnapshot?) -> String {
        guard let snapshot else { return "尚未更新" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: snapshot.capturedAt)
    }
}
