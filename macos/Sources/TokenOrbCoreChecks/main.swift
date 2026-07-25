import Darwin
import Foundation
import TokenOrbCore

var failures = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        failures += 1
        fputs("FAIL: \(message)\n", stderr)
    }
}

func checkCamelCaseRateLimits() {
    let json = """
    {
      "limitId": "codex",
      "primary": {
        "usedPercent": 25,
        "windowDurationMins": 300,
        "resetsAt": 1785142848
      },
      "secondary": {
        "usedPercent": 54,
        "windowDurationMins": 10080,
        "resetsAt": 1785747648
      },
      "credits": {
        "hasCredits": true,
        "unlimited": false,
        "balance": "766.76"
      },
      "planType": "pro"
    }
    """
    guard
        let limits = QuotaParser.object(from: json),
        let snapshot = QuotaParser.snapshot(
            fromRateLimits: limits,
            source: "test",
            isLive: true
        )
    else {
        expect(false, "camelCase rate limits should parse")
        return
    }

    expect(snapshot.primary?.remainingPercent == 75, "primary remaining percent")
    expect(snapshot.secondary?.windowMinutes == 10_080, "secondary window duration")
    expect(snapshot.credits?.balance == "766.76", "credit balance")
    expect(snapshot.planType == "pro", "plan type")
    expect(snapshot.isLive, "live marker")
}

func checkSnakeCaseLocalEvent() {
    let json = """
    {
      "timestamp": "2026-07-21T08:00:00Z",
      "type": "event_msg",
      "payload": {
        "type": "token_count",
        "rate_limits": {
          "limit_id": "codex",
          "primary": {
            "used_percent": 54.0,
            "window_minutes": 10080,
            "resets_at": 1785142848
          },
          "plan_type": "plus"
        }
      }
    }
    """
    guard let snapshot = QuotaParser.localEvent(from: json) else {
        expect(false, "snake_case local event should parse")
        return
    }

    expect(snapshot.limitID == "codex", "local limit id")
    expect(snapshot.primary?.remainingPercent == 46, "local remaining percent")
    expect(snapshot.primary?.windowMinutes == 10_080, "local window duration")
    expect(snapshot.planType == "plus", "local plan")
    expect(!snapshot.isLive, "local snapshot marker")
}

func checkSparseMerge() {
    let current = QuotaSnapshot(
        primary: QuotaWindow(usedPercent: 10, windowMinutes: 300),
        secondary: QuotaWindow(usedPercent: 20, windowMinutes: 10_080),
        credits: QuotaCredits(hasCredits: true, balance: "100"),
        planType: "plus",
        source: "initial",
        isLive: true
    )
    let update = QuotaSnapshot(
        primary: QuotaWindow(usedPercent: 30),
        source: "push",
        isLive: true
    )
    let merged = current.merged(with: update)

    expect(merged.primary?.usedPercent == 30, "sparse primary update")
    expect(merged.primary?.windowMinutes == 300, "sparse primary duration preservation")
    expect(merged.secondary?.usedPercent == 20, "secondary preservation")
    expect(merged.credits?.balance == "100", "credits preservation")
    expect(merged.planType == "plus", "plan preservation")
    expect(merged.source == "push", "source update")
}

func checkNestedRateLimits() {
    let message: [String: Any] = [
        "result": [
            "account": [
                "rateLimits": [
                    "primary": ["usedPercent": 12],
                ],
            ],
        ],
    ]
    let limits = QuotaParser.findRateLimits(in: message)
    let primary = limits?["primary"] as? [String: Any]
    expect(primary?["usedPercent"] as? Int == 12, "nested rate limits lookup")

    let byID: [String: Any] = [
        "rateLimitsByLimitId": [
            "other": ["primary": ["usedPercent": 90]],
            "codex": ["primary": ["usedPercent": 34]],
        ],
    ]
    let codexLimits = QuotaParser.findRateLimits(in: byID)
    let codexPrimary = codexLimits?["primary"] as? [String: Any]
    expect(codexPrimary?["usedPercent"] as? Int == 34, "rate limits by Codex limit id")
}

func checkFormatting() {
    expect(
        QuotaFormatting.windowName(QuotaWindow(windowMinutes: 300)) == "5小时",
        "5-hour window label"
    )
    expect(
        QuotaFormatting.windowName(QuotaWindow(windowMinutes: 10_080)) == "7天",
        "7-day window label"
    )
    expect(QuotaFormatting.planName("plus") == "ChatGPT Plus", "Plus plan label")
    expect(QuotaFormatting.planName("pro") == "ChatGPT Pro", "Pro plan label")
    expect(QuotaFormatting.planName("business") == "ChatGPT Business", "Business plan label")
    expect(QuotaFormatting.planName("edu") == "ChatGPT Edu", "Edu plan label")
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let reset = QuotaWindow(resetsAt: now.addingTimeInterval(125))
    expect(
        QuotaFormatting.resetText(reset, now: now).hasPrefix("2分 5秒后"),
        "sub-hour reset text should include seconds"
    )
    expect(QuotaFormatting.roundedPercent(12.5) == 12, "percentage midpoint rounds to even")
    expect(QuotaFormatting.roundedPercent(13.5) == 14, "percentage midpoint rounds to even up")
}

func checkAppIdentity() {
    expect(AppIdentity.productName == "Token Orb", "product name")
    expect(AppIdentity.displayVersion == "v1.4.0", "display version")
    expect(AppIdentity.protocolVersion == "1.4.0", "protocol version")
    expect(AppIdentity.publisher == "chenxulin", "publisher")
}

func checkAuthStateTracker() {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("TokenOrbCoreChecks-\(UUID().uuidString)", isDirectory: true)
    let authURL = directory.appendingPathComponent("auth.json")
    do {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data("""
        {"auth_mode":"chatgpt","tokens":{"account_id":"account-a","access_token":"one"}}
        """.utf8).write(to: authURL)
        let tracker = AuthStateTracker(authURL: authURL)
        expect(!tracker.pollForChange(), "initial auth state should not count as a change")

        try Data("""
        {"auth_mode":"chatgpt","tokens":{"account_id":"account-a","access_token":"two"}}
        """.utf8).write(to: authURL)
        expect(!tracker.pollForChange(), "same-account token rotation should be ignored")
        expect(!tracker.pollForChange(), "same-account token rotation stays ignored")

        try Data("""
        {"auth_mode":"chatgpt","tokens":{"account_id":"account-b","access_token":"three"}}
        """.utf8).write(to: authURL)
        expect(!tracker.pollForChange(), "account switch should require a stable second observation")
        expect(tracker.pollForChange(), "stable account switch should be detected")

        try Data("{".utf8).write(to: authURL)
        expect(!tracker.pollForChange(), "incomplete auth replacement should be ignored")
    } catch {
        expect(false, "auth tracker fixture: \(error.localizedDescription)")
    }
    try? FileManager.default.removeItem(at: directory)
}

func checkOrbVisualMetrics() {
    expect(OrbVisualMetrics.minimumDiameter == 24, "minimum orb diameter")
    expect(OrbVisualMetrics.maximumDiameter == 160, "maximum orb diameter")
    expect(OrbVisualMetrics.tone(remaining: nil) == .waiting, "waiting tone")
    expect(OrbVisualMetrics.tone(remaining: 21) == .healthy, "healthy threshold")
    expect(OrbVisualMetrics.tone(remaining: 20) == .warning, "warning threshold")
    expect(OrbVisualMetrics.tone(remaining: 10) == .critical, "critical threshold")
    expect(OrbVisualMetrics.tone(remaining: 0) == .depleted, "depleted threshold")
    expect(
        abs(OrbVisualMetrics.bodyPulseScale(phase: .pi / 2) - 1.04) < 0.000_001,
        "body pulse amplitude"
    )
    expect(
        OrbVisualMetrics.visibleWaveHeight(size: 60, radius: 20, remaining: 1) == 5,
        "small quota should retain a visible wave"
    )
}

func checkRetryPolicy() {
    var policy = RealtimeRetryPolicy()
    let first = policy.recordFailure()
    let second = policy.recordFailure()
    let third = policy.recordFailure()
    expect(first.delay == 2 && !first.useLocalFallback, "first realtime retry")
    expect(second.delay == 4 && !second.useLocalFallback, "second realtime retry")
    expect(third.delay == 8 && third.useLocalFallback, "third retry enables fallback")
    expect(policy.recordFailure().delay == 16, "fourth realtime retry")
    expect(policy.recordFailure().delay == 30, "retry delay cap")
    expect(policy.recordFailure().delay == 30, "retry delay remains capped")
    policy.recordSuccess()
    expect(policy.recordFailure().delay == 2, "retry reset")
    expect(
        !LocalFallbackStatePolicy.resolve(
            connected: true,
            currentlyActive: true,
            fallbackRequested: true
        ),
        "live connection should disable local fallback"
    )
    expect(
        LocalFallbackStatePolicy.resolve(
            connected: false,
            currentlyActive: false,
            fallbackRequested: true
        ),
        "explicit fallback request should enable local snapshots"
    )
}

func checkCodexPaths() {
    let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
    let configured = CodexPaths.home(
        environment: ["CODEX_HOME": "/Volumes/CodexData"],
        homeDirectory: home
    )
    expect(configured.path == "/Volumes/CodexData", "CODEX_HOME override")
    expect(
        CodexPaths.sessions(environment: [:], homeDirectory: home).path
            == "/Users/tester/.codex/sessions",
        "default sessions path"
    )
}

func checkCodexProcessPolicy() {
    expect(
        CodexProcessPolicy.isDesktopHost(
            bundleIdentifier: "com.openai.codex",
            localizedName: "Codex",
            bundlePath: "/Applications/Codex.app",
            isRegularApplication: true
        ),
        "Codex desktop bundle should be detected"
    )
    expect(
        !CodexProcessPolicy.isDesktopHost(
            bundleIdentifier: nil,
            localizedName: "codex",
            bundlePath: "/Applications/Codex.app/Contents/Resources/codex",
            isRegularApplication: false
        ),
        "app-server child must not count as the desktop host"
    )
    expect(
        !CodexProcessPolicy.isDesktopHost(
            bundleIdentifier: nil,
            localizedName: "codex",
            bundlePath: "/opt/homebrew/bin/codex",
            isRegularApplication: false
        ),
        "Codex CLI must not count as the desktop host"
    )
}

func checkOrbRuntimePolicy() {
    expect(
        OrbRuntimePolicy.shouldRunService(
            followCodex: true,
            codexRunning: true,
            manuallyHidden: false
        ),
        "following mode should run with Codex"
    )
    expect(
        !OrbRuntimePolicy.shouldRunService(
            followCodex: true,
            codexRunning: false,
            manuallyHidden: false
        ),
        "following mode should stop without Codex"
    )
    expect(
        !OrbRuntimePolicy.shouldRunService(
            followCodex: true,
            codexRunning: true,
            manuallyHidden: true
        ),
        "manual hide should stop the service"
    )
    expect(
        OrbRuntimePolicy.shouldRunService(
            followCodex: false,
            codexRunning: false,
            manuallyHidden: false
        ),
        "standalone mode should run without Codex"
    )
    expect(
        OrbRuntimePolicy.shouldResetManualHide(
            followCodex: true,
            wasCodexRunning: false,
            codexRunning: true
        ),
        "new Codex session should clear manual hide"
    )
}

func checkAccountSwitchPolicy() {
    expect(
        !AccountSwitchQuotaPolicy.canUseClientGeneration(3, minimum: 4),
        "stale client generation should be rejected"
    )
    expect(
        AccountSwitchQuotaPolicy.canUseClientGeneration(4, minimum: 4),
        "minimum client generation should be accepted"
    )
    let switchTime = Date(timeIntervalSince1970: 2_000)
    let stale = QuotaSnapshot(
        primary: QuotaWindow(usedPercent: 20),
        capturedAt: switchTime.addingTimeInterval(-1),
        source: "test",
        isLive: false
    )
    let fresh = QuotaSnapshot(
        primary: QuotaWindow(usedPercent: 20),
        capturedAt: switchTime,
        source: "test",
        isLive: false
    )
    expect(
        !AccountSwitchQuotaPolicy.canUseLocalSnapshot(stale, capturedNotBefore: switchTime),
        "pre-switch local snapshot should be rejected"
    )
    expect(
        AccountSwitchQuotaPolicy.canUseLocalSnapshot(fresh, capturedNotBefore: switchTime),
        "post-switch local snapshot should be accepted"
    )
}

func checkLocalSnapshotReader() {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("TokenOrbSessions-\(UUID().uuidString)", isDirectory: true)
    let nested = root.appendingPathComponent("2026/07/25", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let older = nested.appendingPathComponent("rollout-older.jsonl")
        let newer = nested.appendingPathComponent("rollout-newer.jsonl")
        let olderEvent = """
        {"timestamp":"2026-07-24T08:00:00Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":80,"window_minutes":300}}}}
        """
        let newerEvent = """
        {"timestamp":"2026-07-25T08:00:00Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":25,"window_minutes":300}}}}
        """
        try Data(olderEvent.utf8).write(to: older)
        try Data(newerEvent.utf8).write(to: newer)
        let reader = LocalSnapshotReader(sessionsRoot: root)
        expect(reader.latest()?.primary?.remainingPercent == 75, "newest local snapshot")
        let fingerprint = reader.fingerprint()
        expect(fingerprint.fileCount == 2, "local snapshot fingerprint file count")
        expect(fingerprint.totalSize > 0, "local snapshot fingerprint size")
    } catch {
        expect(false, "local snapshot fixture: \(error.localizedDescription)")
    }
    try? FileManager.default.removeItem(at: root)
}

checkCamelCaseRateLimits()
checkSnakeCaseLocalEvent()
checkSparseMerge()
checkNestedRateLimits()
checkFormatting()
checkAppIdentity()
checkAuthStateTracker()
checkOrbVisualMetrics()
checkRetryPolicy()
checkCodexPaths()
checkCodexProcessPolicy()
checkOrbRuntimePolicy()
checkAccountSwitchPolicy()
checkLocalSnapshotReader()

if failures > 0 {
    fputs("\(failures) core check(s) failed.\n", stderr)
    exit(1)
}
print("All Token Orb core checks passed.")
