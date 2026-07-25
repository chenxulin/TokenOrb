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
        try Data("{}".utf8).write(to: authURL)
        let tracker = AuthStateTracker(authURL: authURL)
        expect(!tracker.pollForChange(), "initial auth state should not count as a change")

        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(2)],
            ofItemAtPath: authURL.path
        )
        expect(tracker.pollForChange(), "auth metadata change should be detected")
    } catch {
        expect(false, "auth tracker fixture: \(error.localizedDescription)")
    }
    try? FileManager.default.removeItem(at: directory)
}

checkCamelCaseRateLimits()
checkSnakeCaseLocalEvent()
checkSparseMerge()
checkNestedRateLimits()
checkFormatting()
checkAuthStateTracker()

if failures > 0 {
    fputs("\(failures) core check(s) failed.\n", stderr)
    exit(1)
}
print("All Token Orb core checks passed.")
