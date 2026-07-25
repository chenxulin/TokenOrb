import AppKit
import Foundation

final class CodexProcessMonitor {
    private(set) var isRunning = false

    func poll() -> Bool {
        let running = NSWorkspace.shared.runningApplications.contains { application in
            if application.bundleIdentifier == "com.openai.codex" {
                return true
            }

            let name = application.localizedName?.lowercased() ?? ""
            if name == "codex" {
                return true
            }

            let path = application.bundleURL?.path.lowercased() ?? ""
            return path.contains("/codex.app/")
                || (path.contains("/chatgpt.app/") && application.bundleIdentifier == "com.openai.codex")
        }
        let changed = running != isRunning
        isRunning = running
        return changed
    }
}
