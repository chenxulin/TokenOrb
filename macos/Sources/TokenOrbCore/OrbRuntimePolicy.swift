import Foundation

public enum OrbRuntimePolicy {
    public static func runtimeAllowsOrb(followCodex: Bool, codexRunning: Bool) -> Bool {
        !followCodex || codexRunning
    }

    public static func shouldRunService(
        followCodex: Bool,
        codexRunning: Bool,
        manuallyHidden: Bool
    ) -> Bool {
        runtimeAllowsOrb(followCodex: followCodex, codexRunning: codexRunning)
            && !manuallyHidden
    }

    public static func shouldResetManualHide(
        followCodex: Bool,
        wasCodexRunning: Bool,
        codexRunning: Bool
    ) -> Bool {
        followCodex && wasCodexRunning != codexRunning
    }
}
