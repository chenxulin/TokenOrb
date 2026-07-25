import Foundation

public struct RealtimeRetryPolicy: Sendable {
    public static let fallbackFailureThreshold = 3
    public static let initialDelay = 2.0
    public static let maximumDelay = 30.0

    public private(set) var consecutiveFailures = 0

    public init() {}

    public mutating func recordFailure() -> (delay: TimeInterval, useLocalFallback: Bool) {
        consecutiveFailures += 1
        let exponent = max(0, consecutiveFailures - 1)
        let delay = min(
            Self.maximumDelay,
            Self.initialDelay * pow(2, Double(exponent))
        )
        return (delay, consecutiveFailures >= Self.fallbackFailureThreshold)
    }

    public mutating func recordSuccess() {
        consecutiveFailures = 0
    }
}

public enum LocalFallbackStatePolicy {
    public static func resolve(
        connected: Bool,
        currentlyActive: Bool,
        fallbackRequested: Bool
    ) -> Bool {
        !connected && (currentlyActive || fallbackRequested)
    }
}
