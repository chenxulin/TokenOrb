import Foundation

public enum AppServerLivenessPolicy {
    public static let initializeTimeout: TimeInterval = 15
    public static let rateLimitsTimeout: TimeInterval = 15
}

public struct RealtimeRetryPolicy: Sendable {
    public static let restartRetryCount = 3
    public static let fallbackFailureThreshold = restartRetryCount + 1
    public static let fallbackRetryDelay = 30.0
    private static let restartRetryDelays = [5.0, 10.0, 15.0]

    public private(set) var consecutiveFailures = 0

    public init() {}

    public mutating func recordFailure() -> (
        delay: TimeInterval,
        retryAttempt: Int,
        useLocalFallback: Bool
    ) {
        consecutiveFailures += 1
        let useLocalFallback = consecutiveFailures >= Self.fallbackFailureThreshold
        let delay = useLocalFallback
            ? Self.fallbackRetryDelay
            : Self.restartRetryDelays[consecutiveFailures - 1]
        return (
            delay,
            useLocalFallback ? 0 : consecutiveFailures,
            useLocalFallback
        )
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
