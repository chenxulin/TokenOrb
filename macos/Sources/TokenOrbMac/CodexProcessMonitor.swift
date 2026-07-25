import AppKit
import Foundation
import TokenOrbCore

final class CodexProcessMonitor {
    private(set) var isRunning = false

    func poll() -> Bool {
        let running = NSWorkspace.shared.runningApplications.contains { application in
            CodexProcessPolicy.isDesktopHost(
                bundleIdentifier: application.bundleIdentifier,
                localizedName: application.localizedName,
                bundlePath: application.bundleURL?.path,
                isRegularApplication: application.activationPolicy == .regular
            )
        }
        let changed = running != isRunning
        isRunning = running
        return changed
    }
}
