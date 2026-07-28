import AppKit
import Foundation
import TokenOrbCore

final class CodexProcessMonitor {
    typealias StateChangeHandler = (_ wasRunning: Bool, _ isRunning: Bool, _ source: String) -> Void

    private let workspace = NSWorkspace.shared
    private var observers: [NSObjectProtocol] = []
    private var fallbackTimer: Timer?
    private var lastCandidateDetails: String?

    private(set) var isRunning = false
    var onStateChanged: StateChangeHandler?

    func start() {
        guard observers.isEmpty, fallbackTimer == nil else { return }

        let center = workspace.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _ = self?.poll(source: "NSWorkspace.didLaunchApplication")
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _ = self?.poll(source: "NSWorkspace.didTerminateApplication")
        })

        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            _ = self?.poll(source: "2s-fallback")
        }
        fallbackTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        _ = poll(source: "initial", forceCandidateLog: true)
    }

    func stop() {
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        let center = workspace.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
    }

    @discardableResult
    func poll(source: String = "manual", forceCandidateLog: Bool = false) -> Bool {
        let applications = workspace.runningApplications
        let running = applications.contains { application in
            CodexProcessPolicy.isDesktopHost(
                bundleIdentifier: application.bundleIdentifier,
                localizedName: application.localizedName,
                bundlePath: application.bundleURL?.path,
                isRegularApplication: application.activationPolicy == .regular
            )
        }
        logCandidates(
            applications,
            source: source,
            force: forceCandidateLog
        )

        let previous = isRunning
        let changed = running != previous
        isRunning = running
        if changed {
            AppLogger.shared.lifecycle(
                operation: "Codex 运行状态变化",
                details: "source=\(source) previous=\(previous) current=\(running)"
            )
            onStateChanged?(previous, running, source)
        }
        return changed
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
        AppLogger.shared.lifecycle(
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

    deinit {
        stop()
    }
}
