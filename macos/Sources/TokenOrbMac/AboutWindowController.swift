import AppKit
import TokenOrbCore

private enum AboutPalette {
    struct Colors {
        let canvas: NSColor
        let footer: NSColor
        let logoHalo: NSColor
        let logoOrbit: NSColor
        let logoCoreStroke: NSColor
    }

    static let canvas = adaptive(
        light: color(247, 252, 255),
        dark: color(15, 25, 31)
    )
    static let actionFill = adaptive(
        light: color(20, 125, 187),
        dark: color(23, 111, 159)
    )

    static func colors(for appearance: NSAppearance) -> Colors {
        if isDark(appearance) {
            return Colors(
                canvas: color(15, 25, 31),
                footer: color(21, 38, 46),
                logoHalo: color(29, 53, 66),
                logoOrbit: color(137, 187, 213),
                logoCoreStroke: color(99, 197, 250)
            )
        }
        return Colors(
            canvas: color(247, 252, 255),
            footer: color(239, 247, 251),
            logoHalo: color(239, 248, 255),
            logoOrbit: color(87, 135, 165),
            logoCoreStroke: color(53, 128, 174)
        )
    }

    private static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            isDark(appearance) ? dark : light
        }
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(
            srgbRed: red / 255,
            green: green / 255,
            blue: blue / 255,
            alpha: 1
        )
    }
}

private final class EscapeClosingPanel: NSPanel {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

final class AboutWindowController: NSWindowController, NSWindowDelegate {
    init() {
        let panel = EscapeClosingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 452),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "关于 \(AppIdentity.productName)"
        panel.isReleasedWhenClosed = false
        panel.level = .normal
        panel.hidesOnDeactivate = false
        panel.backgroundColor = AboutPalette.canvas
        panel.contentView = AboutSurfaceView(
            style: .canvas,
            frame: panel.contentView?.frame ?? .zero
        )
        super.init(window: panel)
        panel.delegate = self
        panel.onCancel = { [weak self] in
            self?.hide()
        }
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window?.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }

        let logo = TokenOrbLogoView()
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.setAccessibilityLabel("\(AppIdentity.productName) 图标")

        let name = label(AppIdentity.productName, size: 22, weight: .semibold, color: .labelColor)
        let powered = label("Powered by Codex", size: 14, color: .secondaryLabelColor)
        let version = label("版本 \(AppIdentity.displayVersion)", size: 14, color: .secondaryLabelColor)
        let released = label(AppIdentity.releaseDateText, size: 14, color: .secondaryLabelColor)
        let publisher = label("© \(AppIdentity.publisher)", size: 14, color: .secondaryLabelColor)

        let identity = NSStackView(views: [logo, name, powered, version, released, publisher])
        identity.orientation = .vertical
        identity.alignment = .centerX
        identity.spacing = 1
        identity.setCustomSpacing(22, after: logo)
        identity.setCustomSpacing(22, after: name)
        identity.setCustomSpacing(22, after: version)
        identity.setCustomSpacing(17, after: released)
        identity.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(identity)

        let footer = AboutSurfaceView(style: .footer)
        footer.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(footer)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(divider)

        let confirm = NSButton(title: "确定", target: self, action: #selector(closeWindow))
        confirm.keyEquivalent = "\r"
        confirm.bezelStyle = .rounded
        confirm.bezelColor = AboutPalette.actionFill
        confirm.contentTintColor = .white
        confirm.font = .systemFont(ofSize: 12, weight: .semibold)
        confirm.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(confirm)

        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 84),
            logo.heightAnchor.constraint(equalToConstant: 84),
            identity.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            identity.centerYAnchor.constraint(equalTo: content.centerYAnchor, constant: -28),

            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 73),
            divider.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            divider.topAnchor.constraint(equalTo: footer.topAnchor),
            confirm.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -14),
            confirm.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            confirm.widthAnchor.constraint(equalToConstant: 100),
            confirm.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    private func label(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor
    ) -> NSTextField {
        let value = NSTextField(labelWithString: text)
        value.font = .systemFont(ofSize: size, weight: weight)
        value.textColor = color
        value.alignment = .center
        return value
    }

    @objc private func closeWindow() {
        hide()
    }
}

private final class AboutSurfaceView: NSView {
    enum Style {
        case canvas
        case footer
    }

    private let style: Style

    init(style: Style, frame: NSRect = .zero) {
        self.style = style
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let colors = AboutPalette.colors(for: effectiveAppearance)
        layer?.backgroundColor = (
            style == .canvas ? colors.canvas : colors.footer
        ).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private final class TokenOrbLogoView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let size = min(bounds.width, bounds.height)
        let scale = size / 84
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let colors = AboutPalette.colors(for: effectiveAppearance)

        colors.logoHalo.setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: center.x - 38 * scale,
                y: center.y - 38 * scale,
                width: 76 * scale,
                height: 76 * scale
            )
        ).fill()

        let orbitAngles: [CGFloat] = [0, 60, 120]
        for angle in orbitAngles {
            NSGraphicsContext.saveGraphicsState()
            if let context = NSGraphicsContext.current?.cgContext {
                context.translateBy(x: center.x, y: center.y)
                context.rotate(by: angle * .pi / 180)
                context.translateBy(x: -center.x, y: -center.y)
                let orbit = NSBezierPath(
                    ovalIn: NSRect(
                        x: center.x - 31 * scale,
                        y: center.y - 13 * scale,
                        width: 62 * scale,
                        height: 26 * scale
                    )
                )
                orbit.lineWidth = max(1.6, 2.7 * scale)
                colors.logoOrbit.setStroke()
                orbit.stroke()
            }
            NSGraphicsContext.restoreGraphicsState()
        }

        let coreRect = NSRect(
            x: center.x - 12 * scale,
            y: center.y - 12 * scale,
            width: 24 * scale,
            height: 24 * scale
        )
        let core = NSBezierPath(ovalIn: coreRect)
        NSColor(srgbRed: 41 / 255, green: 145 / 255, blue: 218 / 255, alpha: 1).setFill()
        core.fill()
        if
            let context = NSGraphicsContext.current?.cgContext,
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    NSColor.white.cgColor,
                    NSColor(srgbRed: 116 / 255, green: 203 / 255, blue: 247 / 255, alpha: 1).cgColor,
                    NSColor(srgbRed: 41 / 255, green: 145 / 255, blue: 218 / 255, alpha: 1).cgColor,
                ] as CFArray,
                locations: [0, 0.50, 1]
            )
        {
            context.saveGState()
            core.addClip()
            context.drawRadialGradient(
                gradient,
                startCenter: NSPoint(
                    x: center.x - 3.8 * scale,
                    y: center.y - 4.8 * scale
                ),
                startRadius: 0,
                endCenter: center,
                endRadius: 16.8 * scale,
                options: [.drawsAfterEndLocation]
            )
            context.restoreGState()
        }
        core.lineWidth = max(1.2, 1.8 * scale)
        colors.logoCoreStroke.setStroke()
        core.stroke()
        drawElectron(
            at: NSPoint(x: center.x + 28 * scale, y: center.y - 7 * scale),
            radius: 4.2 * scale,
            color: NSColor(srgbRed: 68 / 255, green: 177 / 255, blue: 235 / 255, alpha: 1),
            scale: scale
        )
        drawElectron(
            at: NSPoint(x: center.x - 24 * scale, y: center.y + 18 * scale),
            radius: 3.6 * scale,
            color: NSColor(srgbRed: 119 / 255, green: 213 / 255, blue: 244 / 255, alpha: 1),
            scale: scale
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func drawElectron(at center: NSPoint, radius: CGFloat, color: NSColor, scale: CGFloat) {
        let path = NSBezierPath(
            ovalIn: NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
        color.setFill()
        path.fill()
        path.lineWidth = max(1, 1.5 * scale)
        NSColor.white.setStroke()
        path.stroke()
    }
}
