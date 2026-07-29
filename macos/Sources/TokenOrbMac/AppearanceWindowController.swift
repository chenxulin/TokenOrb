import AppKit
import TokenOrbCore

private enum AppearanceLayout {
    static let windowWidth: CGFloat = 740
    static let windowHeight: CGFloat = 424
    static let horizontalInset: CGFloat = 24
    static let verticalInset: CGFloat = 18
    static let sectionSpacing: CGFloat = 10
    static let actionButtonWidth: CGFloat = 96
    static let actionButtonHeight: CGFloat = 28
}

private enum AppearancePalette {
    struct Surfaces {
        let canvas: NSColor
        let card: NSColor
        let cardBorder: NSColor
        let option: NSColor
        let optionBorder: NSColor
        let selectedOption: NSColor
        let previewBorder: NSColor
        let swatchBorder: NSColor
        let shadow: NSColor
    }

    static let canvas = adaptive(
        light: color(247, 252, 255),
        dark: color(15, 25, 31)
    )
    static let primaryText = adaptive(
        light: color(24, 72, 99),
        dark: color(237, 248, 252)
    )
    static let secondaryText = adaptive(
        light: color(72, 102, 119),
        dark: color(170, 199, 213)
    )
    static let accent = adaptive(
        light: color(20, 125, 187),
        dark: color(99, 197, 250)
    )
    static let actionFill = adaptive(
        light: color(20, 125, 187),
        dark: color(23, 111, 159)
    )

    static func surfaces(for appearance: NSAppearance) -> Surfaces {
        if isDark(appearance) {
            return Surfaces(
                canvas: color(15, 25, 31),
                card: color(25, 40, 48),
                cardBorder: color(56, 88, 104),
                option: color(20, 35, 43),
                optionBorder: color(62, 102, 121),
                selectedOption: color(23, 65, 84),
                previewBorder: color(84, 137, 163),
                swatchBorder: color(192, 215, 226),
                shadow: .black
            )
        }
        return Surfaces(
            canvas: color(247, 252, 255),
            card: color(253, 255, 255),
            cardBorder: color(184, 222, 242).withAlphaComponent(0.85),
            option: color(250, 254, 255),
            optionBorder: color(184, 222, 242),
            selectedOption: color(226, 245, 255),
            previewBorder: color(164, 213, 240),
            swatchBorder: .white,
            shadow: color(24, 72, 99)
        )
    }

    static func accent(for appearance: NSAppearance) -> NSColor {
        isDark(appearance)
            ? color(99, 197, 250)
            : color(20, 125, 187)
    }

    static func success(for appearance: NSAppearance) -> NSColor {
        isDark(appearance)
            ? color(94, 219, 179)
            : color(49, 190, 145)
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

final class AppearanceWindowController: NSWindowController, NSTextFieldDelegate, NSWindowDelegate {
    private let settings: AppSettings
    private let sizeSlider = NSSlider(
        value: OrbVisualMetrics.defaultDiameter,
        minValue: OrbVisualMetrics.minimumDiameter,
        maxValue: OrbVisualMetrics.maximumDiameter,
        target: nil,
        action: nil
    )
    private let sizeField = NSTextField(
        string: String(Int(OrbAppearanceDefaults.size))
    )
    private let colorPreview = AppearanceColorPreviewView(cornerRadius: 15)
    private let hexLabel = NSTextField(
        labelWithString: OrbAppearanceDefaults.accentHex
    )
    private let previewStyleLabel = NSTextField(
        labelWithString: OrbAppearanceDefaults.textStyle.displayName
    )
    private let previewOrb: OrbView
    private var previewOrbWidthConstraint: NSLayoutConstraint?
    private var previewOrbHeightConstraint: NSLayoutConstraint?
    private var presetButtons: [ColorPresetButton] = []
    private var textStyleButtons: [TextStyleOptionButton] = []
    private var frameRateButtons: [FrameRateOptionButton] = []
    private var pendingColor: NSColor
    private var pendingTextStyle: OrbTextStyle
    private var pendingAnimationFrameRate: Int
    private var colorPickerController: ThemedColorPickerWindowController?

    var onChange: (() -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
        pendingColor = settings.accentColor
        pendingTextStyle = settings.textStyle
        pendingAnimationFrameRate = settings.animationFrameRate
        previewOrb = OrbView(
            frame: NSRect(x: 0, y: 0, width: 104, height: 104),
            accentColor: settings.accentColor,
            textStyle: settings.textStyle,
            animationFrameRate: settings.animationFrameRate,
            isInteractive: false
        )

        let panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: AppearanceLayout.windowWidth,
                height: AppearanceLayout.windowHeight
            ),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "个性化外观"
        panel.titleVisibility = .hidden
        panel.isReleasedWhenClosed = false
        panel.level = .normal
        panel.hidesOnDeactivate = false
        panel.backgroundColor = AppearancePalette.canvas
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.contentView = AppearanceCanvasView(frame: panel.contentView?.frame ?? .zero)
        super.init(window: panel)
        panel.delegate = self
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        let size = settings.orbSize.rounded()
        pendingColor = settings.accentColor
        pendingTextStyle = settings.textStyle
        pendingAnimationFrameRate = settings.animationFrameRate
        sizeSlider.doubleValue = Double(size)
        sizeField.stringValue = "\(Int(size))"
        updateSelectionsAndPreview()
        previewOrb.setAnimating(true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        previewOrb.setAnimating(false)
        window?.orderOut(nil)
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }

        let heading = NSTextField(labelWithString: "个性化外观")
        heading.font = .systemFont(ofSize: 20, weight: .bold)
        heading.textColor = AppearancePalette.primaryText
        let subtitle = NSTextField(labelWithString: "调整尺寸、主题色、数字样式和动画帧率")
        subtitle.font = .systemFont(ofSize: 11.5)
        subtitle.textColor = AppearancePalette.secondaryText
        let headingStack = NSStackView(views: [heading, subtitle])
        headingStack.orientation = .vertical
        headingStack.alignment = .leading
        headingStack.spacing = 4

        sizeSlider.isContinuous = true
        sizeSlider.target = self
        sizeSlider.action = #selector(sizeChanged(_:))
        sizeSlider.trackFillColor = AppearancePalette.accent

        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = NSNumber(value: OrbVisualMetrics.minimumDiameter)
        formatter.maximum = NSNumber(value: OrbVisualMetrics.maximumDiameter)
        formatter.allowsFloats = false
        sizeField.formatter = formatter
        sizeField.delegate = self
        sizeField.alignment = .right
        sizeField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        sizeField.translatesAutoresizingMaskIntoConstraints = false
        sizeField.widthAnchor.constraint(equalToConstant: 58).isActive = true

        colorPreview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            colorPreview.widthAnchor.constraint(equalToConstant: 30),
            colorPreview.heightAnchor.constraint(equalToConstant: 30),
        ])
        hexLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        hexLabel.textColor = AppearancePalette.primaryText

        let previewCard = makePreviewCard()
        let header = NSStackView(views: [headingStack, NSView(), previewCard])
        header.orientation = .horizontal
        header.alignment = .top
        header.spacing = 14
        let sizeCard = makeSizeCard()
        let colorCard = makeColorCard()
        let textStyleCard = makeTextStyleCard()
        let frameRateCard = makeFrameRateCard()
        let actionRow = makeActionRow()

        let leftColumn = NSStackView(views: [sizeCard, colorCard])
        leftColumn.orientation = .vertical
        leftColumn.alignment = .leading
        leftColumn.spacing = AppearanceLayout.sectionSpacing
        sizeCard.widthAnchor.constraint(equalTo: leftColumn.widthAnchor).isActive = true
        colorCard.widthAnchor.constraint(equalTo: leftColumn.widthAnchor).isActive = true

        let rightColumn = NSStackView(views: [frameRateCard, textStyleCard])
        rightColumn.orientation = .vertical
        rightColumn.alignment = .leading
        rightColumn.spacing = AppearanceLayout.sectionSpacing
        textStyleCard.widthAnchor.constraint(equalTo: rightColumn.widthAnchor).isActive = true
        frameRateCard.widthAnchor.constraint(equalTo: rightColumn.widthAnchor).isActive = true

        let controlColumns = NSStackView(views: [leftColumn, rightColumn])
        controlColumns.orientation = .horizontal
        controlColumns.alignment = .top
        controlColumns.distribution = .fillEqually
        controlColumns.spacing = 12
        NSLayoutConstraint.activate([
            sizeCard.heightAnchor.constraint(equalTo: frameRateCard.heightAnchor),
            colorCard.heightAnchor.constraint(equalTo: textStyleCard.heightAnchor),
        ])

        let mainStack = NSStackView(views: [
            header,
            controlColumns,
            actionRow,
        ])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = AppearanceLayout.sectionSpacing
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(
                equalTo: content.leadingAnchor,
                constant: AppearanceLayout.horizontalInset
            ),
            mainStack.trailingAnchor.constraint(
                equalTo: content.trailingAnchor,
                constant: -AppearanceLayout.horizontalInset
            ),
            mainStack.topAnchor.constraint(
                equalTo: content.topAnchor,
                constant: AppearanceLayout.verticalInset
            ),
            mainStack.bottomAnchor.constraint(
                lessThanOrEqualTo: content.bottomAnchor,
                constant: -AppearanceLayout.verticalInset
            ),
            header.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            controlColumns.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            actionRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
        ])
    }

    private func makePreviewCard() -> NSView {
        previewOrb.translatesAutoresizingMaskIntoConstraints = false
        let previewDiameter = CGFloat(OrbVisualMetrics.appearancePreviewDiameter(
            configuredDiameter: sizeSlider.doubleValue
        ))
        let widthConstraint = previewOrb.widthAnchor.constraint(equalToConstant: previewDiameter)
        let heightConstraint = previewOrb.heightAnchor.constraint(equalToConstant: previewDiameter)
        previewOrbWidthConstraint = widthConstraint
        previewOrbHeightConstraint = heightConstraint
        NSLayoutConstraint.activate([widthConstraint, heightConstraint])
        previewOrb.update(
            remainingPercent: 30,
            accentColor: pendingColor,
            textStyle: pendingTextStyle,
            connected: true
        )

        let statusDot = AppearanceStatusDotView()
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusDot.widthAnchor.constraint(equalToConstant: 7),
            statusDot.heightAnchor.constraint(equalToConstant: 7),
        ])
        let eyebrow = NSTextField(labelWithString: "实时预览")
        eyebrow.font = .systemFont(ofSize: 10, weight: .semibold)
        eyebrow.textColor = AppearancePalette.accent
        let status = NSStackView(views: [statusDot, eyebrow])
        status.orientation = .horizontal
        status.alignment = .centerY
        status.spacing = 6
        previewStyleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        previewStyleLabel.textColor = AppearancePalette.primaryText
        previewStyleLabel.alignment = .center
        previewStyleLabel.translatesAutoresizingMaskIntoConstraints = false
        status.translatesAutoresizingMaskIntoConstraints = false
        let labels = NSView()
        labels.translatesAutoresizingMaskIntoConstraints = false
        labels.addSubview(previewStyleLabel)
        labels.addSubview(status)
        NSLayoutConstraint.activate([
            labels.widthAnchor.constraint(equalToConstant: 104),
            labels.heightAnchor.constraint(
                equalToConstant: CGFloat(OrbVisualMetrics.appearancePreviewMaximumDiameter)
            ),
            status.leadingAnchor.constraint(equalTo: labels.leadingAnchor),
            status.topAnchor.constraint(equalTo: labels.topAnchor),
            previewStyleLabel.centerXAnchor.constraint(equalTo: labels.centerXAnchor),
            previewStyleLabel.centerYAnchor.constraint(equalTo: labels.centerYAnchor),
            previewStyleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: labels.leadingAnchor),
            previewStyleLabel.trailingAnchor.constraint(lessThanOrEqualTo: labels.trailingAnchor),
        ])
        let row = NSStackView(views: [labels, NSView(), previewOrb])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        let card = makeCard(body: row, minimumHeight: 76)
        card.widthAnchor.constraint(equalToConstant: 236).isActive = true
        return card
    }

    private func makeSizeCard() -> NSView {
        let unit = NSTextField(labelWithString: "px")
        unit.font = .systemFont(ofSize: 11)
        unit.textColor = AppearancePalette.secondaryText
        let sizeRow = NSStackView(views: [sizeSlider, sizeField, unit])
        sizeRow.orientation = .horizontal
        sizeRow.alignment = .centerY
        sizeRow.spacing = 9
        sizeSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        return makeSectionCard(
            title: "悬浮球大小",
            body: sizeRow
        )
    }

    private func makeColorCard() -> NSView {
        presetButtons = OrbAppearancePresets.all.map { preset in
            let button = ColorPresetButton(name: preset.name, color: NSColor(hex: preset.hex))
            button.target = self
            button.action = #selector(presetSelected(_:))
            return button
        }
        let presetRow = NSStackView(views: presetButtons)
        presetRow.orientation = .horizontal
        presetRow.alignment = .centerY
        presetRow.spacing = 8

        let custom = NSButton(title: "自定义取色", target: self, action: #selector(showColorPicker))
        custom.bezelStyle = .rounded
        custom.font = .systemFont(ofSize: 11.5, weight: .medium)
        custom.toolTip = "打开 TokenOrb 自定义取色器"
        let customRow = NSStackView(views: [custom, colorPreview, hexLabel, NSView()])
        customRow.orientation = .horizontal
        customRow.alignment = .centerY
        customRow.spacing = 10

        let body = NSStackView(views: [presetRow, customRow])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 8
        customRow.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        return makeSectionCard(
            title: "主题颜色",
            body: body
        )
    }

    private func makeTextStyleCard() -> NSView {
        textStyleButtons = OrbTextStyle.allCases.map { style in
            let button = TextStyleOptionButton(style: style)
            button.target = self
            button.action = #selector(textStyleSelected(_:))
            return button
        }
        let row = NSStackView(views: textStyleButtons)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fillEqually
        row.spacing = 8
        return makeSectionCard(
            title: "数字样式",
            body: row
        )
    }

    private func makeFrameRateCard() -> NSView {
        frameRateButtons = OrbVisualMetrics.supportedAnimationFrameRates.map {
            frameRate in
            let button = FrameRateOptionButton(frameRate: frameRate)
            button.target = self
            button.action = #selector(frameRateSelected(_:))
            return button
        }
        let row = NSStackView(views: frameRateButtons)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fillEqually
        row.spacing = 8
        return makeSectionCard(
            title: "动画帧率",
            body: row
        )
    }

    private func makeActionRow() -> NSView {
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelChanges))
        cancel.keyEquivalent = "\u{1b}"
        cancel.bezelStyle = .rounded
        cancel.font = .systemFont(ofSize: 12, weight: .medium)
        let save = NSButton(title: "保存", target: self, action: #selector(saveChanges))
        save.keyEquivalent = "\r"
        save.bezelStyle = .rounded
        save.bezelColor = AppearancePalette.actionFill
        save.contentTintColor = .white
        save.font = .systemFont(ofSize: 12, weight: .semibold)
        [cancel, save].forEach { button in
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(
                    equalToConstant: AppearanceLayout.actionButtonWidth
                ),
                button.heightAnchor.constraint(
                    equalToConstant: AppearanceLayout.actionButtonHeight
                ),
            ])
        }
        let row = NSStackView(views: [NSView(), cancel, save])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func makeSectionCard(title: String, body: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = AppearancePalette.primaryText
        let stack = NSStackView(views: [titleLabel, body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        body.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return makeCard(body: stack)
    }

    private func makeCard(body: NSView, minimumHeight: CGFloat? = nil) -> NSView {
        let card = AppearanceCardView(frame: .zero)
        body.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 15),
            body.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -15),
            body.topAnchor.constraint(equalTo: card.topAnchor, constant: 13),
            body.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -13),
        ])
        if let minimumHeight {
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: minimumHeight).isActive = true
        }
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }

    func controlTextDidChange(_ notification: Notification) {
        guard
            let changedField = notification.object as? NSTextField,
            changedField === sizeField
        else { return }
        guard let value = Double(sizeField.stringValue) else { return }
        sizeSlider.doubleValue = value.clamped(
            to: OrbVisualMetrics.minimumDiameter...OrbVisualMetrics.maximumDiameter
        )
        updatePreview()
    }

    @objc private func sizeChanged(_ sender: NSSlider) {
        let rounded = sender.doubleValue.rounded()
        sender.doubleValue = rounded
        sizeField.stringValue = "\(Int(rounded))"
        updatePreview()
    }

    @objc private func presetSelected(_ sender: ColorPresetButton) {
        pendingColor = sender.presetColor
        updateSelectionsAndPreview()
    }

    @objc private func textStyleSelected(_ sender: TextStyleOptionButton) {
        pendingTextStyle = sender.textStyle
        updateSelectionsAndPreview()
    }

    @objc private func frameRateSelected(_ sender: FrameRateOptionButton) {
        pendingAnimationFrameRate = OrbVisualMetrics.normalizedAnimationFrameRate(
            sender.frameRate
        )
        updateSelectionsAndPreview()
    }

    @objc private func showColorPicker() {
        guard let parent = window else { return }
        let picker = ThemedColorPickerWindowController(initialColor: pendingColor)
        colorPickerController = picker
        picker.onConfirm = { [weak self] color in
            guard let self else { return }
            self.pendingColor = color
            self.updateSelectionsAndPreview()
            self.colorPickerController = nil
        }
        picker.onCancel = { [weak self] in
            self?.colorPickerController = nil
        }
        picker.showSheet(for: parent)
    }

    @objc private func saveChanges() {
        let parsed = Double(sizeField.stringValue) ?? sizeSlider.doubleValue
        settings.orbSize = CGFloat(parsed.clamped(
            to: OrbVisualMetrics.minimumDiameter...OrbVisualMetrics.maximumDiameter
        ).rounded())
        settings.accentColor = pendingColor
        settings.textStyle = pendingTextStyle
        settings.animationFrameRate = pendingAnimationFrameRate
        previewOrb.setAnimating(false)
        window?.orderOut(nil)
        onChange?()
    }

    @objc private func cancelChanges() {
        previewOrb.setAnimating(false)
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        previewOrb.setAnimating(false)
    }

    private func updateSelectionsAndPreview() {
        let hex = pendingColor.hexString
        hexLabel.stringValue = hex
        colorPreview.layer?.backgroundColor = pendingColor.cgColor
        for button in presetButtons {
            button.isPresetSelected = button.presetColor.hexString == hex
        }
        for button in textStyleButtons {
            button.isStyleSelected = button.textStyle == pendingTextStyle
        }
        for button in frameRateButtons {
            button.isFrameRateSelected = button.frameRate == pendingAnimationFrameRate
        }
        updatePreview()
    }

    private func updatePreview() {
        let configuredDiameter = sizeSlider.doubleValue.rounded()
        let previewDiameter = CGFloat(OrbVisualMetrics.appearancePreviewDiameter(
            configuredDiameter: configuredDiameter
        ))
        previewOrbWidthConstraint?.constant = previewDiameter
        previewOrbHeightConstraint?.constant = previewDiameter
        previewOrb.update(
            remainingPercent: 30,
            accentColor: pendingColor,
            textStyle: pendingTextStyle,
            connected: true
        )
        previewOrb.setAnimationFrameRate(pendingAnimationFrameRate)
        previewStyleLabel.stringValue = pendingTextStyle.displayName
        previewOrb.superview?.layoutSubtreeIfNeeded()
    }
}

private final class AppearanceCanvasView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = AppearancePalette.surfaces(
            for: effectiveAppearance
        ).canvas.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private final class AppearanceColorPreviewView: NSView {
    init(cornerRadius: CGFloat) {
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
        layer?.borderColor = AppearancePalette.surfaces(
            for: effectiveAppearance
        ).previewBorder.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private final class AppearanceStatusDotView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 3.5
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = AppearancePalette.success(
            for: effectiveAppearance
        ).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private final class AppearanceCardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.cornerRadius = 15
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let surfaces = AppearancePalette.surfaces(for: effectiveAppearance)
        layer?.backgroundColor = surfaces.card.cgColor
        layer?.borderColor = surfaces.cardBorder.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private final class ColorPresetButton: NSButton {
    let presetColor: NSColor

    var isPresetSelected = false {
        didSet { needsDisplay = true }
    }

    init(name: String, color: NSColor) {
        presetColor = color
        super.init(frame: NSRect(x: 0, y: 0, width: 42, height: 42))
        isBordered = false
        title = ""
        toolTip = "\(name) · \(color.hexString)"
        setAccessibilityLabel(name)
        wantsLayer = true
        layer?.cornerRadius = 21
        layer?.shadowRadius = 4
        layer?.shadowOffset = .zero
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 42),
            heightAnchor.constraint(equalToConstant: 42),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let surfaces = AppearancePalette.surfaces(for: effectiveAppearance)
        layer?.backgroundColor = presetColor.cgColor
        layer?.borderWidth = isPresetSelected ? 3 : 1
        layer?.borderColor = (
            isPresetSelected
                ? AppearancePalette.accent(for: effectiveAppearance)
                : surfaces.swatchBorder
        ).cgColor
        layer?.shadowColor = surfaces.shadow.cgColor
        layer?.shadowOpacity = isPresetSelected ? 0.20 : 0
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private final class FrameRateOptionButton: NSButton {
    let frameRate: Int

    var isFrameRateSelected = false {
        didSet { needsDisplay = true }
    }

    init(frameRate: Int) {
        self.frameRate = frameRate
        super.init(frame: .zero)
        isBordered = false
        title = "\(frameRate) FPS"
        font = .systemFont(ofSize: 10.5, weight: .semibold)
        contentTintColor = AppearancePalette.primaryText
        wantsLayer = true
        layer?.cornerRadius = 11
        setAccessibilityLabel("\(frameRate) FPS")
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 40).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let surfaces = AppearancePalette.surfaces(for: effectiveAppearance)
        layer?.backgroundColor = (
            isFrameRateSelected ? surfaces.selectedOption : surfaces.option
        ).cgColor
        layer?.borderColor = (
            isFrameRateSelected
                ? AppearancePalette.accent(for: effectiveAppearance)
                : surfaces.optionBorder
        ).cgColor
        layer?.borderWidth = isFrameRateSelected ? 2 : 1
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private final class TextStyleOptionButton: NSButton {
    let textStyle: OrbTextStyle

    var isStyleSelected = false {
        didSet { needsDisplay = true }
    }

    init(style: OrbTextStyle) {
        textStyle = style
        super.init(frame: .zero)
        isBordered = false
        title = ""
        wantsLayer = true
        layer?.cornerRadius = 12
        setAccessibilityLabel("数字样式 \(style.displayName)")

        let sample = QuotaTextSampleView(style: style)
        let label = NSTextField(labelWithString: style.displayName)
        label.font = .systemFont(ofSize: 10.5)
        label.textColor = AppearancePalette.primaryText
        label.alignment = .center
        let stack = NSStackView(views: [sample, label])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            sample.heightAnchor.constraint(equalToConstant: 36),
            heightAnchor.constraint(equalToConstant: 76),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let surfaces = AppearancePalette.surfaces(for: effectiveAppearance)
        layer?.backgroundColor = (
            isStyleSelected ? surfaces.selectedOption : surfaces.option
        ).cgColor
        layer?.borderColor = (
            isStyleSelected
                ? AppearancePalette.accent(for: effectiveAppearance)
                : surfaces.optionBorder
        ).cgColor
        layer?.borderWidth = isStyleSelected ? 2 : 1
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private final class QuotaTextSampleView: NSView {
    private let textStyle: OrbTextStyle

    init(style: OrbTextStyle) {
        textStyle = style
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 48, height: 36) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let fontSize: CGFloat = textStyle == .emphasis ? 24 : 20
        let color = AppearancePalette.primaryText
        let result: NSAttributedString
        if textStyle == .emphasis {
            let value = NSMutableAttributedString(
                string: "30",
                attributes: [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .black),
                    .foregroundColor: color,
                ]
            )
            value.append(NSAttributedString(
                string: "%",
                attributes: [
                    .font: NSFont.systemFont(ofSize: fontSize * 0.48, weight: .bold),
                    .foregroundColor: color,
                    .baselineOffset: fontSize * 0.22,
                ]
            ))
            result = value
        } else {
            let value = NSMutableAttributedString(
                string: "30%",
                attributes: [
                    .font: Self.font(size: fontSize, style: textStyle),
                    .foregroundColor: color,
                ]
            )
            let percentScale: CGFloat
            switch textStyle {
            case .geometric: percentScale = 0.73
            case .condensed: percentScale = 0.69
            case .rounded: percentScale = 0.78
            case .minimal, .emphasis: percentScale = 1
            }
            if percentScale < 1 {
                value.addAttribute(
                    .font,
                    value: Self.font(size: fontSize * percentScale, style: textStyle),
                    range: NSRange(location: 2, length: 1)
                )
            }
            result = value
        }
        let size = result.size()
        result.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private static func font(size: CGFloat, style: OrbTextStyle) -> NSFont {
        switch style {
        case .geometric:
            return NSFont(name: "Avenir Next Demi Bold", size: size)
                ?? .systemFont(ofSize: size, weight: .semibold)
        case .condensed:
            return NSFont(name: "Avenir Next Condensed Demi Bold", size: size)
                ?? .systemFont(ofSize: size, weight: .semibold)
        case .rounded:
            return NSFont(name: "Arial Rounded MT Bold", size: size)
                ?? .systemFont(ofSize: size, weight: .bold)
        case .minimal, .emphasis:
            return .systemFont(ofSize: size, weight: .bold)
        }
    }
}

private final class ThemedColorPickerWindowController: NSWindowController, NSTextFieldDelegate {
    private let spectrum = ColorSpectrumView(frame: .zero)
    private let hueStrip = HueStripView(frame: .zero)
    private let preview = AppearanceColorPreviewView(cornerRadius: 13)
    private let hexField = NSTextField(string: "")
    private let redField = NSTextField(string: "")
    private let greenField = NSTextField(string: "")
    private let blueField = NSTextField(string: "")
    private var selectedColor: NSColor
    private var syncing = false

    var onConfirm: ((NSColor) -> Void)?
    var onCancel: (() -> Void)?

    init(initialColor: NSColor) {
        selectedColor = initialColor.sRGB
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 500),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = "自定义取色"
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = AppearancePalette.canvas
        panel.titlebarAppearsTransparent = true
        panel.contentView = AppearanceCanvasView(frame: panel.contentView?.frame ?? .zero)
        super.init(window: panel)
        buildContent()
        setSelectedColor(selectedColor)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showSheet(for parent: NSWindow) {
        guard let window else { return }
        parent.beginSheet(window)
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }

        let title = NSTextField(labelWithString: "自定义取色")
        title.font = .systemFont(ofSize: 20, weight: .bold)
        title.textColor = AppearancePalette.primaryText
        let subtitle = NSTextField(labelWithString: "拖动色面与色相条，或直接输入颜色值")
        subtitle.font = .systemFont(ofSize: 10.5)
        subtitle.textColor = AppearancePalette.secondaryText
        let header = NSStackView(views: [title, subtitle])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 4

        spectrum.translatesAutoresizingMaskIntoConstraints = false
        hueStrip.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            spectrum.heightAnchor.constraint(equalToConstant: 190),
            hueStrip.heightAnchor.constraint(equalToConstant: 20),
        ])
        spectrum.onChange = { [weak self] color in
            guard let self, !self.syncing else { return }
            self.selectedColor = color
            self.syncFields()
        }
        hueStrip.onChange = { [weak self] hue in
            guard let self, !self.syncing else { return }
            self.spectrum.hue = hue
            self.selectedColor = self.spectrum.selectedColor
            self.syncFields()
        }
        let pickerStack = NSStackView(views: [spectrum, hueStrip])
        pickerStack.orientation = .vertical
        pickerStack.alignment = .leading
        pickerStack.spacing = 10
        spectrum.widthAnchor.constraint(equalTo: pickerStack.widthAnchor).isActive = true
        hueStrip.widthAnchor.constraint(equalTo: pickerStack.widthAnchor).isActive = true
        let pickerCard = makePickerCard(body: pickerStack)

        preview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            preview.widthAnchor.constraint(equalToConstant: 44),
            preview.heightAnchor.constraint(equalToConstant: 44),
        ])

        [hexField, redField, greenField, blueField].forEach {
            $0.delegate = self
            $0.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            $0.alignment = .center
        }
        hexField.translatesAutoresizingMaskIntoConstraints = false
        hexField.widthAnchor.constraint(equalToConstant: 86).isActive = true
        [redField, greenField, blueField].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.widthAnchor.constraint(equalToConstant: 52).isActive = true
        }

        let hexRow = valueRow(label: "HEX", field: hexField)
        let rgbRow = NSStackView(views: [
            valueRow(label: "R", field: redField),
            valueRow(label: "G", field: greenField),
            valueRow(label: "B", field: blueField),
        ])
        rgbRow.orientation = .horizontal
        rgbRow.spacing = 10
        let fields = NSStackView(views: [hexRow, rgbRow])
        fields.orientation = .vertical
        fields.alignment = .leading
        fields.spacing = 8
        let valuesRow = NSStackView(views: [preview, fields, NSView()])
        valuesRow.orientation = .horizontal
        valuesRow.alignment = .centerY
        valuesRow.spacing = 14
        let valuesCard = makePickerCard(body: valuesRow)

        let hint = NSTextField(labelWithString: "支持 HEX 与 RGB")
        hint.font = .systemFont(ofSize: 10.5)
        hint.textColor = AppearancePalette.secondaryText
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelPicker))
        cancel.keyEquivalent = "\u{1b}"
        cancel.bezelStyle = .rounded
        let confirm = NSButton(title: "确认", target: self, action: #selector(confirmPicker))
        confirm.keyEquivalent = "\r"
        confirm.bezelStyle = .rounded
        confirm.bezelColor = AppearancePalette.actionFill
        confirm.contentTintColor = .white
        confirm.font = .systemFont(ofSize: 12, weight: .semibold)
        let actions = NSStackView(views: [hint, NSView(), cancel, confirm])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 10

        let stack = NSStackView(views: [header, pickerCard, valuesCard, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -18),
            pickerCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            valuesCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            actions.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func makePickerCard(body: NSView) -> NSView {
        let card = AppearanceCardView(frame: .zero)
        body.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            body.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            body.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            body.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])
        return card
    }

    private func valueRow(label: String, field: NSTextField) -> NSView {
        let labelField = NSTextField(labelWithString: label)
        labelField.font = .systemFont(ofSize: 10.5, weight: .semibold)
        labelField.textColor = AppearancePalette.secondaryText
        let row = NSStackView(views: [labelField, field])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }

    func controlTextDidChange(_ notification: Notification) {
        guard !syncing else { return }
        if let changedField = notification.object as? NSTextField, changedField === hexField {
            let cleaned = hexField.stringValue
                .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            guard cleaned.count == 6, UInt64(cleaned, radix: 16) != nil else {
                return
            }
            setSelectedColor(NSColor(hex: "#\(cleaned)"))
            return
        }
        guard
            let red = Int(redField.stringValue), (0...255).contains(red),
            let green = Int(greenField.stringValue), (0...255).contains(green),
            let blue = Int(blueField.stringValue), (0...255).contains(blue)
        else { return }
        setSelectedColor(NSColor(
            srgbRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        ))
    }

    @objc private func confirmPicker() {
        finishSheet()
        onConfirm?(selectedColor)
    }

    @objc private func cancelPicker() {
        finishSheet()
        onCancel?()
    }

    private func finishSheet() {
        guard let window else { return }
        window.sheetParent?.endSheet(window)
        window.orderOut(nil)
    }

    private func setSelectedColor(_ color: NSColor) {
        selectedColor = color.sRGB
        let hsv = selectedColor.hsv
        syncing = true
        spectrum.set(hue: hsv.hue, saturation: hsv.saturation, value: hsv.value)
        hueStrip.hue = hsv.hue
        syncing = false
        syncFields()
    }

    private func syncFields() {
        syncing = true
        preview.layer?.backgroundColor = selectedColor.cgColor
        hexField.stringValue = selectedColor.hexString
        let rgb = selectedColor.sRGB
        redField.stringValue = "\(Int((rgb.redComponent * 255).rounded()))"
        greenField.stringValue = "\(Int((rgb.greenComponent * 255).rounded()))"
        blueField.stringValue = "\(Int((rgb.blueComponent * 255).rounded()))"
        syncing = false
    }
}

private final class ColorSpectrumView: NSView {
    var onChange: ((NSColor) -> Void)?
    var hue: CGFloat = 200 {
        didSet { needsDisplay = true }
    }
    private(set) var saturation: CGFloat = 1
    private(set) var value: CGFloat = 1

    var selectedColor: NSColor {
        NSColor(hueDegrees: hue, saturation: saturation, value: value)
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("饱和度和亮度色面")
        toolTip = "点击后使用方向键微调，按住 Shift 加速"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(hue: CGFloat, saturation: CGFloat, value: CGFloat) {
        self.hue = hue.normalizedHue
        self.saturation = saturation.clamped(to: 0...1)
        self.value = value.clamped(to: 0...1)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSColor(hueDegrees: hue, saturation: 1, value: 1).setFill()
        bounds.fill()
        NSGradient(
            starting: .white,
            ending: .white.withAlphaComponent(0)
        )?.draw(in: bounds, angle: 0)
        NSGradient(
            starting: .black.withAlphaComponent(0),
            ending: .black
        )?.draw(in: bounds, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        AppearancePalette.primaryText.withAlphaComponent(0.45).setStroke()
        path.lineWidth = 1
        path.stroke()
        let point = NSPoint(x: saturation * bounds.width, y: (1 - value) * bounds.height)
        let marker = NSBezierPath(ovalIn: NSRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14))
        NSColor.white.setStroke()
        marker.lineWidth = 2
        marker.stroke()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        update(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        update(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 0.05 : 0.01
        switch event.keyCode {
        case 123:
            saturation -= step
        case 124:
            saturation += step
        case 126:
            value += step
        case 125:
            value -= step
        default:
            super.keyDown(with: event)
            return
        }
        saturation = saturation.clamped(to: 0...1)
        value = value.clamped(to: 0...1)
        needsDisplay = true
        onChange?(selectedColor)
    }

    private func update(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        saturation = (point.x / max(1, bounds.width)).clamped(to: 0...1)
        value = (1 - point.y / max(1, bounds.height)).clamped(to: 0...1)
        needsDisplay = true
        onChange?(selectedColor)
    }
}

private final class HueStripView: NSView {
    var onChange: ((CGFloat) -> Void)?
    var hue: CGFloat = 200 {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("色相选择条")
        toolTip = "点击后使用方向键微调，按住 Shift 加速"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSGradient(colors: [
            .red,
            .yellow,
            .green,
            .cyan,
            .blue,
            .magenta,
            .red,
        ])?.draw(in: bounds, angle: 0)
        NSGraphicsContext.restoreGraphicsState()
        let x = hue / 360 * bounds.width
        let markerRect = NSRect(x: x - 7, y: bounds.midY - 7, width: 14, height: 14)
        NSColor(hueDegrees: hue, saturation: 1, value: 1).setFill()
        let marker = NSBezierPath(ovalIn: markerRect)
        marker.fill()
        NSColor.white.setStroke()
        marker.lineWidth = 2
        marker.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        update(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        update(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 123, 125:
            hue = (hue - step).normalizedHue
        case 124, 126:
            hue = (hue + step).normalizedHue
        default:
            super.keyDown(with: event)
            return
        }
        onChange?(hue)
    }

    private func update(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        hue = ((point.x / max(1, bounds.width)).clamped(to: 0...1) * 359.999)
        onChange?(hue)
    }
}

private extension NSColor {
    convenience init(hueDegrees: CGFloat, saturation: CGFloat, value: CGFloat) {
        let rgb = NSColor.hsvToRgb(
            hue: hueDegrees,
            saturation: saturation,
            value: value
        )
        self.init(
            srgbRed: rgb.red,
            green: rgb.green,
            blue: rgb.blue,
            alpha: 1
        )
    }

    var sRGB: NSColor {
        usingColorSpace(.sRGB) ?? self
    }

    var hsv: (hue: CGFloat, saturation: CGFloat, value: CGFloat) {
        let rgb = sRGB
        let red = rgb.redComponent
        let green = rgb.greenComponent
        let blue = rgb.blueComponent
        let maximum = max(red, max(green, blue))
        let minimum = min(red, min(green, blue))
        let delta = maximum - minimum
        let hue: CGFloat
        if delta < 0.000_001 {
            hue = 0
        } else if maximum == red {
            hue = (60 * ((green - blue) / delta).truncatingRemainder(dividingBy: 6)).normalizedHue
        } else if maximum == green {
            hue = 60 * ((blue - red) / delta + 2)
        } else {
            hue = 60 * ((red - green) / delta + 4)
        }
        return (
            hue.normalizedHue,
            maximum < 0.000_001 ? 0 : delta / maximum,
            maximum
        )
    }

    private static func hsvToRgb(
        hue: CGFloat,
        saturation: CGFloat,
        value: CGFloat
    ) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let safeHue = hue.normalizedHue
        let safeSaturation = saturation.clamped(to: 0...1)
        let safeValue = value.clamped(to: 0...1)
        let chroma = safeValue * safeSaturation
        let segment = safeHue / 60
        let x = chroma * (1 - abs(segment.truncatingRemainder(dividingBy: 2) - 1))
        let values: (CGFloat, CGFloat, CGFloat)
        switch segment {
        case 0..<1: values = (chroma, x, 0)
        case 1..<2: values = (x, chroma, 0)
        case 2..<3: values = (0, chroma, x)
        case 3..<4: values = (0, x, chroma)
        case 4..<5: values = (x, 0, chroma)
        default: values = (chroma, 0, x)
        }
        let offset = safeValue - chroma
        return (values.0 + offset, values.1 + offset, values.2 + offset)
    }
}

private extension CGFloat {
    var normalizedHue: CGFloat {
        guard isFinite else { return 0 }
        let result = truncatingRemainder(dividingBy: 360)
        return result < 0 ? result + 360 : result
    }

}
