import AppKit
import TokenOrbCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum MenuTag: Int {
        case toggleOrb = 101
        case followCodex = 102
    }

    private let settings = AppSettings.shared
    private let client = CodexAppServerClient()
    private let localReader = LocalSnapshotReader()
    private let authTracker = AuthStateTracker()
    private let processMonitor = CodexProcessMonitor()
    private lazy var orbController = OrbPanelController(settings: settings)
    private lazy var detailController = DetailWindowController()
    private lazy var appearanceController = AppearanceWindowController(settings: settings)

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var processTimer: Timer?
    private var refreshTimer: Timer?
    private var authTimer: Timer?
    private var retryTimer: Timer?
    private var snapshot: QuotaSnapshot?
    private var liveSnapshot: QuotaSnapshot?
    private var localSnapshotNotBefore: Date?
    private var statusText = "正在准备…"
    private var connected = false
    private var clientActive = false
    private let demoMode = CommandLine.arguments.contains("--demo")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configureControllers()

        if demoMode {
            snapshot = .demo()
            statusText = "演示数据"
            connected = true
            settings.orbVisible = true
            updatePresentation()
            return
        }

        _ = processMonitor.poll()
        settings.updateLoginItem(enabled: settings.followCodex)
        evaluateRuntimeState()
        startTimers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        processTimer?.invalidate()
        refreshTimer?.invalidate()
        authTimer?.invalidate()
        retryTimer?.invalidate()
        client.stopAndWait()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateMenuState(menu)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.imagePosition = .imageLeading
        item.button?.toolTip = "Token Orb"

        let menu = makeMenu()
        menu.delegate = self
        statusMenu = menu
        item.menu = menu
        updateStatusItem()
    }

    private func configureControllers() {
        orbController.onClick = { [weak self] in
            self?.showDetails()
        }
        orbController.menuProvider = { [weak self] in
            self?.makeMenu()
        }
        appearanceController.onChange = { [weak self] in
            self?.orbController.applyAppearance()
            self?.updatePresentation()
        }

        client.onSnapshot = { [weak self] update, sparse in
            guard let self else { return }
            self.liveSnapshot = sparse && self.liveSnapshot != nil
                ? self.liveSnapshot?.merged(with: update)
                : update
            self.snapshot = self.liveSnapshot
            self.localSnapshotNotBefore = nil
            self.connected = true
            self.statusText = "实时同步中"
            self.retryTimer?.invalidate()
            self.updatePresentation()
        }
        client.onStatus = { [weak self] text, connected in
            guard let self else { return }
            self.statusText = text
            self.connected = connected
            if !connected {
                self.loadLocalFallback()
                self.scheduleRetry()
            }
            self.updatePresentation()
        }
    }

    private func startTimers() {
        processTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.processMonitor.poll() {
                self.evaluateRuntimeState()
            }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.client.refresh()
        }
        authTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.authTracker.pollForChange() else { return }
            self.snapshot = nil
            self.liveSnapshot = nil
            self.localSnapshotNotBefore = Date()
            self.connected = false
            self.statusText = "检测到 Codex 账号变化，正在刷新额度…"
            self.updatePresentation()
            if self.clientActive {
                self.client.restart()
            }
        }
    }

    private func evaluateRuntimeState() {
        let shouldRun = !settings.followCodex || processMonitor.isRunning
        if shouldRun, !clientActive {
            clientActive = true
            statusText = "正在准备 Codex 实时接口…"
            connected = false
            client.start()
            loadLocalFallback()
        } else if !shouldRun, clientActive {
            clientActive = false
            connected = false
            statusText = "等待 Codex 启动"
            client.stop()
        }
        updatePresentation()
    }

    private func loadLocalFallback() {
        let reader = localReader
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let local = reader.latest()
            DispatchQueue.main.async {
                guard
                    let self,
                    !self.connected,
                    let local,
                    self.localSnapshotNotBefore.map({ local.capturedAt >= $0 }) ?? true,
                    self.snapshot == nil || local.capturedAt > self.snapshot!.capturedAt
                else {
                    return
                }
                self.snapshot = local
                if self.statusText.isEmpty || self.statusText == "正在准备…" {
                    self.statusText = "使用本地会话快照"
                }
                self.updatePresentation()
            }
        }
    }

    private func scheduleRetry() {
        guard clientActive, retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.retryTimer = nil
            if self.clientActive, !self.connected {
                self.client.restart()
            }
        }
    }

    private func updatePresentation() {
        orbController.update(snapshot: snapshot, connected: connected)
        detailController.update(snapshot: snapshot, status: statusText, connected: connected)
        applyOrbVisibility()
        updateStatusItem()
        if let statusMenu {
            updateMenuState(statusMenu)
        }
    }

    private func applyOrbVisibility() {
        let runtimeAllowsOrb = demoMode || !settings.followCodex || processMonitor.isRunning
        if settings.orbVisible && runtimeAllowsOrb {
            orbController.show()
        } else {
            orbController.hide()
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let percent = snapshot?.mostRestrictiveWindow?.remainingPercent
        button.title = percent.map { " \(Int($0.rounded()))%" } ?? " —"
        button.image = statusImage(color: settings.accentColor, connected: connected)
        button.contentTintColor = nil
        button.toolTip = "Token Orb · \(statusText)"
    }

    private func statusImage(color: NSColor, connected: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let ring = rect.insetBy(dx: 2.5, dy: 2.5)
            let path = NSBezierPath(ovalIn: ring)
            path.lineWidth = 2.5
            color.setStroke()
            path.stroke()
            (connected ? color : NSColor.systemOrange).setFill()
            NSBezierPath(
                ovalIn: NSRect(x: rect.maxX - 6, y: rect.maxY - 6, width: 4, height: 4)
            ).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Token Orb")
        menu.delegate = self
        menu.addItem(item("查看详细额度", action: #selector(showDetails)))
        menu.addItem(item("立即刷新", action: #selector(refreshNow)))
        menu.addItem(item("外观…", action: #selector(showAppearance)))
        menu.addItem(.separator())

        let toggleOrb = item("显示悬浮球", action: #selector(toggleOrb))
        toggleOrb.tag = MenuTag.toggleOrb.rawValue
        menu.addItem(toggleOrb)

        let follow = item("跟随 Codex 启动/关闭", action: #selector(toggleFollowCodex))
        follow.tag = MenuTag.followCodex.rawValue
        menu.addItem(follow)

        menu.addItem(.separator())
        menu.addItem(item("关于 Token Orb", action: #selector(showAbout)))
        menu.addItem(item("退出", action: #selector(quit)))
        updateMenuState(menu)
        return menu
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func updateMenuState(_ menu: NSMenu) {
        menu.item(withTag: MenuTag.toggleOrb.rawValue)?.state = settings.orbVisible ? .on : .off
        menu.item(withTag: MenuTag.followCodex.rawValue)?.state = settings.followCodex ? .on : .off
    }

    @objc private func showDetails() {
        detailController.show(relativeTo: orbController.panel.frame)
    }

    @objc private func refreshNow() {
        guard !demoMode else {
            snapshot = .demo()
            updatePresentation()
            return
        }
        snapshot = nil
        liveSnapshot = nil
        connected = false
        statusText = "正在刷新实时额度…"
        updatePresentation()
        if clientActive {
            client.restart()
        } else {
            evaluateRuntimeState()
        }
    }

    @objc private func showAppearance() {
        appearanceController.show()
    }

    @objc private func toggleOrb() {
        settings.orbVisible.toggle()
        applyOrbVisibility()
        if let statusMenu {
            updateMenuState(statusMenu)
        }
    }

    @objc private func toggleFollowCodex() {
        settings.followCodex.toggle()
        _ = processMonitor.poll()
        evaluateRuntimeState()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Token Orb v1.3.2"
        alert.informativeText = """
        macOS 原生版本

        实时监控 Codex 剩余额度，并支持悬浮球、菜单栏、外观设置和跟随 Codex 启动/关闭。

        Copyright © chenxulin
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
