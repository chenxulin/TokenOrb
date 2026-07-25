import AppKit
import TokenOrbCore

final class OrbPanelController {
    let panel: NSPanel
    private let orbView: OrbView
    private let settings: AppSettings

    var onClick: (() -> Void)? {
        didSet { orbView.onClick = onClick }
    }
    var menuProvider: (() -> NSMenu?)? {
        didSet { orbView.menuProvider = menuProvider }
    }

    init(settings: AppSettings) {
        self.settings = settings
        let size = settings.orbSize
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        orbView = OrbView(
            frame: NSRect(x: 0, y: 0, width: size, height: size),
            accentColor: settings.accentColor
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = orbView
        panel.setFrameOrigin(Self.initialOrigin(size: size, saved: settings.savedOrbOrigin))

        orbView.onMove = { [weak self] origin in
            self?.settings.saveOrbOrigin(origin)
        }
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func show() {
        panel.orderFrontRegardless()
        orbView.setAnimating(true)
    }

    func hide() {
        orbView.setAnimating(false)
        panel.orderOut(nil)
    }

    func update(snapshot: QuotaSnapshot?, connected: Bool, toolTip: String) {
        let remaining = snapshot?.mostRestrictiveWindow?.remainingPercent
        orbView.update(
            remainingPercent: remaining,
            accentColor: settings.accentColor,
            connected: connected,
            toolTip: toolTip
        )
    }

    func applyAppearance() {
        let oldFrame = panel.frame
        let center = NSPoint(x: oldFrame.midX, y: oldFrame.midY)
        let size = settings.orbSize
        let origin = Self.clampedOrigin(
            NSPoint(x: center.x - size / 2, y: center.y - size / 2),
            size: size
        )
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: size, height: size), display: true)
        orbView.frame = NSRect(x: 0, y: 0, width: size, height: size)
        orbView.update(
            remainingPercent: orbView.remainingPercent,
            accentColor: settings.accentColor,
            connected: orbView.connected,
            toolTip: orbView.toolTip ?? "Token Orb"
        )
        settings.saveOrbOrigin(origin)
    }

    private static func initialOrigin(size: CGFloat, saved: NSPoint?) -> NSPoint {
        if let saved {
            return clampedOrigin(saved, size: size)
        }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
        return NSPoint(
            x: screen.maxX - size - 36,
            y: screen.midY - size / 2
        )
    }

    static func clampedOrigin(_ origin: NSPoint, size: CGFloat) -> NSPoint {
        let proposed = NSRect(x: origin.x, y: origin.y, width: size, height: size)
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(proposed) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
        return NSPoint(
            x: origin.x.clamped(to: visible.minX...(visible.maxX - size)),
            y: origin.y.clamped(to: visible.minY...(visible.maxY - size))
        )
    }
}

final class OrbView: NSView {
    fileprivate private(set) var remainingPercent: Double?
    fileprivate private(set) var connected = false
    private var accentColor: NSColor
    private var animationTimer: Timer?
    private var wavePhase = 0.0
    private var breathPhase = 0.0
    private var bodyLightPhase = 0.0
    private var activeContextMenu: NSMenu?
    private var deactivationObserver: NSObjectProtocol?
    private var mouseDownLocation: NSPoint?
    private var windowOriginAtMouseDown: NSPoint?
    private var dragged = false

    var onClick: (() -> Void)?
    var onMove: ((NSPoint) -> Void)?
    var menuProvider: (() -> NSMenu?)?

    init(frame: NSRect, accentColor: NSColor) {
        self.accentColor = accentColor
        super.init(frame: frame)
        wantsLayer = true
        toolTip = "Token Orb · 点击查看详细额度"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Token Orb 悬浮球")
        setAccessibilityHelp("点击查看详细额度，右键打开菜单，拖动可调整位置")
        deactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            // Mirrors Windows MainWindow.Deactivated: never leave the orb menu
            // floating after focus moves to another application.
            self?.activeContextMenu?.cancelTracking()
        }
    }

    deinit {
        animationTimer?.invalidate()
        if let deactivationObserver {
            NotificationCenter.default.removeObserver(deactivationObserver)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    func setAnimating(_ shouldAnimate: Bool) {
        if shouldAnimate, animationTimer == nil {
            let timer = Timer(timeInterval: OrbVisualMetrics.animationInterval, repeats: true) {
                [weak self] _ in
                self?.advanceAnimation()
            }
            RunLoop.main.add(timer, forMode: .common)
            animationTimer = timer
        } else if !shouldAnimate {
            animationTimer?.invalidate()
            animationTimer = nil
            activeContextMenu?.cancelTracking()
        }
    }

    func update(
        remainingPercent: Double?,
        accentColor: NSColor,
        connected: Bool,
        toolTip: String
    ) {
        self.remainingPercent = remainingPercent
        self.accentColor = accentColor
        self.connected = connected
        self.toolTip = toolTip
        setAccessibilityValue(
            remainingPercent.map { "剩余 \(QuotaFormatting.roundedPercent($0))%" }
                ?? "等待额度数据"
        )
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let size = min(bounds.width, bounds.height)
        guard size > 0 else { return }

        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let outerRadius = max(6, size / 2 - max(2.2, size * 0.092))
        let remaining = remainingPercent?.clamped(to: 0...100)
        let waveRemaining = remaining ?? OrbVisualMetrics.waitingWaveRemainingPercent
        let depleted = remaining.map { $0 <= 0 } ?? false
        let rawBodyOffset = OrbVisualMetrics.bodyLightOffset(phase: bodyLightPhase)
        let bodyOffset = (x: CGFloat(rawBodyOffset.x), y: CGFloat(rawBodyOffset.y))
        let bodyStrength = OrbVisualMetrics.bodyLightStrength(phase: bodyLightPhase)
        let pulseScale = CGFloat(OrbVisualMetrics.bodyPulseScale(phase: bodyLightPhase))

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: pulseScale, y: pulseScale)
        context.translateBy(x: -center.x, y: -center.y)

        let bodyRect = NSRect(
            x: center.x - outerRadius,
            y: center.y - outerRadius,
            width: outerRadius * 2,
            height: outerRadius * 2
        )
        let bodyPath = NSBezierPath(ovalIn: bodyRect)
        drawBodyShadow(path: bodyPath, size: size)

        let borderColor = depleted ? OrbPalette.red : OrbPalette.outerRingBlue
        let borderWidth = CGFloat(
            OrbVisualMetrics.outerBorderWidth(size: Double(size), depleted: depleted)
        )
        let breathStrength = OrbVisualMetrics.breathStrength(phase: breathPhase)
        let borderAlpha = CGFloat(OrbVisualMetrics.outerRingAlpha(
            strength: breathStrength,
            depleted: depleted
        ) / 255)
        let glowAlpha = CGFloat(
            (Double(depleted ? 14 : 18) + Double(depleted ? 30 : 36) * breathStrength)
                .rounded(.toNearestOrEven) / 255
        )
        let glowWidth = borderWidth + max(
            1.6,
            min(6, size * CGFloat(0.034 + 0.018 * breathStrength))
        )

        strokeCircle(
            center: center,
            radius: outerRadius,
            color: borderColor.withAlphaComponent(glowAlpha),
            width: glowWidth
        )
        drawBodyGradient(
            in: bodyPath,
            rect: bodyRect,
            offset: bodyOffset,
            strength: bodyStrength,
            radius: outerRadius
        )
        strokeCircle(
            center: center,
            radius: outerRadius,
            color: borderColor.withAlphaComponent(borderAlpha),
            width: borderWidth
        )

        drawBodyHighlights(
            center: center,
            outerRadius: outerRadius,
            borderWidth: borderWidth,
            offset: bodyOffset,
            strength: bodyStrength
        )

        let quotaColor = OrbPalette.color(for: remaining)
        let ringWidth = max(1.8, min(8, size * 0.066))
        let ringRadius = max(4, outerRadius - ringWidth * 1.04)
        if remaining == nil || (remaining ?? 0) > 0 {
            let waveInset = max(0.65, size * 0.012)
            let waveRadius = max(2.2, ringRadius - ringWidth / 2 - waveInset)
            drawWaterWave(
                center: center,
                radius: waveRadius,
                remaining: waveRemaining,
                color: quotaColor,
                size: size
            )
        }

        strokeCircle(
            center: center,
            radius: ringRadius,
            color: .white.withAlphaComponent(190 / 255),
            width: ringWidth
        )
        if let remaining, remaining > 0 {
            drawQuotaArc(
                center: center,
                radius: ringRadius,
                remaining: remaining,
                color: quotaColor,
                width: ringWidth
            )
        }
        context.restoreGState()

        drawQuotaText(center: center, size: size, remaining: remaining, depleted: depleted)
        drawConnectionStatus(center: center, outerRadius: outerRadius, size: size)
    }

    private func advanceAnimation() {
        wavePhase = (wavePhase + 0.15).truncatingRemainder(dividingBy: .pi * 2)
        breathPhase = (
            breathPhase + .pi * 2 * OrbVisualMetrics.animationInterval
                / OrbVisualMetrics.outerRingBreathingCycle
        ).truncatingRemainder(dividingBy: .pi * 2)
        bodyLightPhase = (
            bodyLightPhase + .pi * 2 * OrbVisualMetrics.animationInterval
                / OrbVisualMetrics.bodyLightCycle
        ).truncatingRemainder(dividingBy: .pi * 2)
        needsDisplay = true
    }

    private func drawBodyShadow(path: NSBezierPath, size: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = accentColor.mixed(with: .black, amount: 0.20)
            .withAlphaComponent(0.30)
        shadow.shadowBlurRadius = max(5, size * 0.18)
        shadow.shadowOffset = NSSize(width: 0, height: max(0.8, size * 0.032))
        shadow.set()
        accentColor.withAlphaComponent(0.08).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawBodyGradient(
        in path: NSBezierPath,
        rect: NSRect,
        offset: (x: CGFloat, y: CGFloat),
        strength: Double,
        radius: CGFloat
    ) {
        let colors = [
            accentColor.mixed(with: .white, amount: 0.97),
            accentColor.mixed(with: .white, amount: 0.650 + 0.150 * strength),
            accentColor.mixed(with: .white, amount: 0.320 + 0.160 * strength),
        ]
        let gradientCenter = NSPoint(
            x: rect.minX + rect.width * (0.38 + offset.x),
            y: rect.minY + rect.height * (0.32 + offset.y)
        )
        let gradientOrigin = NSPoint(
            x: rect.minX + rect.width * (0.30 + offset.x * 1.15),
            y: rect.minY + rect.height * (0.24 + offset.y * 1.15)
        )
        drawEllipticalRadialGradient(
            colors: colors,
            locations: [0, 0.58, 1],
            startCenter: gradientOrigin,
            endCenter: gradientCenter,
            radiusX: radius * CGFloat(1.54 + 0.11 * strength),
            radiusY: radius * CGFloat(1.56 + 0.09 * strength),
            clip: path
        )
    }

    private func drawBodyHighlights(
        center: NSPoint,
        outerRadius: CGFloat,
        borderWidth: CGFloat,
        offset: (x: CGFloat, y: CGFloat),
        strength: Double
    ) {
        let highlightRadius = max(2, outerRadius - borderWidth * 0.56)
        let clip = NSBezierPath(
            ovalIn: NSRect(
                x: center.x - highlightRadius,
                y: center.y - highlightRadius,
                width: highlightRadius * 2,
                height: highlightRadius * 2
            )
        )
        let highlightCenter = NSPoint(
            x: center.x + outerRadius * (-0.40 + offset.x * 2.80),
            y: center.y + outerRadius * (-0.48 + offset.y * 2.60)
        )
        drawEllipticalRadialGradient(
            colors: [
                .white.withAlphaComponent(
                    CGFloat(OrbVisualMetrics.bodyHighlightAlpha(strength: strength) / 255)
                ),
                .white.withAlphaComponent(0),
            ],
            locations: [0, 0.84],
            startCenter: highlightCenter,
            endCenter: highlightCenter,
            radiusX: highlightRadius * 0.84,
            radiusY: highlightRadius * 0.72,
            clip: clip
        )

        let rawSheenOffset = OrbVisualMetrics.bodySheenOffset(phase: bodyLightPhase)
        let sheenOffset = (x: CGFloat(rawSheenOffset.x), y: CGFloat(rawSheenOffset.y))
        let sheenCenter = NSPoint(
            x: center.x + outerRadius * sheenOffset.x,
            y: center.y + outerRadius * sheenOffset.y
        )
        let sheenTint = accentColor.mixed(with: .white, amount: 0.35)
        let sheenAlpha = CGFloat(OrbVisualMetrics.bodySheenAlpha(strength: strength) / 255)
        let sheenRect = NSRect(
            x: sheenCenter.x - max(2.2, outerRadius * 0.30),
            y: sheenCenter.y - max(1.3, outerRadius * 0.13),
            width: max(4.4, outerRadius * 0.60),
            height: max(2.6, outerRadius * 0.26)
        )
        let sheenGradientCenter = NSPoint(
            x: sheenRect.minX + sheenRect.width * 0.42,
            y: sheenRect.minY + sheenRect.height * 0.40
        )
        drawEllipticalRadialGradient(
            colors: [
                sheenTint.withAlphaComponent(sheenAlpha),
                sheenTint.withAlphaComponent(sheenAlpha / 3),
                sheenTint.withAlphaComponent(0),
            ],
            locations: [0, 0.48, 1],
            startCenter: sheenGradientCenter,
            endCenter: sheenGradientCenter,
            radiusX: sheenRect.width * 0.58,
            radiusY: sheenRect.height * 0.58,
            clip: clip,
            shape: NSBezierPath(ovalIn: sheenRect)
        )

        let coreCenter = NSPoint(
            x: sheenCenter.x - outerRadius * 0.04,
            y: sheenCenter.y - outerRadius * 0.035
        )
        let coreRect = NSRect(
            x: coreCenter.x - max(1.3, outerRadius * 0.115),
            y: coreCenter.y - max(0.8, outerRadius * 0.050),
            width: max(2.6, outerRadius * 0.230),
            height: max(1.6, outerRadius * 0.100)
        )
        let coreGradientCenter = NSPoint(
            x: coreRect.minX + coreRect.width * 0.42,
            y: coreRect.minY + coreRect.height * 0.38
        )
        drawEllipticalRadialGradient(
            colors: [
                .white.withAlphaComponent(
                    CGFloat(OrbVisualMetrics.bodySheenCoreAlpha(strength: strength) / 255)
                ),
                .white.withAlphaComponent(0),
            ],
            locations: [0, 1],
            startCenter: coreGradientCenter,
            endCenter: coreGradientCenter,
            radiusX: coreRect.width * 0.62,
            radiusY: coreRect.height * 0.62,
            clip: clip,
            shape: NSBezierPath(ovalIn: coreRect)
        )
    }

    private func drawWaterWave(
        center: NSPoint,
        radius: CGFloat,
        remaining: Double,
        color: NSColor,
        size: CGFloat
    ) {
        let visibleHeight = CGFloat(OrbVisualMetrics.visibleWaveHeight(
            size: Double(size),
            radius: Double(radius),
            remaining: remaining
        ))
        let ratio = visibleHeight / max(1, radius * 2)
        let waterLine = center.y + radius - radius * 2 * ratio
        let edgeDamping = max(0.38, min(1, min(ratio, 1 - ratio) * 4.2))
        let amplitude = max(0.75, min(5.5, size * 0.052)) * edgeDamping
        let clip = NSBezierPath(
            ovalIn: NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )

        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        color.withAlphaComponent(72 / 255).setFill()
        wavePath(
            center: center,
            radius: radius,
            waterLine: waterLine + amplitude * 0.42,
            amplitude: amplitude * 0.72,
            phase: -wavePhase * 0.74 + 1.35,
            cycles: 1.20
        ).fill()
        color.withAlphaComponent(132 / 255).setFill()
        wavePath(
            center: center,
            radius: radius,
            waterLine: waterLine,
            amplitude: amplitude,
            phase: wavePhase,
            cycles: 1.42
        ).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func wavePath(
        center: NSPoint,
        radius: CGFloat,
        waterLine: CGFloat,
        amplitude: CGFloat,
        phase: Double,
        cycles: Double
    ) -> NSBezierPath {
        let left = center.x - radius
        let right = center.x + radius
        let bottom = center.y + radius
        let segments = max(28, min(120, Int(ceil(radius * 1.8))))
        let path = NSBezierPath()
        path.move(to: NSPoint(x: left, y: bottom))
        for index in 0...segments {
            let progress = CGFloat(index) / CGFloat(segments)
            let x = left + (right - left) * progress
            let wave = sin(Double(progress) * .pi * 2 * cycles + phase)
            let y = waterLine + amplitude * CGFloat(wave)
            path.line(to: NSPoint(x: x, y: y))
        }
        path.line(to: NSPoint(x: right, y: bottom))
        path.close()
        return path
    }

    private func drawQuotaArc(
        center: NSPoint,
        radius: CGFloat,
        remaining: Double,
        color: NSColor,
        width: CGFloat
    ) {
        let path: NSBezierPath
        if remaining >= 99.8 {
            path = NSBezierPath(
                ovalIn: NSRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
        } else {
            path = NSBezierPath()
            path.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 90,
                endAngle: CGFloat(90 - 3.6 * remaining),
                clockwise: true
            )
        }
        path.lineWidth = width
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    private func drawQuotaText(
        center: NSPoint,
        size: CGFloat,
        remaining: Double?,
        depleted: Bool
    ) {
        guard let remaining else { return }
        let text = "\(QuotaFormatting.roundedPercent(remaining))%"
        let calculated = text.count >= 4 ? size * 0.242 : size * 0.274
        let fontSize = calculated.clamped(to: 6.8...37)
        let textColor = depleted
            ? OrbPalette.red
            : accentColor.mixed(with: .black, amount: 0.58)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: textColor,
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(
                x: center.x - textSize.width / 2,
                y: center.y - textSize.height / 2 - 0.3
            ),
            withAttributes: attributes
        )
    }

    private func drawConnectionStatus(center: NSPoint, outerRadius: CGFloat, size: CGFloat) {
        let statusCenter = NSPoint(
            x: center.x + outerRadius * 0.70,
            y: center.y - outerRadius * 0.70
        )
        let outer = max(2, size * 0.071)
        let inner = max(1.2, size * 0.043)
        accentColor.mixed(with: .white, amount: 0.94).setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: statusCenter.x - outer,
                y: statusCenter.y - outer,
                width: outer * 2,
                height: outer * 2
            )
        ).fill()
        (connected ? OrbPalette.green : OrbPalette.amber).setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: statusCenter.x - inner,
                y: statusCenter.y - inner,
                width: inner * 2,
                height: inner * 2
            )
        ).fill()
    }

    private func strokeCircle(center: NSPoint, radius: CGFloat, color: NSColor, width: CGFloat) {
        let path = NSBezierPath(
            ovalIn: NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }

    private func drawEllipticalRadialGradient(
        colors: [NSColor],
        locations: [CGFloat],
        startCenter: NSPoint,
        endCenter: NSPoint,
        radiusX: CGFloat,
        radiusY: CGFloat,
        clip: NSBezierPath,
        shape: NSBezierPath? = nil
    ) {
        guard
            let context = NSGraphicsContext.current?.cgContext,
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors.map { $0.sRGB.cgColor } as CFArray,
                locations: locations
            )
        else { return }
        context.saveGState()
        clip.addClip()
        shape?.addClip()
        let safeRadiusY = max(0.001, radiusY)
        let xScale = max(0.001, radiusX / safeRadiusY)
        context.translateBy(x: endCenter.x, y: endCenter.y)
        context.scaleBy(x: xScale, y: 1)
        let transformedStart = NSPoint(
            x: (startCenter.x - endCenter.x) / xScale,
            y: startCenter.y - endCenter.y
        )
        context.drawRadialGradient(
            gradient,
            startCenter: transformedStart,
            startRadius: 0,
            endCenter: .zero,
            endRadius: safeRadiusY,
            options: [.drawsAfterEndLocation]
        )
        context.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = NSEvent.mouseLocation
        windowOriginAtMouseDown = window?.frame.origin
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard
            let window,
            let start = mouseDownLocation,
            let origin = windowOriginAtMouseDown
        else {
            return
        }
        let current = NSEvent.mouseLocation
        let delta = NSPoint(x: current.x - start.x, y: current.y - start.y)
        if abs(delta.x) > 2 || abs(delta.y) > 2 {
            dragged = true
        }
        let size = window.frame.width
        let proposed = NSPoint(x: origin.x + delta.x, y: origin.y + delta.y)
        window.setFrameOrigin(OrbPanelController.clampedOrigin(proposed, size: size))
    }

    override func mouseUp(with event: NSEvent) {
        if let origin = window?.frame.origin {
            onMove?(origin)
        }
        if !dragged {
            onClick?()
        }
        mouseDownLocation = nil
        windowOriginAtMouseDown = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider?() else { return }
        activeContextMenu = menu
        NSMenu.popUpContextMenu(menu, with: event, for: self)
        activeContextMenu = nil
    }
}

private enum OrbPalette {
    static let green = NSColor(srgbRed: 45 / 255, green: 194 / 255, blue: 145 / 255, alpha: 1)
    static let amber = NSColor(srgbRed: 239 / 255, green: 169 / 255, blue: 66 / 255, alpha: 1)
    static let red = NSColor(srgbRed: 232 / 255, green: 100 / 255, blue: 119 / 255, alpha: 1)
    static let blue = NSColor(srgbRed: 47 / 255, green: 164 / 255, blue: 235 / 255, alpha: 1)
    static let outerRingBlue = NSColor(srgbRed: 125 / 255, green: 211 / 255, blue: 252 / 255, alpha: 1)

    static func color(for remaining: Double?) -> NSColor {
        switch OrbVisualMetrics.tone(remaining: remaining) {
        case .waiting:
            return blue
        case .healthy:
            return green
        case .warning:
            return amber
        case .critical, .depleted:
            return red
        }
    }
}

private extension NSColor {
    var sRGB: NSColor {
        usingColorSpace(.sRGB) ?? self
    }

    func mixed(with target: NSColor, amount: Double) -> NSColor {
        let source = sRGB
        let destination = target.sRGB
        let value = CGFloat(amount.clamped(to: 0...1))
        func mixedComponent(_ start: CGFloat, _ end: CGFloat) -> CGFloat {
            ((start * 255 + (end - start) * 255 * value)
                .rounded(.toNearestOrEven)) / 255
        }
        return NSColor(
            srgbRed: mixedComponent(source.redComponent, destination.redComponent),
            green: mixedComponent(source.greenComponent, destination.greenComponent),
            blue: mixedComponent(source.blueComponent, destination.blueComponent),
            alpha: source.alphaComponent + (destination.alphaComponent - source.alphaComponent) * value
        )
    }
}
