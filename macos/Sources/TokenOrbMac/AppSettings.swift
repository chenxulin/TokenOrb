import AppKit
import Foundation
import ServiceManagement
import TokenOrbCore

enum LoginItemUpdateResult {
    case enabled
    case disabled
    case requiresApproval
}

private enum LoginItemUpdateError: LocalizedError {
    case registrationDidNotComplete

    var errorDescription: String? {
        "TokenOrb 跟随组件注册未完成，请确认 TokenOrb.app 位于 Applications 文件夹后重试。"
    }
}

final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let orbSize = "orbSize"
        static let accentHex = "accentHex"
        static let textStyle = "textStyle"
        static let animationFrameRate = "animationFrameRate"
        static let followCodex = "followCodex"
        static let orbOriginX = "orbOriginX"
        static let orbOriginY = "orbOriginY"
    }

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Key.orbSize: OrbAppearanceDefaults.size,
            Key.accentHex: OrbAppearanceDefaults.accentHex,
            Key.textStyle: OrbAppearanceDefaults.textStyle.rawValue,
            Key.animationFrameRate: OrbAppearanceDefaults.animationFrameRate,
            Key.followCodex: true,
        ])
    }

    var orbSize: CGFloat {
        get {
            CGFloat(defaults.double(forKey: Key.orbSize))
                .clamped(
                    to: CGFloat(OrbVisualMetrics.minimumDiameter)...CGFloat(OrbVisualMetrics.maximumDiameter)
                )
        }
        set {
            defaults.set(
                Double(newValue.clamped(
                    to: CGFloat(OrbVisualMetrics.minimumDiameter)...CGFloat(OrbVisualMetrics.maximumDiameter)
                )),
                forKey: Key.orbSize
            )
        }
    }

    var accentColor: NSColor {
        get {
            NSColor(
                hex: defaults.string(forKey: Key.accentHex)
                    ?? OrbAppearanceDefaults.accentHex
            )
        }
        set { defaults.set(newValue.hexString, forKey: Key.accentHex) }
    }

    var textStyle: OrbTextStyle {
        get { OrbTextStyle(storedValue: defaults.string(forKey: Key.textStyle)) }
        set { defaults.set(newValue.rawValue, forKey: Key.textStyle) }
    }

    var animationFrameRate: Int {
        get {
            OrbVisualMetrics.normalizedAnimationFrameRate(
                defaults.integer(forKey: Key.animationFrameRate)
            )
        }
        set {
            defaults.set(
                OrbVisualMetrics.normalizedAnimationFrameRate(newValue),
                forKey: Key.animationFrameRate
            )
        }
    }

    var followCodex: Bool {
        defaults.bool(forKey: Key.followCodex)
    }

    var savedOrbOrigin: NSPoint? {
        guard
            defaults.object(forKey: Key.orbOriginX) != nil,
            defaults.object(forKey: Key.orbOriginY) != nil
        else {
            return nil
        }
        return NSPoint(
            x: defaults.double(forKey: Key.orbOriginX),
            y: defaults.double(forKey: Key.orbOriginY)
        )
    }

    func saveOrbOrigin(_ origin: NSPoint) {
        defaults.set(origin.x, forKey: Key.orbOriginX)
        defaults.set(origin.y, forKey: Key.orbOriginY)
    }

    @discardableResult
    func setFollowCodex(_ enabled: Bool) throws -> LoginItemUpdateResult {
        let result = try updateLoginItem(enabled: enabled)
        defaults.set(enabled, forKey: Key.followCodex)
        return result
    }

    @discardableResult
    func updateLoginItem(enabled: Bool) throws -> LoginItemUpdateResult {
        guard #available(macOS 13.0, *) else {
            return enabled ? .enabled : .disabled
        }

        let service = SMAppService.loginItem(identifier: AppIdentity.watcherBundleIdentifier)
        let legacyMainAppService = SMAppService.mainApp
        if enabled {
            // v1.5.2 and earlier registered the full UI as the login item. The
            // watcher now owns login-time monitoring, so remove that legacy job.
            try unregisterIfNeeded(legacyMainAppService)
            switch service.status {
            case .enabled:
                return .enabled
            case .requiresApproval:
                return .requiresApproval
            case .notRegistered, .notFound:
                try service.register()
            @unknown default:
                try service.register()
            }

            switch service.status {
            case .enabled:
                return .enabled
            case .requiresApproval:
                return .requiresApproval
            case .notRegistered, .notFound:
                throw LoginItemUpdateError.registrationDidNotComplete
            @unknown default:
                throw LoginItemUpdateError.registrationDidNotComplete
            }
        }

        try unregisterIfNeeded(service)
        try unregisterIfNeeded(legacyMainAppService)
        return .disabled
    }

    private func unregisterIfNeeded(_ service: SMAppService) throws {
        switch service.status {
        case .enabled, .requiresApproval:
            try service.unregister()
        case .notRegistered, .notFound:
            break
        @unknown default:
            try service.unregister()
        }
    }

    func openLoginItemSettings() {
        guard #available(macOS 13.0, *) else { return }
        SMAppService.openSystemSettingsLoginItems()
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

extension NSColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat

        if cleaned.count == 6 {
            red = CGFloat((value >> 16) & 0xFF) / 255
            green = CGFloat((value >> 8) & 0xFF) / 255
            blue = CGFloat(value & 0xFF) / 255
        } else {
            red = 47 / 255
            green = 164 / 255
            blue = 235 / 255
        }
        self.init(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    var hexString: String {
        guard
            let rgb = usingColorSpace(.sRGB),
            rgb.numberOfComponents >= 3
        else {
            return OrbAppearanceDefaults.accentHex
        }
        return String(
            format: "#%02X%02X%02X",
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded())
        )
    }
}
