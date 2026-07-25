import CryptoKit
import Foundation

/// Tracks the authenticated account identity without retaining or logging credentials.
/// Token rotation for the same account is intentionally ignored, matching Windows.
public final class AuthStateTracker {
    private struct Fingerprint: Equatable {
        let digest: Data

        init(identity: String) {
            digest = Data(SHA256.hash(data: Data(identity.utf8)))
        }
    }

    private let authURL: URL
    private var current: Fingerprint?
    private var pending: Fingerprint?

    public init(authURL: URL = CodexPaths.auth()) {
        self.authURL = authURL
        current = Self.capture(from: authURL)
    }

    /// Requires the same new identity in two consecutive observations so a replacing
    /// `auth.json` cannot momentarily mix the previous and next accounts.
    public func pollForChange() -> Bool {
        guard let observed = Self.capture(from: authURL) else { return false }
        guard let current else {
            self.current = observed
            pending = nil
            return false
        }
        if current == observed {
            pending = nil
            return false
        }
        if pending == observed {
            self.current = observed
            pending = nil
            return true
        }
        pending = observed
        return false
    }

    private static func capture(from url: URL) -> Fingerprint? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Fingerprint(identity: "missing")
        }
        guard
            let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            // Codex may be replacing the file. Retain the last stable identity.
            return nil
        }

        let authMode = string(root["auth_mode"] ?? root["authMode"]) ?? ""
        let tokens = root["tokens"] as? [String: Any]
        let accountID = string(tokens?["account_id"] ?? tokens?["accountId"])
        if let accountID, !accountID.isEmpty {
            return Fingerprint(identity: "account\0\(authMode)\0\(accountID)")
        }

        let credential = string(
            root["OPENAI_API_KEY"]
                ?? root["personal_access_token"]
                ?? root["bedrock_api_key"]
        )
        if let credential, !credential.isEmpty {
            return Fingerprint(identity: "credential\0\(authMode)\0\(credential)")
        }

        guard let json = String(data: data, encoding: .utf8) else { return nil }
        return Fingerprint(identity: "auth-file\0\(json)")
    }

    private static func string(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        return (value as? String) ?? String(describing: value)
    }
}
