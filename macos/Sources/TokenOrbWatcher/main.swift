import AppKit
import Foundation
import ServiceManagement
import TokenOrbCore

private enum WatcherMenuTag: Int {
    case status = 201
    case open = 202
    case refresh = 203
}

private final class WatcherDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let workspace = NSWorkspace.shared
    private var observers: [NSObjectProtocol] = []
    private var fallbackTimer: Timer?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?

    private var codexRunning = false
    private var mainRunning = false
    private var mainObservedThisCodexSession = false
    private var launchInFlight = false
    private var launchAttempts = 0
    private var nextLaunchAttempt = Date.distantPast
    private var lastCandidateDetails: String?
    private let maximumLaunchAttempts = 3

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        startMonitoring()
        reconcile(source: "initial", forceCandidateLog: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        let center = workspace.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func menuWillOpen(_ menu: NSMenu) {
        reconcile(source: "menu-open")
    }

    private func configureStatusItem() {
        let newStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = newStatusItem
        newStatusItem.button?.imagePosition = .imageOnly
        newStatusItem.button?.toolTip = "\(AppIdentity.productName) · 正在准备跟随组件"

        let menu = NSMenu(title: AppIdentity.productName)
        menu.delegate = self

        let status = NSMenuItem(title: "状态：正在准备…", action: nil, keyEquivalent: "")
        status.tag = WatcherMenuTag.status.rawValue
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let open = item("打开 TokenOrb", action: #selector(openTokenOrb))
        open.tag = WatcherMenuTag.open.rawValue
        menu.addItem(open)
        let refresh = item("立即检查", action: #selector(refreshNow))
        refresh.tag = WatcherMenuTag.refresh.rawValue
        menu.addItem(refresh)
        menu.addItem(item("打开诊断日志", action: #selector(openDiagnosticLogs)))
        menu.addItem(item("打开登录项设置", action: #selector(openLoginItemSettings)))

        statusMenu = menu
        newStatusItem.menu = menu
        updateStatusItem(text: "正在准备…", symbolName: "circle.dotted", visible: true)
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func startMonitoring() {
        let center = workspace.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reconcile(source: "NSWorkspace.didLaunchApplication")
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reconcile(source: "NSWorkspace.didTerminateApplication")
        })

        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.reconcile(source: "2s-fallback")
        }
        fallbackTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func reconcile(source: String, forceCandidateLog: Bool = false) {
        let applications = workspace.runningApplications
        let previousCodex = codexRunning
        let previousMain = mainRunning

        codexRunning = applications.contains(where: isCodexDesktopHost)
        mainRunning = applications.contains(where: isTokenOrbMainApplication)
        logCandidates(applications, source: source, force: forceCandidateLog)

        if codexRunning != previousCodex {
            WatcherLogger.shared.write(
                operation: "Codex 运行状态变化",
                details: "source=\(source) previous=\(previousCodex) current=\(codexRunning)"
            )
        }
        if mainRunning != previousMain {
            WatcherLogger.shared.write(
                operation: "TokenOrb 主应用状态变化",
                details: "source=\(source) previous=\(previousMain) current=\(mainRunning)"
            )
        }

        if !codexRunning {
            mainObservedThisCodexSession = false
            launchAttempts = 0
            nextLaunchAttempt = .distantPast
        } else if !previousCodex {
            mainObservedThisCodexSession = mainRunning
            launchAttempts = 0
            nextLaunchAttempt = .distantPast
        }

        if mainRunning {
            if codexRunning {
                mainObservedThisCodexSession = true
            }
            launchInFlight = false
            updateStatusItem(text: "主应用运行中", symbolName: "circle.fill", visible: false)
            return
        }

        if !codexRunning {
            updateStatusItem(text: "等待 Codex 启动", symbolName: "circle.dotted", visible: true)
            return
        }

        if mainObservedThisCodexSession {
            updateStatusItem(
                text: "TokenOrb 已退出，点击可重新打开",
                symbolName: "exclamationmark.circle",
                visible: true
            )
            return
        }

        if launchAttempts >= maximumLaunchAttempts {
            updateStatusItem(
                text: "TokenOrb 启动失败，请查看诊断日志",
                symbolName: "exclamationmark.triangle",
                visible: true
            )
            return
        }

        updateStatusItem(text: "正在启动 TokenOrb…", symbolName: "arrow.clockwise", visible: true)
        if !launchInFlight, Date() >= nextLaunchAttempt {
            launchMain(arguments: [AppIdentity.watcherLaunchArgument], automatic: true)
        }
    }

    private func isCodexDesktopHost(_ application: NSRunningApplication) -> Bool {
        CodexProcessPolicy.isDesktopHost(
            bundleIdentifier: application.bundleIdentifier,
            localizedName: application.localizedName,
            bundlePath: application.bundleURL?.path,
            isRegularApplication: application.activationPolicy == .regular
        )
    }

    private func isTokenOrbMainApplication(_ application: NSRunningApplication) -> Bool {
        application.bundleIdentifier?.caseInsensitiveCompare(AppIdentity.bundleIdentifier)
            == .orderedSame
    }

    private func launchMain(arguments: [String], automatic: Bool) {
        guard let applicationURL = mainApplicationURL() else {
            launchAttempts = maximumLaunchAttempts
            WatcherLogger.shared.write(
                operation: "TokenOrb 主应用路径无效",
                details: "watcherBundle=\(Bundle.main.bundleURL.path)"
            )
            updateStatusItem(
                text: "找不到 TokenOrb.app，请重新安装",
                symbolName: "exclamationmark.triangle",
                visible: true
            )
            return
        }

        launchInFlight = true
        launchAttempts += 1
        nextLaunchAttempt = Date().addingTimeInterval(2)

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.allowsRunningApplicationSubstitution = true
        configuration.createsNewApplicationInstance = false
        configuration.promptsUserIfNeeded = !automatic
        configuration.arguments = arguments

        WatcherLogger.shared.write(
            operation: "请求启动 TokenOrb 主应用",
            details: "automatic=\(automatic) attempt=\(launchAttempts) path=\(applicationURL.path)"
        )
        workspace.openApplication(at: applicationURL, configuration: configuration) {
            application,
            error in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.launchInFlight = false
                if let error {
                    WatcherLogger.shared.write(
                        operation: "TokenOrb 主应用启动失败",
                        details: "attempt=\(self.launchAttempts) error=\(String(reflecting: error))"
                    )
                } else {
                    WatcherLogger.shared.write(
                        operation: "TokenOrb 主应用启动请求完成",
                        details: "pid=\(application?.processIdentifier ?? 0)"
                    )
                }
                self.reconcile(source: "openApplication-completion")
            }
        }
    }

    private func mainApplicationURL() -> URL? {
        let helperURL = Bundle.main.bundleURL
        let applicationURL = helperURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard
            applicationURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
            Bundle(url: applicationURL)?.bundleIdentifier?.caseInsensitiveCompare(
                AppIdentity.bundleIdentifier
            ) == .orderedSame
        else { return nil }
        return applicationURL
    }

    private func updateStatusItem(text: String, symbolName: String, visible: Bool) {
        statusItem?.isVisible = visible
        statusItem?.button?.toolTip = "\(AppIdentity.productName) · \(text)"
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: AppIdentity.productName
        )
        image?.isTemplate = true
        statusItem?.button?.image = image
        statusMenu?.item(withTag: WatcherMenuTag.status.rawValue)?.title = "状态：\(text)"
        statusMenu?.item(withTag: WatcherMenuTag.open.rawValue)?.isEnabled = !mainRunning
    }

    private func logCandidates(
        _ applications: [NSRunningApplication],
        source: String,
        force: Bool
    ) {
        let details = applications.compactMap { application -> String? in
            guard CodexProcessPolicy.isDiagnosticCandidate(
                bundleIdentifier: application.bundleIdentifier,
                localizedName: application.localizedName,
                bundlePath: application.bundleURL?.path
            ) else { return nil }
            return [
                "pid=\(application.processIdentifier)",
                "bundle=\(application.bundleIdentifier ?? "nil")",
                "name=\(application.localizedName ?? "nil")",
                "policy=\(activationPolicyName(application.activationPolicy))",
                "path=\(application.bundleURL?.path ?? "nil")",
            ].joined(separator: " ")
        }
        .sorted()
        .joined(separator: " | ")

        let normalized = details.isEmpty ? "<none>" : details
        guard force || normalized != lastCandidateDetails else { return }
        lastCandidateDetails = normalized
        WatcherLogger.shared.write(
            operation: "Codex 候选进程",
            details: "source=\(source) candidates=\(normalized)"
        )
    }

    private func activationPolicyName(_ policy: NSApplication.ActivationPolicy) -> String {
        switch policy {
        case .regular: return "regular"
        case .accessory: return "accessory"
        case .prohibited: return "prohibited"
        @unknown default: return "unknown(\(policy.rawValue))"
        }
    }

    @objc private func openTokenOrb() {
        mainObservedThisCodexSession = false
        launchAttempts = 0
        nextLaunchAttempt = .distantPast
        launchMain(arguments: [], automatic: false)
    }

    @objc private func refreshNow() {
        reconcile(source: "manual-refresh", forceCandidateLog: true)
    }

    @objc private func openDiagnosticLogs() {
        WatcherLogger.shared.prepareDirectory()
        workspace.open(WatcherLogger.shared.directoryURL)
    }

    @objc private func openLoginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

private final class WatcherLogger {
    static let shared = WatcherLogger()

    private let queue = DispatchQueue(label: "com.tokenorb.watcher.logs", qos: .utility)
    let directoryURL: URL
    private let maximumBytes: UInt64 = 1_024 * 1_024

    private init() {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        directoryURL = applicationSupport.appendingPathComponent("TokenOrb", isDirectory: true)
    }

    func prepareDirectory() {
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    func write(operation: String, details: String) {
        let directory = directoryURL
        let maximumBytes = maximumBytes
        queue.async {
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                let current = directory.appendingPathComponent("watcher.log")
                let previous = directory.appendingPathComponent("watcher.previous.log")
                let attributes = try? FileManager.default.attributesOfItem(atPath: current.path)
                let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
                if size >= maximumBytes {
                    try? FileManager.default.removeItem(at: previous)
                    try FileManager.default.moveItem(at: current, to: previous)
                }
                let safeOperation = Self.sanitize(operation, maximumLength: 120)
                let safeDetails = Self.sanitize(details, maximumLength: 8_000)
                let entry = "\(Self.timestamp()) [\(safeOperation)] \(safeDetails)\n"
                try Self.append(entry, to: current)
            } catch {
                // Logging must never destabilize the watcher.
            }
        }
    }

    private static func append(_ text: String, to url: URL) throws {
        let data = Data(text.utf8)
        if !FileManager.default.fileExists(atPath: url.path) {
            try data.write(to: url, options: .atomic)
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private static func sanitize(_ value: String, maximumLength: Int) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { text = "unknown" }
        text = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if !home.isEmpty {
            text = text.replacingOccurrences(
                of: home,
                with: "$HOME",
                options: [.caseInsensitive]
            )
        }
        guard text.count > maximumLength else { return text }
        return String(text.prefix(maximumLength)) + "…"
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

let application = NSApplication.shared
private let delegate = WatcherDelegate()
application.delegate = delegate
application.run()
