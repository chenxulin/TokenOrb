import AppKit
import TokenOrbCore

final class DetailWindowController: NSWindowController {
    private let statusLabel = NSTextField(labelWithString: "正在准备…")
    private let primaryCard = QuotaCardView()
    private let secondaryCard = QuotaCardView()
    private let creditsValue = NSTextField(labelWithString: "待补充")
    private let planValue = NSTextField(labelWithString: "待补充")
    private let footerLabel = NSTextField(labelWithString: "等待额度数据")
    private var snapshot: QuotaSnapshot?

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 410, height: 430),
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Token Orb"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: panel)
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(snapshot: QuotaSnapshot?, status: String, connected: Bool) {
        self.snapshot = snapshot
        statusLabel.stringValue = connected ? "实时" : status
        statusLabel.textColor = connected ? .systemGreen : .secondaryLabelColor

        primaryCard.update(window: snapshot?.primary)
        secondaryCard.update(window: snapshot?.secondary)
        primaryCard.isHidden = snapshot?.primary == nil
        secondaryCard.isHidden = snapshot?.secondary == nil
        creditsValue.stringValue = QuotaFormatting.credits(snapshot?.credits)
        planValue.stringValue = QuotaFormatting.planName(snapshot?.planType)

        if let snapshot {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "MM-dd HH:mm:ss"
            footerLabel.stringValue = "数据：\(snapshot.source) · \(formatter.string(from: snapshot.capturedAt))"
        } else {
            footerLabel.stringValue = "等待 Codex 产生额度数据"
        }
    }

    func show(relativeTo orbFrame: NSRect) {
        guard let window else { return }
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(orbFrame) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let size = window.frame.size
        let gap: CGFloat = 14
        let rightOrigin = orbFrame.maxX + gap
        let x = rightOrigin + size.width <= visible.maxX
            ? rightOrigin
            : orbFrame.minX - size.width - gap
        let y = (orbFrame.midY - size.height / 2)
            .clamped(to: visible.minY...(visible.maxY - size.height))
        window.setFrameOrigin(NSPoint(x: x, y: y))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        title.font = .systemFont(ofSize: 25, weight: .bold)
        title.textColor = NSColor(calibratedRed: 0.08, green: 0.28, blue: 0.39, alpha: 1)

        statusLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        statusLabel.alignment = .right
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)

        let titleRow = NSStackView(views: [title, NSView(), statusLabel])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY

        let subtitle = NSTextField(labelWithString: "最紧张的额度会显示在悬浮球上")
        subtitle.textColor = .secondaryLabelColor
        subtitle.font = .systemFont(ofSize: 12)

        primaryCard.translatesAutoresizingMaskIntoConstraints = false
        secondaryCard.translatesAutoresizingMaskIntoConstraints = false

        let infoCard = NSView()
        infoCard.wantsLayer = true
        infoCard.layer?.cornerRadius = 14
        infoCard.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.06).cgColor
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
            wrappingLabelWithString: "只调用本机 Codex；不会读取、上传或保存登录凭据"
        )
        privacyLabel.textColor = .tertiaryLabelColor
        privacyLabel.font = .systemFont(ofSize: 10.5)

        let stack = NSStackView(views: [
            titleRow,
            subtitle,
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
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: effect.topAnchor, constant: 30),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: effect.bottomAnchor, constant: -20),
            titleRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            primaryCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            secondaryCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            infoCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            infoCard.heightAnchor.constraint(equalToConstant: 72),
            infoGrid.leadingAnchor.constraint(equalTo: infoCard.leadingAnchor, constant: 16),
            infoGrid.trailingAnchor.constraint(equalTo: infoCard.trailingAnchor, constant: -16),
            infoGrid.centerYAnchor.constraint(equalTo: infoCard.centerYAnchor),
            footerLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            privacyLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }
}

private final class QuotaCardView: NSView {
    private let titleLabel = NSTextField(labelWithString: "额度")
    private let remainingLabel = NSTextField(labelWithString: "剩余 —")
    private let progress = NSProgressIndicator()
    private let resetLabel = NSTextField(labelWithString: "刷新时间待补充")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.24).cgColor
        layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.06).cgColor

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        remainingLabel.font = .systemFont(ofSize: 16, weight: .bold)
        remainingLabel.textColor = .systemGreen
        remainingLabel.alignment = .right
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 100
        progress.controlTint = .blueControlTint
        resetLabel.font = .systemFont(ofSize: 11)
        resetLabel.textColor = .secondaryLabelColor

        let topRow = NSStackView(views: [titleLabel, NSView(), remainingLabel])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY

        let stack = NSStackView(views: [topRow, progress, resetLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 92),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            topRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            progress.widthAnchor.constraint(equalTo: stack.widthAnchor),
            resetLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(window: QuotaWindow?) {
        titleLabel.stringValue = "\(QuotaFormatting.windowName(window))额度"
        if let window {
            remainingLabel.stringValue = "剩余 \(Int(window.remainingPercent.rounded()))%"
            progress.doubleValue = window.remainingPercent
            resetLabel.stringValue = "下轮重置　\(QuotaFormatting.resetText(window))"
        } else {
            remainingLabel.stringValue = "剩余 —"
            progress.doubleValue = 0
            resetLabel.stringValue = "刷新时间待补充"
        }
    }
}
