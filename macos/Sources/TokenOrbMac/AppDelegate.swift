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
    private lazy var aboutController = AboutWindowController()

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var processTimer: Timer?
    private var refreshTimer: Timer?
    private var authTimer: Timer?
    private var processRetryTimer: Timer?
    private var localWatchTimer: Timer?
    private var localPollTimer: Timer?
    private var localDebounceTimer: Timer?
    private var presentationTimer: Timer?

    private var snapshot: QuotaSnapshot?
    private var liveSnapshot: QuotaSnapshot?
    private var localSnapshotNotBefore: Date?
    private var localFallbackActive = false
    private var statusText = "正在准备…"
    private var connected = false
    private var clientActive = false
    private var manuallyHidden = false
    private var serviceGeneration = 0
    private var minimumClientGeneration = 0
    private var lastLocalFingerprint: LocalSessionsFingerprint?
    private var localFingerprintCheckInFlight = false
    private let demoMode = CommandLine.arguments.contains("--demo")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configureControllers()
        startTimers()

        if demoMode {
            snapshot = .demo()
            statusText = "演示数据"
            connected = true
            updatePresentation()
            return
        }

        _ = processMonitor.poll()
        settings.updateLoginItem(enabled: settings.followCodex)
        evaluateRuntimeState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        [
            processTimer,
            refreshTimer,
            authTimer,
            processRetryTimer,
            localWatchTimer,
            localPollTimer,
            localDebounceTimer,
            presentationTimer,
        ].forEach { $0?.invalidate() }
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

        client.onSnapshot = { [weak self] update, sparse, generation in
            guard
                let self,
                self.clientActive,
                AccountSwitchQuotaPolicy.canUseClientGeneration(
                    generation,
                    minimum: self.minimumClientGeneration
                )
            else { return }
            self.liveSnapshot = sparse && self.liveSnapshot != nil
                ? self.liveSnapshot?.merged(with: update)
                : update
            self.snapshot = self.liveSnapshot
            self.localSnapshotNotBefore = nil
            self.localFallbackActive = false
            self.connected = true
            self.statusText = "实时同步中"
            self.updatePresentation()
        }
        client.onStatus = { [weak self] text, connected, generation, useLocalFallback in
            guard
                let self,
                self.clientActive,
                AccountSwitchQuotaPolicy.canUseClientGeneration(
                    generation,
                    minimum: self.minimumClientGeneration
                )
            else { return }
            self.statusText = text
            self.connected = connected
            self.localFallbackActive = LocalFallbackStatePolicy.resolve(
                connected: connected,
                currentlyActive: self.localFallbackActive,
                fallbackRequested: useLocalFallback
            )
            if !connected, self.localFallbackActive {
                self.loadLocalFallback()
            }
            self.updatePresentation()
        }
        client.onDiagnostic = { operation, details in
            AppLogger.shared.realtime(operation: operation, details: details)
        }
    }

    private func startTimers() {
        presentationTimer = commonTimer(interval: 1) { [weak self] in
            self?.refreshTimePresentation()
        }
        guard !demoMode else { return }

        processTimer = commonTimer(interval: 2) { [weak self] in
            guard let self else { return }
            let wasRunning = self.processMonitor.isRunning
            guard self.processMonitor.poll() else { return }
            if OrbRuntimePolicy.shouldResetManualHide(
                followCodex: self.settings.followCodex,
                wasCodexRunning: wasRunning,
                codexRunning: self.processMonitor.isRunning
            ) {
                // Manual hiding is scoped to one Codex session on Windows.
                self.manuallyHidden = false
            }
            self.evaluateRuntimeState()
        }
        refreshTimer = commonTimer(interval: 20) { [weak self] in
            guard let self, self.clientActive else { return }
            if !self.client.isRecovering {
                self.client.refresh()
            }
        }
        authTimer = commonTimer(interval: 1) { [weak self] in
            self?.pollAuthState()
        }
        processRetryTimer = commonTimer(interval: 120) { [weak self] in
            guard let self, self.clientActive else { return }
            if (!self.client.isRunning || !self.client.isInitialized)
                && !self.client.isRecovering
            {
                self.minimumClientGeneration = self.client.currentGeneration + 1
                self.client.restart()
            }
        }
        localWatchTimer = commonTimer(interval: 1) { [weak self] in
            self?.pollLocalFingerprint()
        }
        localPollTimer = commonTimer(interval: 60) { [weak self] in
            guard let self, self.clientActive, self.localFallbackActive else { return }
            self.loadLocalFallback()
        }
    }

    private func commonTimer(interval: TimeInterval, action: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in action() }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func evaluateRuntimeState() {
        let runtimeAllowsOrb = OrbRuntimePolicy.runtimeAllowsOrb(
            followCodex: settings.followCodex,
            codexRunning: processMonitor.isRunning
        )
        let shouldRun = OrbRuntimePolicy.shouldRunService(
            followCodex: settings.followCodex,
            codexRunning: processMonitor.isRunning,
            manuallyHidden: manuallyHidden
        )
        if shouldRun {
            startServiceIfNeeded()
        } else {
            let text = runtimeAllowsOrb ? "悬浮球已隐藏" : "等待 Codex 启动"
            stopServiceIfNeeded(status: text)
        }
        updatePresentation()
    }

    private func startServiceIfNeeded() {
        guard !clientActive else { return }
        serviceGeneration += 1
        clientActive = true
        minimumClientGeneration = client.currentGeneration + 1
        connected = false
        localFallbackActive = false
        statusText = "正在准备 Codex 实时接口…"
        lastLocalFingerprint = nil
        client.restart()
        pollLocalFingerprint()
    }

    private func stopServiceIfNeeded(status: String) {
        detailController.hide()
        localDebounceTimer?.invalidate()
        localDebounceTimer = nil
        serviceGeneration += 1
        if clientActive {
            clientActive = false
            minimumClientGeneration = client.currentGeneration + 1
            client.stop()
        }
        connected = false
        localFallbackActive = false
        liveSnapshot = nil
        snapshot = nil
        localSnapshotNotBefore = nil
        statusText = status
    }

    private func pollAuthState() {
        guard clientActive, authTracker.pollForChange() else { return }
        serviceGeneration += 1
        snapshot = nil
        liveSnapshot = nil
        localSnapshotNotBefore = Date()
        localFallbackActive = false
        connected = false
        statusText = "检测到 Codex 账号变化，正在刷新额度…"
        minimumClientGeneration = client.currentGeneration + 1
        updatePresentation()
        client.restart()
    }

    private func pollLocalFingerprint() {
        guard clientActive, !localFingerprintCheckInFlight else { return }
        localFingerprintCheckInFlight = true
        let reader = localReader
        let generation = serviceGeneration
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let fingerprint = reader.fingerprint()
            DispatchQueue.main.async {
                guard let self else { return }
                self.localFingerprintCheckInFlight = false
                guard self.clientActive, self.serviceGeneration == generation else { return }
                defer { self.lastLocalFingerprint = fingerprint }
                guard
                    let previous = self.lastLocalFingerprint,
                    previous != fingerprint,
                    self.localFallbackActive
                else { return }
                self.scheduleLocalRefresh()
            }
        }
    }

    private func scheduleLocalRefresh() {
        localDebounceTimer?.invalidate()
        let timer = Timer(timeInterval: 0.650, repeats: false) { [weak self] _ in
            self?.localDebounceTimer = nil
            self?.loadLocalFallback()
        }
        localDebounceTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func loadLocalFallback() {
        guard clientActive, localFallbackActive else { return }
        let reader = localReader
        let generation = serviceGeneration
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let local = reader.latest()
            DispatchQueue.main.async {
                guard
                    let self,
                    self.clientActive,
                    self.serviceGeneration == generation,
                    !self.connected,
                    self.localFallbackActive
                else { return }

                guard let local else {
                    if self.snapshot == nil {
                        self.statusText = "等待 Codex 产生额度数据…"
                        self.updatePresentation()
                    }
                    return
                }
                guard AccountSwitchQuotaPolicy.canUseLocalSnapshot(
                    local,
                    capturedNotBefore: self.localSnapshotNotBefore
                ) else {
                    return
                }
                let changed = self.snapshot == nil
                    || self.snapshot?.isLive == true
                    || local.capturedAt > self.snapshot!.capturedAt
                guard changed else { return }
                self.snapshot = local
                self.updatePresentation()
            }
        }
    }

    private func updatePresentation() {
        orbController.update(
            snapshot: snapshot,
            connected: connected,
            toolTip: orbToolTip()
        )
        detailController.update(snapshot: snapshot, status: statusText, connected: connected)
        applyOrbVisibility()
        updateStatusItem()
        if let statusMenu {
            updateMenuState(statusMenu)
        }
    }

    private func refreshTimePresentation() {
        detailController.refreshTimeLabels()
        orbController.update(
            snapshot: snapshot,
            connected: connected,
            toolTip: orbToolTip()
        )
        statusItem?.button?.toolTip = "Token Orb · \(statusText)"
    }

    private func applyOrbVisibility() {
        let runtimeAllowsOrb = demoMode || OrbRuntimePolicy.runtimeAllowsOrb(
            followCodex: settings.followCodex,
            codexRunning: processMonitor.isRunning
        )
        if runtimeAllowsOrb && !manuallyHidden {
            orbController.show()
        } else {
            detailController.hide()
            orbController.hide()
        }
    }

    private func orbToolTip() -> String {
        guard let limiting = snapshot?.mostRestrictiveWindow else {
            return "\(statusText)\n点击查看详情，右键打开菜单"
        }
        return "Codex \(QuotaFormatting.windowName(limiting))剩余 "
            + "\(QuotaFormatting.roundedPercent(limiting.remainingPercent))%\n"
            + "\(QuotaFormatting.resetText(limiting))\n"
            + "\(statusText) · 点击查看详情"
    }

    private func updateStatusItem() {
        statusItem?.isVisible = demoMode || OrbRuntimePolicy.runtimeAllowsOrb(
            followCodex: settings.followCodex,
            codexRunning: processMonitor.isRunning
        )
        guard let button = statusItem?.button else { return }
        let percent = snapshot?.mostRestrictiveWindow?.remainingPercent
        button.title = percent.map { " \(QuotaFormatting.roundedPercent($0))%" } ?? " —"
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
        let runtimeAllowsOrb = demoMode || OrbRuntimePolicy.runtimeAllowsOrb(
            followCodex: settings.followCodex,
            codexRunning: processMonitor.isRunning
        )
        menu.item(withTag: MenuTag.toggleOrb.rawValue)?.state = (
            runtimeAllowsOrb && !manuallyHidden
        ) ? .on : .off
        menu.item(withTag: MenuTag.followCodex.rawValue)?.state = settings.followCodex ? .on : .off
    }

    @objc private func showDetails() {
        guard orbController.isVisible else { return }
        detailController.toggle(relativeTo: orbController.orbFrame)
    }

    @objc private func refreshNow() {
        if demoMode {
            snapshot = .demo()
            statusText = "演示数据"
            connected = true
            updatePresentation()
            return
        }
        guard !manuallyHidden else { return }
        liveSnapshot = nil
        localFallbackActive = false
        connected = false
        statusText = "正在刷新实时额度…"
        updatePresentation()
        if clientActive {
            minimumClientGeneration = client.currentGeneration + 1
            client.restart()
        } else {
            evaluateRuntimeState()
        }
    }

    @objc private func showAppearance() {
        appearanceController.show()
    }

    @objc private func toggleOrb() {
        manuallyHidden.toggle()
        if demoMode {
            if manuallyHidden {
                detailController.hide()
            } else {
                snapshot = .demo()
                statusText = "演示数据"
                connected = true
            }
            updatePresentation()
            return
        }
        evaluateRuntimeState()
    }

    @objc private func toggleFollowCodex() {
        settings.followCodex.toggle()
        _ = processMonitor.poll()
        if settings.followCodex, !processMonitor.isRunning {
            manuallyHidden = false
        }
        evaluateRuntimeState()
    }

    @objc private func showAbout() {
        aboutController.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
