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
    public static let defaultDiameter = OrbAppearanceDefaults.size
    public static let minimumDiameter = 24.0
    public static let maximumDiameter = 160.0
    public static let defaultTrailingMargin = 22.0
    public static let defaultTopOffsetRatio = 0.38
    public static let previewWidth = 320.0
    public static let previewHeight = 180.0
    public static let previewCornerRadius = 18.0
    public static let appearancePreviewMinimumDiameter = 54.0
    public static let appearancePreviewMaximumDiameter = 82.0
    public static let dragActivationDistance = 4.0
    public static let supportedAnimationFrameRates = [30, 60, 90, 120, 180]
    public static let defaultAnimationFrameRate = OrbAppearanceDefaults.animationFrameRate
    public static let animationFramesPerSecond = 60.0
    public static let animationInterval = 1.0 / 60.0
    public static let maximumAnimationDelta = 0.050
    public static let wavePhaseRadiansPerSecond = 3.75
    public static let backWaveSpeedRatio = 0.618_033_988_75
    public static let backWavePhaseRadiansPerSecond =
        -wavePhaseRadiansPerSecond * backWaveSpeedRatio
    public static let backWaveInitialPhase = 1.35
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

    public static func appearancePreviewDiameter(configuredDiameter: Double) -> Double {
        let safeDiameter = configuredDiameter.isFinite ? configuredDiameter : defaultDiameter
        return safeDiameter.clamped(
            to: appearancePreviewMinimumDiameter...appearancePreviewMaximumDiameter
        )
    }

    public static func shouldTreatAsDrag(deltaX: Double, deltaY: Double) -> Bool {
        guard deltaX.isFinite, deltaY.isFinite else { return false }
        return abs(deltaX) + abs(deltaY) >= dragActivationDistance
    }

    public static func animationElapsedSeconds(
        previousTimestamp: Double?,
        currentTimestamp: Double
    ) -> Double {
        guard
            currentTimestamp.isFinite,
            let previousTimestamp,
            previousTimestamp.isFinite
        else { return animationInterval }
        let elapsed = currentTimestamp - previousTimestamp
        guard elapsed > 0 else { return animationInterval }
        return min(elapsed, maximumAnimationDelta)
    }

    public static func normalizedAnimationFrameRate(_ frameRate: Int) -> Int {
        supportedAnimationFrameRates.contains(frameRate)
            ? frameRate
            : defaultAnimationFrameRate
    }

    public static func animationInterval(frameRate: Int) -> Double {
        1.0 / Double(normalizedAnimationFrameRate(frameRate))
    }

    public static func advancedLoopingPhase(
        phase: Double,
        radiansPerSecond: Double,
        elapsedSeconds: Double
    ) -> Double {
        guard
            phase.isFinite,
            radiansPerSecond.isFinite,
            elapsedSeconds.isFinite
        else { return 0 }
        let fullCycle = Double.pi * 2
        let advanced = phase + radiansPerSecond * elapsedSeconds
        let wrapped = advanced.truncatingRemainder(dividingBy: fullCycle)
        return wrapped < 0 ? wrapped + fullCycle : wrapped
    }

    public static func waveSurfaceSample(
        progress: Double,
        phase: Double,
        cycles: Double
    ) -> Double {
        sin(progress * .pi * 2 * cycles + phase)
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

public enum OrbTextStyle: String, CaseIterable, Equatable, Sendable {
    case minimal
    case geometric
    case condensed
    case rounded
    case emphasis

    public static let defaultStyle = OrbTextStyle.minimal

    public init(storedValue: String?) {
        self = storedValue.flatMap(OrbTextStyle.init(rawValue:))
            ?? OrbTextStyle.defaultStyle
    }

    public var displayName: String {
        switch self {
        case .minimal: return "Wing"
        case .geometric: return "Aureole"
        case .condensed: return "Spear"
        case .rounded: return "Pearl"
        case .emphasis: return "Thunder"
        }
    }
}

/// Used only when no saved appearance exists, so upgrades keep user choices.
public enum OrbAppearanceDefaults {
    public static let size = 65.0
    public static let accentHex = "#2FA4EB"
    public static let textStyle = OrbTextStyle.condensed
    public static let animationFrameRate = 60
}

public struct OrbAppearancePreset: Equatable, Sendable {
    public let name: String
    public let hex: String

    public init(name: String, hex: String) {
        self.name = name
        self.hex = hex
    }
}

public enum OrbAppearancePresets {
    /// Keep these names and RGB values in lockstep with the Windows appearance dialog.
    public static let all = [
        OrbAppearancePreset(name: "浅蓝", hex: "#2FA4EB"),
        OrbAppearancePreset(name: "薄荷", hex: "#31BE91"),
        OrbAppearancePreset(name: "薰衣草", hex: "#8D83F6"),
        OrbAppearancePreset(name: "晴空", hex: "#4D8DF7"),
        OrbAppearancePreset(name: "蜜桃", hex: "#F49A6A"),
        OrbAppearancePreset(name: "玫瑰", hex: "#EA718C"),
    ]
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
