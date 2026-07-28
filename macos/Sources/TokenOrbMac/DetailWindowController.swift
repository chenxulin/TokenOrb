import AppKit
import TokenOrbCore

private final class EscapeClosingDetailPanel: NSPanel {
    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

private enum DetailPalette {
    struct Surfaces {
        let card: NSColor
        let cardBorder: NSColor
        let inset: NSColor
        let insetBorder: NSColor
        let progressTrack: NSColor
    }

    static let primaryText = adaptive(
        light: color(23, 56, 75),
        dark: color(239, 248, 252)
    )
    static let secondaryText = adaptive(
        light: color(72, 102, 119),
        dark: color(180, 203, 214)
    )
    static let metadataText = adaptive(
        light: color(47, 91, 113),
        dark: color(201, 220, 229)
    )
    static let footerText = adaptive(
        light: color(56, 86, 100),
        dark: color(199, 216, 224)
    )

    static func surfaces(for appearance: NSAppearance) -> Surfaces {
        if isDark(appearance) {
            return Surfaces(
                card: color(38, 64, 79),
                cardBorder: color(72, 103, 120),
                inset: color(27, 50, 63),
                insetBorder: color(61, 91, 106),
                progressTrack: color(67, 94, 107)
            )
        }
        return Surfaces(
            card: color(244, 250, 253),
            cardBorder: color(190, 213, 225),
            inset: color(229, 241, 247),
            insetBorder: color(198, 219, 229),
            progressTrack: color(210, 229, 238)
        )
    }

    static func toneColor(_ tone: OrbQuotaTone) -> NSColor {
        adaptive(
            light: toneColor(tone, dark: false),
            dark: toneColor(tone, dark: true)
        )
    }

    static func toneColor(_ tone: OrbQuotaTone, for appearance: NSAppearance) -> NSColor {
        toneColor(tone, dark: isDark(appearance))
    }

    private static func toneColor(_ tone: OrbQuotaTone, dark: Bool) -> NSColor {
        switch (tone, dark) {
        case (.healthy, false):
            return color(8, 127, 91)
        case (.healthy, true):
            return color(90, 221, 180)
        case (.warning, false):
            return color(143, 82, 0)
        case (.warning, true):
            return color(255, 207, 112)
        case (.critical, false), (.depleted, false):
            return color(183, 49, 75)
        case (.critical, true), (.depleted, true):
            return color(255, 139, 158)
        case (.waiting, false):
            return color(34, 105, 157)
        case (.waiting, true):
            return color(119, 197, 246)
        }
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

private final class DetailSurfaceView: NSView {
    enum Style {
        case card
        case inset
    }

    private let style: Style

    init(style: Style, cornerRadius: CGFloat) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let surfaces = DetailPalette.surfaces(for: effectiveAppearance)
        switch style {
        case .card:
            layer?.backgroundColor = surfaces.card.cgColor
            layer?.borderColor = surfaces.cardBorder.cgColor
        case .inset:
            layer?.backgroundColor = surfaces.inset.cgColor
            layer?.borderColor = surfaces.insetBorder.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private final class DetailStatusPillView: NSView {
    var tone = OrbQuotaTone.waiting {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let color = DetailPalette.toneColor(tone, for: effectiveAppearance)
        let alpha: CGFloat = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? 0.20
            : 0.12
        layer?.backgroundColor = color.withAlphaComponent(alpha).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

final class DetailWindowController: NSWindowController, NSWindowDelegate {
    private let statusLabel = NSTextField(labelWithString: "正在准备…")
    private let statusPill = DetailStatusPillView()
    private let primaryCard = QuotaCardView()
    private let secondaryCard = QuotaCardView()
    private let creditsValue = NSTextField(labelWithString: "待补充")
    private let planValue = NSTextField(labelWithString: "待补充")
    private let sourceLabel = NSTextField(labelWithString: "等待额度数据")
    private let capturedAtLabel = NSTextField(labelWithString: "")
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
        let statusTone: OrbQuotaTone = connected ? .healthy : .warning
        let statusColor = DetailPalette.toneColor(statusTone)
        statusLabel.textColor = statusColor
        statusPill.tone = statusTone
        statusPill.toolTip = status

        primaryCard.update(window: snapshot?.primary)
        secondaryCard.update(window: snapshot?.secondary)
        primaryCard.isHidden = snapshot?.primary?.usedPercent == nil
        secondaryCard.isHidden = snapshot?.secondary?.usedPercent == nil
        creditsValue.stringValue = snapshot.map { QuotaFormatting.credits($0.credits) } ?? "—"
        planValue.stringValue = snapshot.map { QuotaFormatting.planName($0.planType) } ?? "—"

        if let snapshot {
            sourceLabel.stringValue = "数据来源：\(QuotaFormatting.dataSource(snapshot))"
            capturedAtLabel.stringValue = QuotaFormatting.capturedAtText(snapshot)
        } else {
            sourceLabel.stringValue = "等待 Codex 额度数据…"
            capturedAtLabel.stringValue = ""
        }

        let visibleCards = [snapshot?.primary, snapshot?.secondary]
            .compactMap { $0 }
            .filter { $0.usedPercent != nil }
            .count
        window?.setContentSize(NSSize(width: 344, height: CGFloat(192 + visibleCards * 104)))
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
        title.textColor = .labelColor

        statusLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        statusLabel.alignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusPill.wantsLayer = true
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

        let infoCard = DetailSurfaceView(style: .card, cornerRadius: 12)
        infoCard.translatesAutoresizingMaskIntoConstraints = false

        let creditsTitle = NSTextField(labelWithString: "额外积分")
        let planTitle = NSTextField(labelWithString: "当前套餐")
        [creditsTitle, planTitle].forEach {
            $0.textColor = DetailPalette.secondaryText
            $0.font = .systemFont(ofSize: 12)
        }
        [creditsValue, planValue].forEach {
            $0.textColor = DetailPalette.primaryText
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

        [sourceLabel, capturedAtLabel].forEach {
            $0.textColor = DetailPalette.footerText
            $0.font = .systemFont(ofSize: 11)
        }
        sourceLabel.lineBreakMode = .byTruncatingTail
        sourceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        capturedAtLabel.alignment = .right
        capturedAtLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let footerRow = NSStackView(views: [sourceLabel, NSView(), capturedAtLabel])
        footerRow.orientation = .horizontal
        footerRow.alignment = .centerY

        let stack = NSStackView(views: [
            titleRow,
            primaryCard,
            secondaryCard,
            infoCard,
            footerRow,
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
            footerRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
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
    private let resetDateLabel = NSTextField(labelWithString: "时间未知")
    private let resetCountdownLabel = NSTextField(labelWithString: "")
    private var quotaWindow: QuotaWindow?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = DetailPalette.primaryText
        remainingLabel.font = .systemFont(ofSize: 16, weight: .bold)
        remainingLabel.textColor = DetailPalette.toneColor(.healthy)
        remainingLabel.alignment = .right
        [resetDateLabel, resetCountdownLabel].forEach {
            $0.font = .systemFont(ofSize: 10.5, weight: .semibold)
            $0.textColor = DetailPalette.metadataText
        }
        resetCountdownLabel.alignment = .right
        resetCountdownLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let resetTitle = NSTextField(labelWithString: "下轮重置")
        resetTitle.font = .systemFont(ofSize: 10)
        resetTitle.textColor = DetailPalette.secondaryText
        let resetRow = NSStackView(views: [
            resetTitle,
            resetDateLabel,
            NSView(),
            resetCountdownLabel,
        ])
        resetRow.orientation = .horizontal
        resetRow.spacing = 6
        resetRow.alignment = .centerY
        resetRow.translatesAutoresizingMaskIntoConstraints = false

        let resetPanel = DetailSurfaceView(style: .inset, cornerRadius: 8)
        resetPanel.addSubview(resetRow)
        NSLayoutConstraint.activate([
            resetRow.leadingAnchor.constraint(equalTo: resetPanel.leadingAnchor, constant: 8),
            resetRow.trailingAnchor.constraint(equalTo: resetPanel.trailingAnchor, constant: -8),
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

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let surfaces = DetailPalette.surfaces(for: effectiveAppearance)
        layer?.backgroundColor = surfaces.card.cgColor
        layer?.borderColor = surfaces.cardBorder.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        progress.needsDisplay = true
    }

    func update(window: QuotaWindow?) {
        quotaWindow = window
        titleLabel.stringValue = "\(QuotaFormatting.windowName(window))额度"
        if let window {
            remainingLabel.stringValue = "剩余 \(QuotaFormatting.roundedPercent(window.remainingPercent))%"
            progress.remainingPercent = window.remainingPercent
            let tone = OrbVisualMetrics.tone(remaining: window.remainingPercent)
            remainingLabel.textColor = DetailPalette.toneColor(tone)
            progress.tone = tone
            refreshReset()
        } else {
            remainingLabel.stringValue = "剩余 —"
            remainingLabel.textColor = DetailPalette.secondaryText
            progress.remainingPercent = 0
            progress.tone = .waiting
            resetDateLabel.stringValue = "时间未知"
            resetCountdownLabel.stringValue = ""
        }
    }

    func refreshReset(now: Date = Date()) {
        resetDateLabel.stringValue = QuotaFormatting.resetDateText(quotaWindow, now: now)
        resetCountdownLabel.stringValue = QuotaFormatting.resetCountdownText(quotaWindow, now: now)
    }

}

private final class QuotaBarView: NSView {
    var remainingPercent = 0.0 {
        didSet { needsDisplay = true }
    }
    var tone = OrbQuotaTone.waiting {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 7)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let track = bounds.insetBy(dx: 0, dy: max(0, (bounds.height - 7) / 2))
        let radius = track.height / 2
        DetailPalette.surfaces(for: effectiveAppearance).progressTrack.setFill()
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
        DetailPalette.toneColor(tone, for: effectiveAppearance).setFill()
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
