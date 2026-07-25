import Foundation

public enum AccountSwitchQuotaPolicy {
    public static func canUseClientGeneration(_ generation: Int, minimum: Int) -> Bool {
        generation >= minimum
    }

    public static func canUseLocalSnapshot(
        _ snapshot: QuotaSnapshot?,
        capturedNotBefore: Date?
    ) -> Bool {
        guard let snapshot, snapshot.hasQuotaData else { return false }
        return capturedNotBefore.map { snapshot.capturedAt >= $0 } ?? true
    }
}
