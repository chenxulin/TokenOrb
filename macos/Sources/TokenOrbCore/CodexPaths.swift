import Foundation

public enum CodexPaths {
    public static func home(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let configured = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty {
            let expanded = (configured as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
        }
        return homeDirectory.appendingPathComponent(".codex", isDirectory: true)
    }

    public static func sessions(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home(environment: environment, homeDirectory: homeDirectory)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    public static func auth(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home(environment: environment, homeDirectory: homeDirectory)
            .appendingPathComponent("auth.json")
    }
}
