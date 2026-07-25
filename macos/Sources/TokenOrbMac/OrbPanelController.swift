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
    }

    func hide() {
        panel.orderOut(nil)
    }

    func update(snapshot: QuotaSnapshot?, connected: Bool) {
        let remaining = snapshot?.mostRestrictiveWindow?.remainingPercent
        orbView.update(
            remainingPercent: remaining,
            accentColor: settings.accentColor,
            connected: connected
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
            connected: orbView.connected
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    func update(remainingPercent: Double?, accentColor: NSColor, connected: Bool) {
        self.remainingPercent = remainingPercent
        self.accentColor = accentColor
        self.connected = connected
        setAccessibilityValue(
            remainingPercent.map { "剩余 \(Int($0.rounded()))%" } ?? "等待额度数据"
        )
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let side = min(bounds.width, bounds.height)
        let inset = max(4, side * 0.09)
        let circle = NSRect(
            x: (bounds.width - side) / 2 + inset,
            y: (bounds.height - side) / 2 + inset,
            width: side - inset * 2,
            height: side - inset * 2
        )

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = accentColor.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = max(6, side * 0.14)
        shadow.shadowOffset = NSSize(width: 0, height: 0)
        shadow.set()
        NSColor.white.withAlphaComponent(0.96).setFill()
        NSBezierPath(ovalIn: circle).fill()
        NSGraphicsContext.restoreGraphicsState()

        let baseRing = NSBezierPath(ovalIn: circle.insetBy(dx: 3.5, dy: 3.5))
        baseRing.lineWidth = max(3.5, side * 0.07)
        accentColor.withAlphaComponent(0.18).setStroke()
        baseRing.stroke()

        let fraction = (remainingPercent ?? 0) / 100
        let center = NSPoint(x: circle.midX, y: circle.midY)
        let radius = circle.width / 2 - 3.5
        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - 360 * fraction,
            clockwise: true
        )
        arc.lineWidth = max(3.5, side * 0.07)
        arc.lineCapStyle = .round
        accentColor.setStroke()
        arc.stroke()

        let text: String
        if let remainingPercent {
            text = "\(Int(remainingPercent.rounded()))%"
        } else {
            text = "—"
        }
        let font = NSFont.systemFont(ofSize: max(12, side * 0.28), weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedRed: 0.08, green: 0.28, blue: 0.39, alpha: 1),
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(
                x: bounds.midX - textSize.width / 2,
                y: bounds.midY - textSize.height / 2
            ),
            withAttributes: attributes
        )

        let dotRadius = max(2.5, side * 0.055)
        let dotRect = NSRect(
            x: circle.maxX - dotRadius * 2,
            y: circle.minY + dotRadius / 2,
            width: dotRadius * 2,
            height: dotRadius * 2
        )
        (connected ? accentColor : NSColor.systemOrange).setFill()
        NSBezierPath(ovalIn: dotRect).fill()
        NSColor.white.setStroke()
        let dotOutline = NSBezierPath(ovalIn: dotRect.insetBy(dx: -1, dy: -1))
        dotOutline.lineWidth = 1.5
        dotOutline.stroke()
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
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
