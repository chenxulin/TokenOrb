import Foundation

final class AppLogger {
    static let shared = AppLogger()

    private let queue = DispatchQueue(label: "com.tokenorb.logs", qos: .utility)
    private let directory: URL
    private let maximumRealtimeBytes: UInt64 = 1_024 * 1_024

    private init() {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        directory = applicationSupport.appendingPathComponent("TokenOrb", isDirectory: true)
    }

    func error(_ error: Error) {
        let details = String(reflecting: error)
        let logDirectory = directory
        queue.async {
            do {
                try FileManager.default.createDirectory(
                    at: logDirectory,
                    withIntermediateDirectories: true
                )
                let url = logDirectory.appendingPathComponent("error.log")
                let entry = "\(Self.timestamp())\n\(details)\n\n"
                try Self.append(entry, to: url)
            } catch {
                // Diagnostics must never destabilize the menu-bar process.
            }
        }
    }

    func realtime(operation: String, details: String) {
        let logDirectory = directory
        let maximumBytes = maximumRealtimeBytes
        queue.async {
            do {
                try FileManager.default.createDirectory(
                    at: logDirectory,
                    withIntermediateDirectories: true
                )
                let current = logDirectory.appendingPathComponent("realtime-errors.log")
                let previous = logDirectory.appendingPathComponent("realtime-errors.previous.log")
                let attributes = try? FileManager.default.attributesOfItem(atPath: current.path)
                let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
                if size >= maximumBytes {
                    try? FileManager.default.removeItem(at: previous)
                    try FileManager.default.moveItem(at: current, to: previous)
                }
                let safeOperation = Self.sanitize(operation, maximumLength: 120)
                let safeDetails = Self.sanitize(details, maximumLength: 2_000)
                try Self.append(
                    "\(Self.timestamp()) [\(safeOperation)] \(safeDetails)\n",
                    to: current
                )
            } catch {
                // Logging is best effort.
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
