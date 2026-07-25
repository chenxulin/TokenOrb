import AppKit
import TokenOrbCore

final class AppearanceWindowController: NSWindowController, NSTextFieldDelegate {
    private let settings: AppSettings
    private let sizeSlider = NSSlider(
        value: OrbVisualMetrics.defaultDiameter,
        minValue: OrbVisualMetrics.minimumDiameter,
        maxValue: OrbVisualMetrics.maximumDiameter,
        target: nil,
        action: nil
    )
    private let sizeField = NSTextField(string: "60")
    private let colorWell = NSColorWell()
    private let colorPreview = NSView()
    private let hexLabel = NSTextField(labelWithString: "#2FA4EB")
    private var presetButtons: [ColorPresetButton] = []
    private var pendingColor = NSColor(hex: "#2FA4EB")

    var onChange: (() -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 382),
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
        let size = settings.orbSize.rounded()
        pendingColor = settings.accentColor
        sizeSlider.doubleValue = Double(size)
        sizeField.stringValue = "\(Int(size))"
        colorWell.color = pendingColor
        updateColorSelection()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }

        let heading = NSTextField(labelWithString: "悬浮球外观")
        heading.font = .systemFont(ofSize: 23, weight: .bold)
        let subtitle = NSTextField(labelWithString: "调整大小与主题色，保存后应用")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor

        let sizeTitle = NSTextField(labelWithString: "大小（24–160 px）")
        sizeTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        sizeSlider.isContinuous = true
        sizeSlider.target = self
        sizeSlider.action = #selector(sizeChanged(_:))

        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = NSNumber(value: OrbVisualMetrics.minimumDiameter)
        formatter.maximum = NSNumber(value: OrbVisualMetrics.maximumDiameter)
        formatter.allowsFloats = false
        sizeField.formatter = formatter
        sizeField.delegate = self
        sizeField.alignment = .right
        sizeField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        sizeField.translatesAutoresizingMaskIntoConstraints = false
        sizeField.widthAnchor.constraint(equalToConstant: 58).isActive = true

        let unit = NSTextField(labelWithString: "px")
        unit.textColor = .secondaryLabelColor
        let sizeRow = NSStackView(views: [sizeSlider, sizeField, unit])
        sizeRow.orientation = .horizontal
        sizeRow.spacing = 9
        sizeRow.alignment = .centerY

        let colorTitle = NSTextField(labelWithString: "颜色预设")
        colorTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        let colors = ["#2FA4EB", "#2FBF9B", "#8274F2", "#4C86F3", "#F39A62", "#EB6F92"]
            .map(NSColor.init(hex:))
        presetButtons = colors.map { color in
            let button = ColorPresetButton(color: color)
            button.target = self
            button.action = #selector(presetSelected(_:))
            return button
        }
        let colorRow = NSStackView(views: presetButtons)
        colorRow.orientation = .horizontal
        colorRow.spacing = 10

        colorWell.target = self
        colorWell.action = #selector(customColorChanged(_:))
        colorWell.toolTip = "选择自定义颜色"
        let customLabel = NSTextField(labelWithString: "自定义颜色")
        customLabel.font = .systemFont(ofSize: 12)

        colorPreview.wantsLayer = true
        colorPreview.layer?.cornerRadius = 8
        colorPreview.layer?.borderWidth = 1
        colorPreview.layer?.borderColor = NSColor.separatorColor.cgColor
        colorPreview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            colorPreview.widthAnchor.constraint(equalToConstant: 28),
            colorPreview.heightAnchor.constraint(equalToConstant: 28),
        ])
        hexLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let customRow = NSStackView(views: [customLabel, colorWell, colorPreview, hexLabel, NSView()])
        customRow.orientation = .horizontal
        customRow.spacing = 10
        customRow.alignment = .centerY

        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelChanges))
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "保存", target: self, action: #selector(saveChanges))
        save.keyEquivalent = "\r"
        save.bezelStyle = .rounded
        let buttonRow = NSStackView(views: [NSView(), cancel, save])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        let stack = NSStackView(views: [
            heading,
            subtitle,
            sizeTitle,
            sizeRow,
            colorTitle,
            colorRow,
            customRow,
            buttonRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 13
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
            sizeRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            sizeSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
            colorRow.heightAnchor.constraint(equalToConstant: 46),
            customRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let value = Double(sizeField.stringValue) else { return }
        sizeSlider.doubleValue = value.clamped(
            to: OrbVisualMetrics.minimumDiameter...OrbVisualMetrics.maximumDiameter
        )
    }

    @objc private func sizeChanged(_ sender: NSSlider) {
        let rounded = sender.doubleValue.rounded()
        sender.doubleValue = rounded
        sizeField.stringValue = "\(Int(rounded))"
    }

    @objc private func presetSelected(_ sender: ColorPresetButton) {
        pendingColor = sender.presetColor
        colorWell.color = pendingColor
        updateColorSelection()
    }

    @objc private func customColorChanged(_ sender: NSColorWell) {
        pendingColor = sender.color
        updateColorSelection()
    }

    @objc private func saveChanges() {
        let parsed = Double(sizeField.stringValue) ?? sizeSlider.doubleValue
        settings.orbSize = CGFloat(parsed.clamped(
            to: OrbVisualMetrics.minimumDiameter...OrbVisualMetrics.maximumDiameter
        ).rounded())
        settings.accentColor = pendingColor
        window?.orderOut(nil)
        onChange?()
    }

    @objc private func cancelChanges() {
        window?.orderOut(nil)
    }

    private func updateColorSelection() {
        let hex = pendingColor.hexString
        hexLabel.stringValue = hex
        colorPreview.layer?.backgroundColor = pendingColor.cgColor
        for button in presetButtons {
            button.isPresetSelected = button.presetColor.hexString == hex
        }
    }
}

private final class ColorPresetButton: NSButton {
    let presetColor: NSColor

    var isPresetSelected = false {
        didSet {
            layer?.borderWidth = isPresetSelected ? 3 : 2
            layer?.borderColor = (
                isPresetSelected ? NSColor.controlAccentColor : NSColor.white
            ).cgColor
        }
    }

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
