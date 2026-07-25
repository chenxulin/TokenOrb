import Foundation

public struct LocalSessionsFingerprint: Equatable, Sendable {
    public let newestModification: TimeInterval
    public let fileCount: Int
    public let totalSize: UInt64
    public let signature: UInt64

    public init(
        newestModification: TimeInterval,
        fileCount: Int,
        totalSize: UInt64,
        signature: UInt64
    ) {
        self.newestModification = newestModification
        self.fileCount = fileCount
        self.totalSize = totalSize
        self.signature = signature
    }
}

public struct LocalSnapshotReader: Sendable {
    private static let tailBytes: UInt64 = 2 * 1_024 * 1_024
    public let sessionsRoot: URL

    public init(sessionsRoot: URL = CodexPaths.sessions()) {
        self.sessionsRoot = sessionsRoot
    }

    public func latest() -> QuotaSnapshot? {
        var newest: QuotaSnapshot?
        for candidate in rolloutFiles().prefix(12) {
            guard let snapshot = latestSnapshot(in: candidate.url) else { continue }
            if newest == nil || snapshot.capturedAt > newest!.capturedAt {
                newest = snapshot
            }
        }
        return newest
    }

    /// A lightweight cross-platform replacement for the Windows FileSystemWatcher.
    /// AppKit polls this every second and applies the same 650 ms debounce.
    public func fingerprint() -> LocalSessionsFingerprint {
        let files = rolloutFiles()
        return LocalSessionsFingerprint(
            newestModification: files.map { $0.modified.timeIntervalSinceReferenceDate }.max() ?? 0,
            fileCount: files.count,
            totalSize: files.reduce(0) { $0 + $1.size },
            signature: fingerprintSignature(files)
        )
    }

    private func fingerprintSignature(
        _ files: [(url: URL, modified: Date, size: UInt64)]
    ) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        func combine(_ value: UInt64) {
            hash ^= value
            hash &*= 1_099_511_628_211
        }
        for file in files.sorted(by: { $0.url.path < $1.url.path }) {
            for byte in file.url.path.utf8 {
                combine(UInt64(byte))
            }
            combine(file.modified.timeIntervalSinceReferenceDate.bitPattern)
            combine(file.size)
        }
        return hash
    }

    private func rolloutFiles() -> [(url: URL, modified: Date, size: UInt64)] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var candidates: [(url: URL, modified: Date, size: UInt64)] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            guard name.hasPrefix("rollout-"), name.hasSuffix(".jsonl") else { continue }
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile != false else { continue }
            candidates.append((
                url,
                values?.contentModificationDate ?? .distantPast,
                UInt64(max(0, values?.fileSize ?? 0))
            ))
        }
        return candidates.sorted { $0.modified > $1.modified }
    }

    private func latestSnapshot(in url: URL) -> QuotaSnapshot? {
        guard let text = tailText(from: url) else { return nil }
        for line in text.split(whereSeparator: \.isNewline).reversed() {
            let textLine = String(line)
            guard
                textLine.localizedCaseInsensitiveContains("\"rate_limits\"")
                    || textLine.localizedCaseInsensitiveContains("\"rateLimits\"")
            else { continue }
            if let snapshot = QuotaParser.localEvent(from: textLine), snapshot.hasQuotaData {
                return snapshot
            }
        }
        return nil
    }

    private func tailText(from url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        do {
            let size = try handle.seekToEnd()
            let offset = size > Self.tailBytes ? size - Self.tailBytes : 0
            try handle.seek(toOffset: offset)
            guard let data = try handle.readToEnd(), var text = String(data: data, encoding: .utf8) else {
                return nil
            }
            if offset > 0, let firstNewline = text.firstIndex(of: "\n") {
                text.removeSubrange(...firstNewline)
            }
            return text
        } catch {
            return nil
        }
    }
}
