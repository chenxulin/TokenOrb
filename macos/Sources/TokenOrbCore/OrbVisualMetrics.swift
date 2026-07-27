import Foundation

public enum OrbQuotaTone: Equatable, Sendable {
    case waiting
    case healthy
    case warning
    case critical
    case depleted
}

/// Platform-neutral visual rules shared with the macOS AppKit renderer.
/// Values intentionally mirror `QuotaBallVisual` on Windows.
public enum OrbVisualMetrics {
    public static let defaultDiameter = 60.0
    public static let minimumDiameter = 24.0
    public static let maximumDiameter = 160.0
    public static let previewWidth = 320.0
    public static let previewHeight = 180.0
    public static let previewCornerRadius = 18.0
    public static let animationInterval = 0.040
    public static let outerRingBreathingCycle = 3.0
    public static let bodyLightCycle = 5.6
    public static let waitingWaveRemainingPercent = 50.0

    public static func previewOffset(diameter: Double) -> (x: Double, y: Double) {
        let safeDiameter = diameter.clamped(to: 0...min(previewWidth, previewHeight))
        return (
            (previewWidth - safeDiameter) / 2,
            (previewHeight - safeDiameter) / 2
        )
    }

    public static func tone(remaining: Double?) -> OrbQuotaTone {
        guard let remaining else { return .waiting }
        if remaining <= 0 { return .depleted }
        if remaining > 20 { return .healthy }
        if remaining > 10 { return .warning }
        return .critical
    }

    public static func breathStrength(phase: Double) -> Double {
        guard phase.isFinite else { return 0.5 }
        return 0.5 + 0.5 * sin(phase)
    }

    public static func bodyLightOffset(phase: Double) -> (x: Double, y: Double) {
        guard phase.isFinite else { return (0, 0) }
        return (sin(phase) * 0.075, cos(phase) * 0.040)
    }

    public static func bodyLightStrength(phase: Double) -> Double {
        guard phase.isFinite else { return 0.5 }
        return 0.5 + 0.5 * sin(phase)
    }

    public static func bodyPulseScale(phase: Double) -> Double {
        guard phase.isFinite else { return 1 }
        return 1 + sin(phase) * 0.040
    }

    public static func bodySheenOffset(phase: Double) -> (x: Double, y: Double) {
        guard phase.isFinite else { return (0, -0.26) }
        return (sin(phase) * 0.36, -0.34 + cos(phase) * 0.040)
    }

    public static func bodyHighlightAlpha(strength: Double) -> Double {
        (28 + 44 * strength.clamped(to: 0...1)).rounded(.toNearestOrEven)
    }

    public static func bodySheenAlpha(strength: Double) -> Double {
        (125 + 70 * strength.clamped(to: 0...1)).rounded(.toNearestOrEven)
    }

    public static func bodySheenCoreAlpha(strength: Double) -> Double {
        (180 + 55 * strength.clamped(to: 0...1)).rounded(.toNearestOrEven)
    }

    public static func outerBorderWidth(size: Double, depleted: Bool) -> Double {
        let safeSize = max(0, size)
        return depleted
            ? (safeSize * 0.040).clamped(to: 2...6)
            : (safeSize * 0.030).clamped(to: 1.1...4.5)
    }

    public static func outerRingAlpha(strength: Double, depleted: Bool) -> Double {
        let minimum = depleted ? 210.0 : 170.0
        return (minimum + (255 - minimum) * strength.clamped(to: 0...1))
            .rounded(.toNearestOrEven)
    }

    public static func visibleWaveHeight(
        size: Double,
        radius: Double,
        remaining: Double
    ) -> Double {
        let safeRemaining = remaining.clamped(to: 0...100)
        guard safeRemaining > 0 else { return 0 }
        let diameter = max(1, radius * 2)
        let actualHeight = diameter * safeRemaining / 100
        let minimumVisibleHeight = (size * 0.10).clamped(to: 2.6...5)
        let maximumVisibleHeight = diameter * 0.965
        return min(maximumVisibleHeight, max(actualHeight, minimumVisibleHeight))
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
