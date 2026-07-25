import AppKit
import Foundation
import ServiceManagement
import TokenOrbCore

final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let orbSize = "orbSize"
        static let accentHex = "accentHex"
        static let followCodex = "followCodex"
        static let orbOriginX = "orbOriginX"
        static let orbOriginY = "orbOriginY"
    }

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Key.orbSize: 60.0,
            Key.accentHex: "#2FA4EB",
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
        get { NSColor(hex: defaults.string(forKey: Key.accentHex) ?? "#2FA4EB") }
        set { defaults.set(newValue.hexString, forKey: Key.accentHex) }
    }

    var followCodex: Bool {
        get { defaults.bool(forKey: Key.followCodex) }
        set {
            defaults.set(newValue, forKey: Key.followCodex)
            updateLoginItem(enabled: newValue)
        }
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

    func updateLoginItem(enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled, SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            } else if !enabled, SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Registration can fail for an unbundled development executable.
            // The packaged app retries the next time the preference changes.
            AppLogger.shared.error(error)
        }
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
            return "#2FA4EB"
        }
        return String(
            format: "#%02X%02X%02X",
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded())
        )
    }
}
