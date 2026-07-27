import AppKit
import TokenOrbCore

private final class EscapeClosingDetailPanel: NSPanel {
    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

final class DetailWindowController: NSWindowController, NSWindowDelegate {
    private let statusLabel = NSTextField(labelWithString: "正在准备…")
    private let statusPill = NSView()
    private let primaryCard = QuotaCardView()
    private let secondaryCard = QuotaCardView()
    private let creditsValue = NSTextField(labelWithString: "待补充")
    private let planValue = NSTextField(labelWithString: "待补充")
    private let footerLabel = NSTextField(labelWithString: "等待额度数据")
    private var snapshot: QuotaSnapshot?
    private(set) var lastAutoDismissedAt = Date.distantPast

    init() {
        let panel = EscapeClosingDetailPanel(
            contentRect: NSRect(x: 0, y: 0, width: 344, height: 430),
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = AppIdentity.productName
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: panel)
        panel.delegate = self
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(snapshot: QuotaSnapshot?, status: String, connected: Bool) {
        self.snapshot = snapshot
        let connecting = !connected && (
            status.localizedCaseInsensitiveContains("正在")
                || status.localizedCaseInsensitiveContains("已连接")
                || status.localizedCaseInsensitiveContains("准备")
        )
        statusLabel.stringValue = connected ? "实时" : (connecting ? "连接中" : "本地")
        let statusColor = connected
            ? NSColor(srgbRed: 45 / 255, green: 194 / 255, blue: 145 / 255, alpha: 1)
            : NSColor(srgbRed: 239 / 255, green: 169 / 255, blue: 66 / 255, alpha: 1)
        statusLabel.textColor = statusColor
        statusPill.layer?.backgroundColor = statusColor.withAlphaComponent(35 / 255).cgColor
        statusPill.toolTip = status

        primaryCard.update(window: snapshot?.primary)
        secondaryCard.update(window: snapshot?.secondary)
        primaryCard.isHidden = snapshot?.primary?.usedPercent == nil
        secondaryCard.isHidden = snapshot?.secondary?.usedPercent == nil
        creditsValue.stringValue = snapshot.map { QuotaFormatting.credits($0.credits) } ?? "—"
        planValue.stringValue = snapshot.map { QuotaFormatting.planName($0.planType) } ?? "—"

        if let snapshot {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "MM-dd HH:mm:ss"
            footerLabel.stringValue = "数据：\(snapshot.source) · \(formatter.string(from: snapshot.capturedAt))"
        } else {
            footerLabel.stringValue = "等待 Codex 额度数据…"
        }

        let visibleCards = [snapshot?.primary, snapshot?.secondary]
            .compactMap { $0 }
            .filter { $0.usedPercent != nil }
            .count
        window?.setContentSize(NSSize(width: 344, height: CGFloat(224 + visibleCards * 104)))
    }

    func refreshTimeLabels(now: Date = Date()) {
        primaryCard.refreshReset(now: now)
        secondaryCard.refreshReset(now: now)
    }

    var isVisible: Bool { window?.isVisible == true }

    func hide() {
        window?.orderOut(nil)
    }

    func toggle(relativeTo orbFrame: NSRect) {
        guard let window else { return }
        if window.isVisible {
            window.orderOut(nil)
            return
        }
        guard Date().timeIntervalSince(lastAutoDismissedAt) >= 0.45 else { return }
        show(relativeTo: orbFrame)
    }

    func show(relativeTo orbFrame: NSRect) {
        guard let window else { return }
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(orbFrame) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let size = window.frame.size
        let gap: CGFloat = 8
        let rightOrigin = orbFrame.maxX + gap
        let preferredX = rightOrigin + size.width <= visible.maxX
            ? rightOrigin
            : orbFrame.minX - size.width - gap
        let maximumX = max(visible.minX, visible.maxX - size.width)
        let maximumY = max(visible.minY, visible.maxY - size.height)
        let x = preferredX.clamped(to: visible.minX...maximumX)
        let y = (orbFrame.maxY + 12 - size.height).clamped(to: visible.minY...maximumY)
        window.setFrameOrigin(NSPoint(x: x, y: y))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard window?.isVisible == true else { return }
        lastAutoDismissedAt = Date()
        window?.orderOut(nil)
    }

    private func buildContent() {
        guard let window else { return }
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = effect

        let title = NSTextField(labelWithString: "Codex 额度")
        title.font = .systemFont(ofSize: 18, weight: .bold)
        title.textColor = NSColor(srgbRed: 24 / 255, green: 72 / 255, blue: 99 / 255, alpha: 1)

        statusLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        statusLabel.alignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusPill.wantsLayer = true
        statusPill.layer?.cornerRadius = 10
        statusPill.translatesAutoresizingMaskIntoConstraints = false
        statusPill.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: statusPill.leadingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: statusPill.trailingAnchor, constant: -8),
            statusLabel.topAnchor.constraint(equalTo: statusPill.topAnchor, constant: 4),
            statusLabel.bottomAnchor.constraint(equalTo: statusPill.bottomAnchor, constant: -4),
        ])

        let closeButton = NSButton(title: "×", target: self, action: #selector(closeDetail))
        closeButton.isBordered = false
        closeButton.font = .systemFont(ofSize: 16)
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = "关闭"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            closeButton.widthAnchor.constraint(equalToConstant: 25),
            closeButton.heightAnchor.constraint(equalToConstant: 25),
        ])

        let titleRow = NSStackView(views: [title, NSView(), statusPill, closeButton])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY

        primaryCard.translatesAutoresizingMaskIntoConstraints = false
        secondaryCard.translatesAutoresizingMaskIntoConstraints = false

        let infoCard = NSView()
        infoCard.wantsLayer = true
        infoCard.layer?.cornerRadius = 12
        infoCard.layer?.backgroundColor = NSColor(
            srgbRed: 238 / 255,
            green: 249 / 255,
            blue: 1,
            alpha: 1
        ).cgColor
        infoCard.translatesAutoresizingMaskIntoConstraints = false

        let creditsTitle = NSTextField(labelWithString: "额外积分")
        let planTitle = NSTextField(labelWithString: "当前套餐")
        [creditsTitle, planTitle].forEach {
            $0.textColor = .secondaryLabelColor
            $0.font = .systemFont(ofSize: 12)
        }
        [creditsValue, planValue].forEach {
            $0.font = .systemFont(ofSize: 13, weight: .semibold)
            $0.alignment = .right
        }

        let infoGrid = NSGridView(views: [
            [creditsTitle, creditsValue],
            [planTitle, planValue],
        ])
        infoGrid.rowSpacing = 8
        infoGrid.columnSpacing = 16
        infoGrid.translatesAutoresizingMaskIntoConstraints = false
        infoGrid.column(at: 0).xPlacement = .leading
        infoGrid.column(at: 1).xPlacement = .trailing
        infoCard.addSubview(infoGrid)

        footerLabel.textColor = .secondaryLabelColor
        footerLabel.font = .systemFont(ofSize: 11)
        footerLabel.lineBreakMode = .byTruncatingMiddle

        let privacyLabel = NSTextField(
            wrappingLabelWithString: "只调用本机 Codex；auth.json 仅用于内存身份指纹，不保存登录凭据"
        )
        privacyLabel.textColor = .tertiaryLabelColor
        privacyLabel.font = .systemFont(ofSize: 10.5)

        let stack = NSStackView(views: [
            titleRow,
            primaryCard,
            secondaryCard,
            infoCard,
            footerLabel,
            privacyLabel,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: effect.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: effect.bottomAnchor, constant: -16),
            titleRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            primaryCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            secondaryCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            infoCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            infoCard.heightAnchor.constraint(equalToConstant: 60),
            infoGrid.leadingAnchor.constraint(equalTo: infoCard.leadingAnchor, constant: 16),
            infoGrid.trailingAnchor.constraint(equalTo: infoCard.trailingAnchor, constant: -16),
            infoGrid.centerYAnchor.constraint(equalTo: infoCard.centerYAnchor),
            footerLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            privacyLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @objc private func closeDetail() {
        window?.orderOut(nil)
    }
}

private final class QuotaCardView: NSView {
    private let titleLabel = NSTextField(labelWithString: "额度")
    private let remainingLabel = NSTextField(labelWithString: "剩余 —")
    private let progress = QuotaBarView()
    private let resetLabel = NSTextField(labelWithString: "重置时间未知")
    private var quotaWindow: QuotaWindow?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(
            srgbRed: 164 / 255,
            green: 213 / 255,
            blue: 240 / 255,
            alpha: 190 / 255
        ).cgColor
        layer?.backgroundColor = NSColor(
            srgbRed: 232 / 255,
            green: 247 / 255,
            blue: 1,
            alpha: 1
        ).cgColor

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        remainingLabel.font = .systemFont(ofSize: 16, weight: .bold)
        remainingLabel.textColor = .systemGreen
        remainingLabel.alignment = .right
        resetLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
        resetLabel.textColor = NSColor(srgbRed: 56 / 255, green: 103 / 255, blue: 130 / 255, alpha: 1)

        let resetTitle = NSTextField(labelWithString: "下轮重置")
        resetTitle.font = .systemFont(ofSize: 10)
        resetTitle.textColor = NSColor(srgbRed: 92 / 255, green: 102 / 255, blue: 110 / 255, alpha: 1)
        let resetRow = NSStackView(views: [resetTitle, resetLabel])
        resetRow.orientation = .horizontal
        resetRow.spacing = 9
        resetRow.alignment = .centerY
        resetRow.translatesAutoresizingMaskIntoConstraints = false

        let resetPanel = NSView()
        resetPanel.wantsLayer = true
        resetPanel.layer?.cornerRadius = 8
        resetPanel.layer?.borderWidth = 1
        resetPanel.layer?.borderColor = NSColor(
            srgbRed: 164 / 255,
            green: 213 / 255,
            blue: 240 / 255,
            alpha: 145 / 255
        ).cgColor
        resetPanel.layer?.backgroundColor = NSColor(
            srgbRed: 218 / 255,
            green: 241 / 255,
            blue: 253 / 255,
            alpha: 1
        ).cgColor
        resetPanel.addSubview(resetRow)
        NSLayoutConstraint.activate([
            resetRow.leadingAnchor.constraint(equalTo: resetPanel.leadingAnchor, constant: 8),
            resetRow.trailingAnchor.constraint(lessThanOrEqualTo: resetPanel.trailingAnchor, constant: -8),
            resetRow.centerYAnchor.constraint(equalTo: resetPanel.centerYAnchor),
        ])

        let topRow = NSStackView(views: [titleLabel, NSView(), remainingLabel])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY

        let stack = NSStackView(views: [topRow, progress, resetPanel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 100),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            topRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            progress.widthAnchor.constraint(equalTo: stack.widthAnchor),
            resetPanel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            resetPanel.heightAnchor.constraint(equalToConstant: 27),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(window: QuotaWindow?) {
        quotaWindow = window
        titleLabel.stringValue = "\(QuotaFormatting.windowName(window))额度"
        if let window {
            remainingLabel.stringValue = "剩余 \(QuotaFormatting.roundedPercent(window.remainingPercent))%"
            progress.remainingPercent = window.remainingPercent
            let color = quotaColor(remaining: window.remainingPercent)
            remainingLabel.textColor = color
            progress.accentColor = color
            refreshReset()
        } else {
            remainingLabel.stringValue = "剩余 —"
            remainingLabel.textColor = .secondaryLabelColor
            progress.remainingPercent = 0
            progress.accentColor = .systemBlue
            resetLabel.stringValue = "重置时间未知"
        }
    }

    func refreshReset(now: Date = Date()) {
        resetLabel.stringValue = QuotaFormatting.resetText(quotaWindow, now: now)
    }

    private func quotaColor(remaining: Double) -> NSColor {
        switch OrbVisualMetrics.tone(remaining: remaining) {
        case .healthy:
            return NSColor(srgbRed: 45 / 255, green: 194 / 255, blue: 145 / 255, alpha: 1)
        case .warning:
            return NSColor(srgbRed: 239 / 255, green: 169 / 255, blue: 66 / 255, alpha: 1)
        case .critical, .depleted:
            return NSColor(srgbRed: 232 / 255, green: 100 / 255, blue: 119 / 255, alpha: 1)
        case .waiting:
            return .systemBlue
        }
    }
}

private final class QuotaBarView: NSView {
    var remainingPercent = 0.0 {
        didSet { needsDisplay = true }
    }
    var accentColor = NSColor.systemBlue {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 7)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let track = bounds.insetBy(dx: 0, dy: max(0, (bounds.height - 7) / 2))
        let radius = track.height / 2
        NSColor(srgbRed: 213 / 255, green: 234 / 255, blue: 245 / 255, alpha: 1).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        let safePercent = remainingPercent.clamped(to: 0...100)
        let fillWidth = track.width * CGFloat(safePercent / 100)
        guard fillWidth > 0.5 else { return }
        let fill = NSRect(
            x: track.minX,
            y: track.minY,
            width: max(track.height, fillWidth),
            height: track.height
        )
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).addClip()
        accentColor.setFill()
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
