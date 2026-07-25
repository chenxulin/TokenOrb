import Foundation

public struct LocalSnapshotReader: Sendable {
    public let sessionsRoot: URL

    public init(
        sessionsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
    ) {
        self.sessionsRoot = sessionsRoot
    }

    public func latest() -> QuotaSnapshot? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        var candidates: [(url: URL, modified: Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            candidates.append((url, values?.contentModificationDate ?? .distantPast))
        }

        for candidate in candidates.sorted(by: { $0.modified > $1.modified }).prefix(8) {
            guard let text = tailText(from: candidate.url) else { continue }
            for line in text.split(whereSeparator: \.isNewline).reversed() {
                if let snapshot = QuotaParser.localEvent(from: String(line)) {
                    return snapshot
                }
            }
        }
        return nil
    }

    private func tailText(from url: URL, maximumBytes: UInt64 = 1_048_576) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > maximumBytes ? size - maximumBytes : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
