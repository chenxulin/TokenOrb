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
        guard isRegularApplication else { return false }
        let identifier = bundleIdentifier?.lowercased() ?? ""
        let name = localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let path = bundlePath?.lowercased() ?? ""

        if identifier == "com.openai.codex" {
            return true
        }
        return name == "codex"
            && (path.hasSuffix("/codex.app") || path.contains("/codex.app/"))
    }
}
