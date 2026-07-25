import AppKit
import TokenOrbCore

final class AboutWindowController: NSWindowController {
    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 452),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "关于 \(AppIdentity.productName)"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        super.init(window: panel)
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.white.cgColor

        let logo = TokenOrbLogoView()
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.setAccessibilityLabel("Token Orb 图标")

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

        let footer = NSView()
        footer.wantsLayer = true
        footer.layer?.backgroundColor = NSColor(srgbRed: 248 / 255, green: 248 / 255, blue: 248 / 255, alpha: 1).cgColor
        footer.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(footer)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(divider)

        let confirm = NSButton(title: "确定", target: self, action: #selector(closeWindow))
        confirm.keyEquivalent = "\r"
        confirm.bezelStyle = .rounded
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
        window?.orderOut(nil)
    }
}

private final class TokenOrbLogoView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let size = min(bounds.width, bounds.height)
        let scale = size / 84
        let center = NSPoint(x: bounds.midX, y: bounds.midY)

        NSColor(srgbRed: 239 / 255, green: 248 / 255, blue: 1, alpha: 1).setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: center.x - 38 * scale,
                y: center.y - 38 * scale,
                width: 76 * scale,
                height: 76 * scale
            )
        ).fill()

        let ringColor = NSColor(srgbRed: 87 / 255, green: 135 / 255, blue: 165 / 255, alpha: 1)
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
                ringColor.setStroke()
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
        NSColor(srgbRed: 53 / 255, green: 128 / 255, blue: 174 / 255, alpha: 1).setStroke()
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
