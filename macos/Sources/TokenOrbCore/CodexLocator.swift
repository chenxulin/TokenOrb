import Foundation

public enum CodexLocatorError: LocalizedError {
    case executableNotFound

    public var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "未找到 Codex CLI。请安装并登录 Codex 桌面应用，或设置 CODEX_QUOTA_CODEX_PATH。"
        }
    }
}

public enum CodexLocator {
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> URL {
        let fileManager = FileManager.default
        var candidates: [String] = []

        if let configured = environment["CODEX_QUOTA_CODEX_PATH"], !configured.isEmpty {
            candidates.append((configured as NSString).expandingTildeInPath)
        }

        let home = homeDirectory.path
        candidates.append(contentsOf: [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "\(home)/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/Applications/ChatGPT.app/Contents/Resources/codex",
            "\(home)/Desktop/Codex.app/Contents/Resources/codex",
            "\(home)/Desktop/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex",
        ])

        if let path = environment["PATH"] {
            candidates.append(
                contentsOf: path
                    .split(separator: ":")
                    .map { String($0) + "/codex" }
            )
        }

        for applicationsRoot in [
            "/Applications",
            "\(home)/Applications",
            "\(home)/Desktop",
        ] {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: applicationsRoot) else {
                continue
            }
            for entry in entries where entry.hasSuffix(".app") {
                let bundleURL = URL(fileURLWithPath: applicationsRoot).appendingPathComponent(entry)
                guard Bundle(url: bundleURL)?.bundleIdentifier == "com.openai.codex" else {
                    continue
                }
                candidates.append(
                    bundleURL
                        .appendingPathComponent("Contents/Resources/codex")
                        .path
                )
            }
        }

        for path in candidates {
            let resolved = URL(fileURLWithPath: path).standardizedFileURL
            if fileManager.isExecutableFile(atPath: resolved.path) {
                return resolved
            }
        }

        throw CodexLocatorError.executableNotFound
    }
}
