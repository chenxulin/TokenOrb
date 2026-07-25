import AppKit

final class AppearanceWindowController: NSWindowController {
    private let settings: AppSettings
    private let sizeSlider = NSSlider(value: 60, minValue: 44, maxValue: 112, target: nil, action: nil)
    private let sizeLabel = NSTextField(labelWithString: "60 px")
    private let colorWell = NSColorWell()

    var onChange: (() -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 355),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "悬浮球外观"
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
        sizeSlider.doubleValue = Double(settings.orbSize)
        sizeLabel.stringValue = "\(Int(settings.orbSize)) px"
        colorWell.color = settings.accentColor
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }

        let heading = NSTextField(labelWithString: "悬浮球外观")
        heading.font = .systemFont(ofSize: 23, weight: .bold)
        let subtitle = NSTextField(labelWithString: "调整大小与主题色，设置会自动保存")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor

        let sizeTitle = NSTextField(labelWithString: "大小")
        sizeTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        sizeSlider.target = self
        sizeSlider.action = #selector(sizeChanged(_:))
        sizeLabel.alignment = .right
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let sizeRow = NSStackView(views: [sizeSlider, sizeLabel])
        sizeRow.orientation = .horizontal
        sizeRow.spacing = 14
        sizeRow.alignment = .centerY

        let colorTitle = NSTextField(labelWithString: "颜色预设")
        colorTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        let colors: [NSColor] = [
            NSColor(hex: "#2FA4EB"),
            NSColor(hex: "#2FBF9B"),
            NSColor(hex: "#8274F2"),
            NSColor(hex: "#4C86F3"),
            NSColor(hex: "#F39A62"),
            NSColor(hex: "#EB6F92"),
        ]
        let colorButtons = colors.map { color -> NSButton in
            let button = ColorPresetButton(color: color)
            button.target = self
            button.action = #selector(presetSelected(_:))
            return button
        }
        let colorRow = NSStackView(views: colorButtons)
        colorRow.orientation = .horizontal
        colorRow.spacing = 10

        colorWell.color = settings.accentColor
        colorWell.target = self
        colorWell.action = #selector(customColorChanged(_:))
        let customLabel = NSTextField(labelWithString: "自定义颜色")
        customLabel.font = .systemFont(ofSize: 12)
        let customRow = NSStackView(views: [customLabel, colorWell, NSView()])
        customRow.orientation = .horizontal
        customRow.spacing = 10
        customRow.alignment = .centerY

        let stack = NSStackView(views: [
            heading,
            subtitle,
            sizeTitle,
            sizeRow,
            colorTitle,
            colorRow,
            customRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            sizeRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            sizeSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
            colorRow.heightAnchor.constraint(equalToConstant: 46),
            customRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @objc private func sizeChanged(_ sender: NSSlider) {
        settings.orbSize = CGFloat(sender.doubleValue)
        sizeLabel.stringValue = "\(Int(sender.doubleValue.rounded())) px"
        onChange?()
    }

    @objc private func presetSelected(_ sender: ColorPresetButton) {
        settings.accentColor = sender.presetColor
        colorWell.color = sender.presetColor
        onChange?()
    }

    @objc private func customColorChanged(_ sender: NSColorWell) {
        settings.accentColor = sender.color
        onChange?()
    }
}

private final class ColorPresetButton: NSButton {
    let presetColor: NSColor

    init(color: NSColor) {
        presetColor = color
        super.init(frame: NSRect(x: 0, y: 0, width: 46, height: 46))
        isBordered = false
        title = ""
        toolTip = color.hexString
        setAccessibilityLabel("颜色 \(color.hexString)")
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = 23
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.white.cgColor
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 46),
            heightAnchor.constraint(equalToConstant: 46),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
