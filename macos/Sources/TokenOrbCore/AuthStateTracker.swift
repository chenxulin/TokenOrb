import Foundation

public final class AuthStateTracker {
    private struct Fingerprint: Equatable {
        let modificationTime: TimeInterval
        let size: UInt64
        let fileNumber: UInt64
    }

    private let authURL: URL
    private var lastFingerprint: Fingerprint?
    private var hasObservedInitialState = false

    public init(
        authURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
    ) {
        self.authURL = authURL
    }

    public func pollForChange() -> Bool {
        let fingerprint = currentFingerprint()
        defer {
            lastFingerprint = fingerprint
            hasObservedInitialState = true
        }
        guard hasObservedInitialState else { return false }
        return fingerprint != lastFingerprint
    }

    private func currentFingerprint() -> Fingerprint? {
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: authURL.path),
            let modificationDate = attributes[.modificationDate] as? Date
        else {
            return nil
        }
        return Fingerprint(
            modificationTime: modificationDate.timeIntervalSinceReferenceDate,
            size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
            fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        )
    }
}
