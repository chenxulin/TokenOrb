import Foundation

public enum QuotaParser {
    public static func object(from data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    public static func object(from json: String) -> [String: Any]? {
        object(from: Data(json.utf8))
    }

    public static func snapshot(
        fromRateLimits limits: [String: Any],
        source: String,
        isLive: Bool
    ) -> QuotaSnapshot? {
        let snapshot = QuotaSnapshot(
            limitID: string(any(in: limits, keys: ["limitId", "limit_id"])),
            limitName: string(any(in: limits, keys: ["limitName", "limit_name"])),
            primary: window(dictionary(any(in: limits, keys: ["primary"]))),
            secondary: window(dictionary(any(in: limits, keys: ["secondary"]))),
            credits: credits(dictionary(any(in: limits, keys: ["credits"]))),
            planType: string(any(in: limits, keys: ["planType", "plan_type"])),
            rateLimitReachedType: string(
                any(in: limits, keys: ["rateLimitReachedType", "rate_limit_reached_type"])
            ),
            spendControlReached: bool(
                any(in: limits, keys: ["spendControlReached", "spend_control_reached"])
            ),
            capturedAt: Date(),
            source: source,
            isLive: isLive
        )
        return snapshot.hasQuotaData ? snapshot : nil
    }

    public static func localEvent(from jsonLine: String) -> QuotaSnapshot? {
        guard
            let root = object(from: jsonLine),
            let payload = dictionary(root["payload"])
        else {
            return nil
        }

        if let type = string(payload["type"]), type.caseInsensitiveCompare("token_count") != .orderedSame {
            return nil
        }

        guard
            let limits = dictionary(any(in: payload, keys: ["rate_limits", "rateLimits"])),
            var snapshot = snapshot(
                fromRateLimits: limits,
                source: "本地会话快照",
                isLive: false
            )
        else {
            return nil
        }

        if let timestamp = date(root["timestamp"]) {
            snapshot.capturedAt = timestamp
        }
        return snapshot
    }

    public static func findRateLimits(in value: Any, depth: Int = 0) -> [String: Any]? {
        guard depth <= 4 else { return nil }
        if let object = value as? [String: Any] {
            if let direct = dictionary(any(in: object, keys: ["rateLimits", "rate_limits"])) {
                return direct
            }
            if object["primary"] != nil || object["secondary"] != nil {
                return object
            }
            for key in ["result", "params", "account", "data"] {
                if let nested = object[key],
                   let found = findRateLimits(in: nested, depth: depth + 1) {
                    return found
                }
            }
        }
        return nil
    }

    public static func any(in dictionary: [String: Any], keys: [String]) -> Any? {
        for key in keys where dictionary[key] != nil {
            return dictionary[key]
        }
        return nil
    }

    public static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    public static func string(_ value: Any?) -> String? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        if let string = value as? String { return string }
        return String(describing: value)
    }

    public static func double(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let text as String:
            return Double(text)
        default:
            return nil
        }
    }

    public static func int(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let text as String:
            return Int(text)
        default:
            return nil
        }
    }

    public static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let number as NSNumber:
            return number.boolValue
        case let text as String:
            switch text.lowercased() {
            case "true", "1":
                return true
            case "false", "0":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private static func window(_ data: [String: Any]?) -> QuotaWindow? {
        guard let data else { return nil }
        let result = QuotaWindow(
            usedPercent: double(any(in: data, keys: ["usedPercent", "used_percent"])),
            windowMinutes: int(
                any(
                    in: data,
                    keys: ["windowDurationMins", "window_minutes", "windowMinutes"]
                )
            ),
            resetsAt: date(any(in: data, keys: ["resetsAt", "resets_at"]))
        )
        return result.isMeaningful ? result : nil
    }

    private static func credits(_ data: [String: Any]?) -> QuotaCredits? {
        guard let data else { return nil }
        return QuotaCredits(
            hasCredits: bool(any(in: data, keys: ["hasCredits", "has_credits"])),
            unlimited: bool(data["unlimited"]),
            balance: string(data["balance"])
        )
    }

    private static func date(_ value: Any?) -> Date? {
        if let number = double(value) {
            return Date(timeIntervalSince1970: number)
        }
        guard let text = value as? String else { return nil }
        if let seconds = Double(text) {
            return Date(timeIntervalSince1970: seconds)
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = fractional.date(from: text) {
            return parsed
        }
        return ISO8601DateFormatter().date(from: text)
    }
}
