import Foundation

public enum CodexProcessPolicy {
    /// Distinguishes the visible Codex desktop host from the `codex app-server`
    /// child, which can share the same executable name.
    public static func isDesktopHost(
        bundleIdentifier: String?,
        localizedName: String?,
        bundlePath: String?,
        isRegularApplication: Bool
    ) -> Bool {
        let identifier = bundleIdentifier?.lowercased() ?? ""
        let name = localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let path = bundlePath?.lowercased() ?? ""

        // The exact desktop bundle identifier is sufficient on its own. Some
        // healthy and recovering LaunchServices states temporarily expose the
        // host as accessory/prohibited even though it is the real Codex app.
        if identifier == "com.openai.codex" {
            return true
        }
        guard isRegularApplication else { return false }
        return name == "codex"
            && (path.hasSuffix("/codex.app") || path.contains("/codex.app/"))
    }

    public static func isDiagnosticCandidate(
        bundleIdentifier: String?,
        localizedName: String?,
        bundlePath: String?
    ) -> Bool {
        [bundleIdentifier, localizedName, bundlePath]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains("codex") }
    }
}
