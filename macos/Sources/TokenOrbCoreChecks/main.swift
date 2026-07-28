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
    expect(QuotaFormatting.credits(nil) == "0", "missing additional credits label")
    expect(
        QuotaFormatting.credits(QuotaCredits(hasCredits: false)) == "0",
        "disabled additional credits label"
    )

    let capturedAt = Date(timeIntervalSince1970: 1_798_854_245)
    let liveSnapshot = QuotaSnapshot(
        capturedAt: capturedAt,
        source: "Codex 实时接口",
        isLive: true
    )
    let localSnapshot = QuotaSnapshot(
        capturedAt: capturedAt,
        source: "本地会话快照",
        isLive: false
    )
    expect(QuotaFormatting.dataSource(liveSnapshot) == "实时数据", "live data source label")
    expect(QuotaFormatting.dataSource(localSnapshot) == "本地快照", "local snapshot label")
    let capturedFormatter = DateFormatter()
    capturedFormatter.locale = Locale(identifier: "zh_CN")
    capturedFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    expect(
        QuotaFormatting.capturedAtText(liveSnapshot) == capturedFormatter.string(from: capturedAt),
        "capture timestamp should include the local year and seconds"
    )

    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let reset = QuotaWindow(resetsAt: now.addingTimeInterval(125))
    expect(
        QuotaFormatting.resetCountdownText(reset, now: now) == "2分5秒后",
        "sub-hour reset text should include seconds"
    )

    let isoFormatter = ISO8601DateFormatter()
    let staleWeeklyReset = isoFormatter.date(from: "2026-12-28T08:00:00Z")!
    let crossYearNow = isoFormatter.date(from: "2026-12-31T16:00:00Z")!
    let weeklyWindow = QuotaWindow(
        windowMinutes: 10_080,
        resetsAt: staleWeeklyReset
    )
    let expectedWeeklyReset = staleWeeklyReset.addingTimeInterval(7 * 86_400)
    expect(
        QuotaFormatting.resolvedReset(weeklyWindow, now: crossYearNow) == expectedWeeklyReset,
        "expired weekly reset should advance by exactly seven days across the year"
    )
    expect(
        QuotaFormatting.resetDateText(weeklyWindow, now: crossYearNow)
            == capturedFormatter.string(from: expectedWeeklyReset),
        "reset timestamp should use the full resolved local date"
    )
    expect(
        QuotaFormatting.resetCountdownText(weeklyWindow, now: crossYearNow)
            == "3天16小时后",
        "weekly countdown should remain separate from the reset date"
    )
    expect(QuotaFormatting.roundedPercent(12.5) == 12, "percentage midpoint rounds to even")
    expect(QuotaFormatting.roundedPercent(13.5) == 14, "percentage midpoint rounds to even up")
}

func checkAppIdentity() {
    expect(AppIdentity.productName == "TokenOrb", "product name")
    expect(
        AppIdentity.bundleIdentifier == "com.chenxulin.TokenOrb",
        "main bundle identifier"
    )
    expect(
        AppIdentity.watcherBundleIdentifier == "com.chenxulin.TokenOrb.Watcher",
        "watcher bundle identifier"
    )
    expect(AppIdentity.displayVersion == "v1.5.3", "display version")
    expect(AppIdentity.protocolVersion == "1.5.3", "protocol version")
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
    expect(OrbVisualMetrics.defaultDiameter == 65, "default orb diameter")
    expect(OrbVisualMetrics.minimumDiameter == 24, "minimum orb diameter")
    expect(OrbVisualMetrics.maximumDiameter == 160, "maximum orb diameter")
    expect(
        OrbAppearanceDefaults.accentHex == "#2FA4EB"
            && OrbAppearanceDefaults.textStyle == .condensed
            && OrbAppearanceDefaults.animationFrameRate == 60,
        "fresh installations should use the release appearance defaults"
    )
    expect(
        OrbVisualMetrics.animationFramesPerSecond == 60,
        "water-wave animation should target 60 FPS"
    )
    expect(
        OrbVisualMetrics.supportedAnimationFrameRates == [30, 60, 90, 120, 180],
        "appearance settings should expose all supported animation frame rates"
    )
    expect(
        OrbVisualMetrics.normalizedAnimationFrameRate(180) == 180,
        "supported high frame rates should be preserved"
    )
    expect(
        OrbVisualMetrics.normalizedAnimationFrameRate(144) == 60,
        "unknown frame rates should safely fall back to 60 FPS"
    )
    expect(
        abs(OrbVisualMetrics.animationInterval(frameRate: 120) - 1.0 / 120.0)
            < 0.000_001,
        "selected frame rate should determine the animation interval"
    )
    expect(
        abs(OrbVisualMetrics.animationInterval - 1.0 / 60.0) < 0.000_001,
        "water-wave fallback clock should use a 60 FPS interval"
    )
    expect(
        abs(OrbVisualMetrics.wavePhaseRadiansPerSecond * 0.040 - 0.15) < 0.000_001,
        "water-wave angular velocity should preserve the previous animation speed"
    )
    expect(
        OrbVisualMetrics.backWavePhaseRadiansPerSecond < 0,
        "the background wave should move independently in the opposite direction"
    )
    let fullCycle = Double.pi * 2
    let frontBeforeWrap = fullCycle - 0.001
    let frontElapsed = 0.001
    let frontUnwrapped = frontBeforeWrap
        + OrbVisualMetrics.wavePhaseRadiansPerSecond * frontElapsed
    let frontAfterWrap = OrbVisualMetrics.advancedLoopingPhase(
        phase: frontBeforeWrap,
        radiansPerSecond: OrbVisualMetrics.wavePhaseRadiansPerSecond,
        elapsedSeconds: frontElapsed
    )
    expect(
        abs(sin(frontUnwrapped) - sin(frontAfterWrap)) < 0.000_001,
        "the foreground wave should cross the 2π seam without a visual jump"
    )
    let backBeforeWrap = 0.001
    let backElapsed = 0.001
    let backUnwrapped = backBeforeWrap
        + OrbVisualMetrics.backWavePhaseRadiansPerSecond * backElapsed
    let backAfterWrap = OrbVisualMetrics.advancedLoopingPhase(
        phase: backBeforeWrap,
        radiansPerSecond: OrbVisualMetrics.backWavePhaseRadiansPerSecond,
        elapsedSeconds: backElapsed
    )
    expect(
        abs(sin(backUnwrapped) - sin(backAfterWrap)) < 0.000_001,
        "the background wave should cross the zero seam without a visual jump"
    )
    for frameRate in OrbVisualMetrics.supportedAnimationFrameRates {
        let elapsed = 1.0 / Double(frameRate)
        var frontPhase = 0.0
        var backPhase = OrbVisualMetrics.backWaveInitialPhase
        var previousFrontSample = OrbVisualMetrics.waveSurfaceSample(
            progress: 0.37,
            phase: frontPhase,
            cycles: 1.42
        )
        var previousBackSample = OrbVisualMetrics.waveSurfaceSample(
            progress: 0.63,
            phase: backPhase,
            cycles: 1.20
        )
        var maximumFrontStep = 0.0
        var maximumBackStep = 0.0
        for _ in 0..<(frameRate * 120) {
            frontPhase = OrbVisualMetrics.advancedLoopingPhase(
                phase: frontPhase,
                radiansPerSecond: OrbVisualMetrics.wavePhaseRadiansPerSecond,
                elapsedSeconds: elapsed
            )
            backPhase = OrbVisualMetrics.advancedLoopingPhase(
                phase: backPhase,
                radiansPerSecond: OrbVisualMetrics.backWavePhaseRadiansPerSecond,
                elapsedSeconds: elapsed
            )
            let frontSample = OrbVisualMetrics.waveSurfaceSample(
                progress: 0.37,
                phase: frontPhase,
                cycles: 1.42
            )
            let backSample = OrbVisualMetrics.waveSurfaceSample(
                progress: 0.63,
                phase: backPhase,
                cycles: 1.20
            )
            maximumFrontStep = max(
                maximumFrontStep,
                abs(frontSample - previousFrontSample)
            )
            maximumBackStep = max(
                maximumBackStep,
                abs(backSample - previousBackSample)
            )
            previousFrontSample = frontSample
            previousBackSample = backSample
        }
        expect(
            maximumFrontStep
                <= abs(OrbVisualMetrics.wavePhaseRadiansPerSecond) * elapsed + 0.000_001,
            "foreground wave continuity at \(frameRate) FPS"
        )
        expect(
            maximumBackStep
                <= abs(OrbVisualMetrics.backWavePhaseRadiansPerSecond) * elapsed + 0.000_001,
            "background wave continuity at \(frameRate) FPS"
        )
    }
    expect(
        abs(OrbVisualMetrics.animationElapsedSeconds(
            previousTimestamp: 1,
            currentTimestamp: 1 + 1.0 / 120.0
        ) - 1.0 / 120.0) < 0.000_001,
        "display-synchronized animation should preserve high-refresh frame timing"
    )
    expect(
        OrbVisualMetrics.animationElapsedSeconds(previousTimestamp: 1, currentTimestamp: 2)
            == OrbVisualMetrics.maximumAnimationDelta,
        "animation should cap long frame gaps to prevent visible jumps"
    )
    expect(
        OrbVisualMetrics.animationElapsedSeconds(
            previousTimestamp: nil,
            currentTimestamp: 1
        ) == OrbVisualMetrics.animationInterval,
        "first frame should use the 60 FPS fallback interval"
    )
    expect(OrbVisualMetrics.defaultTrailingMargin == 22, "Windows default trailing margin")
    expect(OrbVisualMetrics.defaultTopOffsetRatio == 0.38, "Windows default top offset")
    expect(
        OrbAppearancePresets.all.map { $0.hex } == [
            "#2FA4EB",
            "#31BE91",
            "#8D83F6",
            "#4D8DF7",
            "#F49A6A",
            "#EA718C",
        ],
        "appearance presets should match Windows RGB values"
    )
    expect(
        OrbTextStyle.allCases.map(\.rawValue) == [
            "minimal",
            "geometric",
            "condensed",
            "rounded",
            "emphasis",
        ],
        "text style storage values should match Windows"
    )
    expect(
        OrbTextStyle(storedValue: nil) == .minimal,
        "legacy appearance settings should use the minimal text style"
    )
    expect(
        OrbTextStyle(storedValue: "future-style") == .minimal,
        "unknown text styles should safely fall back"
    )
    expect(
        OrbTextStyle.allCases.map(\.displayName) == [
            "Wing",
            "Aureole",
            "Spear",
            "Pearl",
            "Thunder",
        ],
        "text styles should expose their user-facing names"
    )
    expect(
        abs(OrbVisualMetrics.previewWidth / OrbVisualMetrics.previewHeight - 16.0 / 9.0)
            < 0.000_001,
        "system preview surface should use a 16:9 rectangle"
    )
    expect(OrbVisualMetrics.previewCornerRadius > 0, "system preview should retain round corners")
    let previewOffset = OrbVisualMetrics.previewOffset(diameter: 60)
    expect(previewOffset.x == 130, "orb should be horizontally centered in system preview")
    expect(previewOffset.y == 60, "orb should be vertically centered in system preview")
    expect(
        OrbVisualMetrics.appearancePreviewDiameter(configuredDiameter: 24) == 54,
        "small configured orbs should retain a legible appearance preview"
    )
    expect(
        OrbVisualMetrics.appearancePreviewDiameter(configuredDiameter: 60) == 60,
        "mid-sized configured orbs should use their actual appearance preview size"
    )
    expect(
        OrbVisualMetrics.appearancePreviewDiameter(configuredDiameter: 160) == 82,
        "large configured orbs should fit inside the appearance preview card"
    )
    expect(
        !OrbVisualMetrics.shouldTreatAsDrag(deltaX: 3, deltaY: 0),
        "movement below the Windows click threshold should remain a click"
    )
    expect(
        OrbVisualMetrics.shouldTreatAsDrag(deltaX: 2, deltaY: 2),
        "movement at the Windows drag threshold should start a drag"
    )
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
    expect(
        first.delay == 5 && first.retryAttempt == 1 && !first.useLocalFallback,
        "first restart retry"
    )
    expect(
        second.delay == 10 && second.retryAttempt == 2 && !second.useLocalFallback,
        "second restart retry"
    )
    expect(
        third.delay == 15 && third.retryAttempt == 3 && !third.useLocalFallback,
        "third restart retry"
    )
    let fourth = policy.recordFailure()
    expect(
        fourth.delay == 30 && fourth.retryAttempt == 0 && fourth.useLocalFallback,
        "fallback starts after three failed retries"
    )
    let fifth = policy.recordFailure()
    expect(fifth.delay == 30 && fifth.useLocalFallback, "fallback retry stays at 30 seconds")
    policy.recordSuccess()
    expect(policy.recordFailure().delay == 5, "retry reset")
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
        CodexProcessPolicy.isDesktopHost(
            bundleIdentifier: "COM.OPENAI.CODEX",
            localizedName: nil,
            bundlePath: nil,
            isRegularApplication: false
        ),
        "exact Codex bundle should not depend on activation policy"
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
    expect(
        CodexProcessPolicy.isDiagnosticCandidate(
            bundleIdentifier: "com.openai.codex.helper",
            localizedName: nil,
            bundlePath: nil
        ),
        "Codex helper should be included in diagnostics"
    )
    expect(
        !CodexProcessPolicy.isDiagnosticCandidate(
            bundleIdentifier: "com.apple.finder",
            localizedName: "Finder",
            bundlePath: "/System/Library/CoreServices/Finder.app"
        ),
        "unrelated apps should be omitted from diagnostics"
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
    expect(
        OrbRuntimePolicy.shouldResetManualHide(
            followCodex: true,
            wasCodexRunning: true,
            codexRunning: false
        ),
        "ending a Codex session should clear manual hide"
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
print("All TokenOrb core checks passed.")
