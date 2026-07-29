import AppKit
import TokenOrbCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum MenuTag: Int {
        case toggleOrb = 101
        case followCodex = 102
        case showDetails = 103
        case refreshNow = 104
        case runtimeStatus = 105
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
    private var refreshTimer: Timer?
    private var authTimer: Timer?
    private var processRetryTimer: Timer?
    private var localWatchTimer: Timer?
    private var localPollTimer: Timer?
    private var localDebounceTimer: Timer?
    private var presentationTimer: Timer?
    private var codexExitTimer: Timer?
    private var watcherLaunchValidationTimer: Timer?

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
    private let launchedByWatcher = CommandLine.arguments.contains(
        AppIdentity.watcherLaunchArgument
    )

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

        processMonitor.onStateChanged = { [weak self] wasRunning, isRunning, source in
            self?.handleCodexStateChange(
                wasRunning: wasRunning,
                isRunning: isRunning,
                source: source
            )
        }
        processMonitor.start()
        do {
            let result = try settings.updateLoginItem(enabled: settings.followCodex)
            if result == .requiresApproval {
                showLoginItemApprovalAlert()
            }
        } catch {
            AppLogger.shared.error(error)
            showFollowCodexError(error)
        }
        evaluateRuntimeState()
        scheduleWatcherLaunchValidationIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        [
            refreshTimer,
            authTimer,
            processRetryTimer,
            localWatchTimer,
            localPollTimer,
            localDebounceTimer,
            presentationTimer,
            codexExitTimer,
            watcherLaunchValidationTimer,
        ].forEach { $0?.invalidate() }
        processMonitor.stop()
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
        item.button?.toolTip = AppIdentity.productName

        let menu = makeMenu(includeAbout: true)
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
            guard let self else { return nil }
            self.detailController.hide()
            return self.makeMenu(includeAbout: false)
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

    private func handleCodexStateChange(
        wasRunning: Bool,
        isRunning: Bool,
        source: String
    ) {
        if OrbRuntimePolicy.shouldResetManualHide(
            followCodex: settings.followCodex,
            wasCodexRunning: wasRunning,
            codexRunning: isRunning
        ) {
            manuallyHidden = false
        }
        if isRunning {
            codexExitTimer?.invalidate()
            codexExitTimer = nil
            watcherLaunchValidationTimer?.invalidate()
            watcherLaunchValidationTimer = nil
        }
        evaluateRuntimeState()

        if settings.followCodex, wasRunning, !isRunning {
            scheduleCodexExitConfirmation(source: source)
        }
    }

    private func scheduleCodexExitConfirmation(source: String) {
        codexExitTimer?.invalidate()
        let timer = Timer(timeInterval: 2, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.codexExitTimer = nil
            _ = self.processMonitor.poll(source: "Codex-exit-confirmation")
            guard self.settings.followCodex, !self.processMonitor.isRunning else { return }
            AppLogger.shared.lifecycle(
                operation: "主应用随 Codex 退出",
                details: "source=\(source)"
            )
            NSApp.terminate(nil)
        }
        codexExitTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func scheduleWatcherLaunchValidationIfNeeded() {
        guard launchedByWatcher, settings.followCodex, !processMonitor.isRunning else { return }
        watcherLaunchValidationTimer?.invalidate()
        let timer = Timer(timeInterval: 6, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.watcherLaunchValidationTimer = nil
            _ = self.processMonitor.poll(source: "watcher-launch-grace")
            guard self.settings.followCodex, !self.processMonitor.isRunning else { return }
            AppLogger.shared.lifecycle(
                operation: "Watcher 启动校验失败",
                details: "Codex remained undetected after the launch grace period"
            )
            NSApp.terminate(nil)
        }
        watcherLaunchValidationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
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
            connected: connected
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
            connected: connected
        )
        statusItem?.button?.toolTip = "\(AppIdentity.productName) · \(statusText)"
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

    private func updateStatusItem() {
        // Keep diagnostics and the follow toggle reachable while waiting.
        statusItem?.isVisible = true
        guard let button = statusItem?.button else { return }
        let percent = snapshot?.orbDisplayWindow?.remainingPercent
        button.title = percent.map { " \(QuotaFormatting.roundedPercent($0))%" }
            ?? (settings.followCodex && !processMonitor.isRunning ? " 等待 Codex" : " —")
        button.image = statusImage(color: settings.accentColor, connected: connected)
        button.contentTintColor = nil
        button.toolTip = "\(AppIdentity.productName) · \(statusText)"
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

    private func makeMenu(includeAbout: Bool) -> NSMenu {
        let menu = NSMenu(title: AppIdentity.productName)
        menu.delegate = self
        let runtimeStatus = NSMenuItem(
            title: "状态：\(statusText)",
            action: nil,
            keyEquivalent: ""
        )
        runtimeStatus.tag = MenuTag.runtimeStatus.rawValue
        runtimeStatus.isEnabled = false
        menu.addItem(runtimeStatus)
        menu.addItem(.separator())
        let details = item("查看额度", action: #selector(showDetails))
        details.tag = MenuTag.showDetails.rawValue
        menu.addItem(details)
        let refresh = item("立即刷新", action: #selector(refreshNow))
        refresh.tag = MenuTag.refreshNow.rawValue
        menu.addItem(refresh)
        menu.addItem(item("个性化外观", action: #selector(showAppearance)))

        let toggleOrb = item("显示悬浮球", action: #selector(toggleOrb))
        toggleOrb.tag = MenuTag.toggleOrb.rawValue
        menu.addItem(toggleOrb)

        if includeAbout {
            let follow = item("跟随 Codex 启动/退出", action: #selector(toggleFollowCodex))
            follow.tag = MenuTag.followCodex.rawValue
            menu.addItem(follow)
            menu.addItem(item("打开诊断日志", action: #selector(openDiagnosticLogs)))
            menu.addItem(item("关于", action: #selector(showAbout)))
        }
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
        let orbVisible = runtimeAllowsOrb && !manuallyHidden
        menu.item(withTag: MenuTag.runtimeStatus.rawValue)?.title = "状态：\(statusText)"
        menu.item(withTag: MenuTag.toggleOrb.rawValue)?.state = orbVisible ? .on : .off
        menu.item(withTag: MenuTag.toggleOrb.rawValue)?.isEnabled = runtimeAllowsOrb
        menu.item(withTag: MenuTag.showDetails.rawValue)?.isEnabled = orbVisible
        menu.item(withTag: MenuTag.refreshNow.rawValue)?.isEnabled = orbVisible
        let followItem = menu.item(withTag: MenuTag.followCodex.rawValue)
        followItem?.state = demoMode ? .off : (settings.followCodex ? .on : .off)
        followItem?.isEnabled = !demoMode
    }

    @objc private func showDetails() {
        guard orbController.isVisible else { return }
        appearanceController.hide()
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
        detailController.hide()
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
        guard !demoMode else { return }
        let enabled = !settings.followCodex
        do {
            let result = try settings.setFollowCodex(enabled)
            if result == .requiresApproval {
                showLoginItemApprovalAlert()
            }
        } catch {
            AppLogger.shared.error(error)
            showFollowCodexError(error)
            return
        }
        codexExitTimer?.invalidate()
        codexExitTimer = nil
        watcherLaunchValidationTimer?.invalidate()
        watcherLaunchValidationTimer = nil
        _ = processMonitor.poll(source: "follow-setting-change")
        if settings.followCodex, !processMonitor.isRunning {
            manuallyHidden = false
        }
        evaluateRuntimeState()
    }

    @objc private func showAbout() {
        aboutController.show()
    }

    @objc private func openDiagnosticLogs() {
        AppLogger.shared.prepareDirectory()
        NSWorkspace.shared.open(AppLogger.shared.directoryURL)
    }

    private func showFollowCodexError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法更新 Codex 跟随设置"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }

    private func showLoginItemApprovalAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "需要允许 \(AppIdentity.productName) 在后台运行"
        alert.informativeText = "请在系统设置的登录项中允许 \(AppIdentity.productName)。轻量 watcher 会等待 Codex，并只在 Codex 运行时启动主应用。"
        alert.addButton(withTitle: "打开登录项设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            settings.openLoginItemSettings()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
