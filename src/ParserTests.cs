using System;
using System.Collections.Generic;
using System.Globalization;

namespace CodexQuotaBall
{
    public static class ParserTests
    {
        private static int assertions;

        public static int Main(string[] args)
        {
            try
            {
                TestLocalSnakeCaseEvent();
                TestRpcCamelCasePayload();
                TestSparseMerge();
                TestRealtimeRetryPolicy();
                TestWindowNames();
                TestCodexDesktopProcessMatching();
                TestFollowCodexStartupDefaults();
                TestWatcherTrayBehavior();
                TestAppIdentity();
                TestWaveColors();
                TestWaveVisibility();
                TestDepletedBallBorder();
                TestOuterRingBreathing();
                TestBodyLightingMotion();
                TestBallPositioning();
                Console.WriteLine("PASS: " + assertions.ToString(CultureInfo.InvariantCulture) + " assertions");
                return 0;
            }
            catch (Exception exception)
            {
                Console.Error.WriteLine("FAIL: " + exception.Message);
                return 1;
            }
        }

        private static void TestLocalSnakeCaseEvent()
        {
            string json = "{\"timestamp\":\"2026-07-21T08:00:00Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"rate_limits\":{\"limit_id\":\"codex\",\"primary\":{\"used_percent\":54.0,\"window_minutes\":10080,\"resets_at\":1785142848},\"secondary\":null,\"credits\":{\"has_credits\":true,\"unlimited\":false,\"balance\":\"2226.6674375000\"},\"plan_type\":\"plus\"}}}";
            QuotaSnapshot snapshot = QuotaJsonParser.ParseLocalEventLine(json);
            Assert(snapshot != null, "Local snapshot should parse");
            Assert(snapshot.Primary != null, "Local primary window should parse");
            AssertNear(46.0, snapshot.Primary.RemainingPercent, "Local remaining percent");
            Assert(snapshot.Primary.WindowMinutes == 10080, "Local window duration");
            Assert(snapshot.Credits != null && snapshot.Credits.HasCredits == true, "Local credits flag");
            Assert(snapshot.Credits.Balance == "2226.6674375000", "Local credit balance");
            Assert(snapshot.PlanType == "plus", "Local plan type");
            Assert(!snapshot.IsLive, "Local snapshot should be fallback data");
        }

        private static void TestRpcCamelCasePayload()
        {
            string json = "{\"id\":7,\"result\":{\"rateLimits\":{\"limitId\":\"codex\",\"primary\":{\"usedPercent\":25,\"windowDurationMins\":300,\"resetsAt\":1785142848},\"secondary\":{\"usedPercent\":18,\"windowDurationMins\":10080,\"resetsAt\":1785747648},\"credits\":{\"hasCredits\":true,\"unlimited\":false,\"balance\":\"766.76\"},\"planType\":\"pro\",\"rateLimitReachedType\":null}}}";
            IDictionary<string, object> root = QuotaJsonParser.ParseObject(json);
            IDictionary<string, object> result = QuotaJsonParser.AsDictionary(QuotaJsonParser.GetAny(root, "result"));
            IDictionary<string, object> limits = QuotaJsonParser.AsDictionary(QuotaJsonParser.GetAny(result, "rateLimits"));
            QuotaSnapshot snapshot = QuotaJsonParser.FromRateLimitsDictionary(limits, "test", true);
            Assert(snapshot != null && snapshot.HasQuotaData, "RPC snapshot should parse");
            AssertNear(75.0, snapshot.Primary.RemainingPercent, "RPC primary remaining");
            AssertNear(82.0, snapshot.Secondary.RemainingPercent, "RPC secondary remaining");
            Assert(snapshot.MostRestrictiveWindow == snapshot.Primary, "Most restrictive window should be selected");
            Assert(snapshot.PlanType == "pro", "RPC plan type");
            Assert(snapshot.IsLive, "RPC snapshot should be live");
        }

        private static void TestSparseMerge()
        {
            QuotaSnapshot current = new QuotaSnapshot
            {
                Primary = new QuotaWindowInfo
                {
                    UsedPercent = 20,
                    WindowMinutes = 300,
                    ResetsAtUnix = 123456
                },
                Credits = new QuotaCreditsInfo
                {
                    HasCredits = true,
                    Unlimited = false,
                    Balance = "10.5"
                },
                PlanType = "plus",
                Source = "full",
                IsLive = true,
                CapturedAt = DateTimeOffset.Now.AddMinutes(-1)
            };
            QuotaSnapshot update = new QuotaSnapshot
            {
                Primary = new QuotaWindowInfo { UsedPercent = 33 },
                Source = "push",
                IsLive = true,
                CapturedAt = DateTimeOffset.Now
            };
            QuotaSnapshot merged = current.MergeSparse(update);
            AssertNear(33.0, merged.Primary.UsedPercent.Value, "Sparse used percent");
            Assert(merged.Primary.WindowMinutes == 300, "Sparse merge keeps window duration");
            Assert(merged.Primary.ResetsAtUnix == 123456, "Sparse merge keeps reset time");
            Assert(merged.Credits != null && merged.Credits.Balance == "10.5", "Sparse merge keeps credits");
            Assert(merged.PlanType == "plus", "Sparse merge keeps plan");
            Assert(merged.Source == "push", "Sparse merge uses latest source");
        }

        private static void TestRealtimeRetryPolicy()
        {
            RealtimeRetryPolicy policy = new RealtimeRetryPolicy();

            RealtimeRetryDecision first = policy.RegisterFailure();
            Assert(first.ConsecutiveFailures == 1, "First realtime failure should be counted");
            AssertNear(2.0, first.Delay.TotalSeconds, "First retry delay");
            Assert(!first.UseLocalFallback, "First realtime failure should not use local fallback");

            RealtimeRetryDecision second = policy.RegisterFailure();
            Assert(second.ConsecutiveFailures == 2, "Second realtime failure should be counted");
            AssertNear(4.0, second.Delay.TotalSeconds, "Second retry delay");
            Assert(!second.UseLocalFallback, "Second realtime failure should not use local fallback");

            RealtimeRetryDecision third = policy.RegisterFailure();
            Assert(third.ConsecutiveFailures == 3, "Third realtime failure should be counted");
            AssertNear(8.0, third.Delay.TotalSeconds, "Third retry delay");
            Assert(third.UseLocalFallback, "Third realtime failure should use local fallback");

            AssertNear(16.0, policy.RegisterFailure().Delay.TotalSeconds, "Fourth retry delay");
            AssertNear(30.0, policy.RegisterFailure().Delay.TotalSeconds, "Retry delay cap");
            AssertNear(30.0, policy.RegisterFailure().Delay.TotalSeconds, "Retry delay remains capped");

            policy.Reset();
            Assert(policy.ConsecutiveFailures == 0, "Successful realtime query should reset failures");
            RealtimeRetryDecision afterReset = policy.RegisterFailure();
            AssertNear(2.0, afterReset.Delay.TotalSeconds, "Retry delay should restart after success");
            Assert(!afterReset.UseLocalFallback, "Reset should clear local fallback state");
        }

        private static void TestWindowNames()
        {
            Assert(QuotaSnapshot.FormatWindowName(new QuotaWindowInfo { WindowMinutes = 300 }) == "5小时", "Five-hour label");
            Assert(QuotaSnapshot.FormatWindowName(new QuotaWindowInfo { WindowMinutes = 10080 }) == "7天", "Weekly label");
            Assert(QuotaSnapshot.FormatWindowName(new QuotaWindowInfo { WindowMinutes = 90 }) == "90分钟", "Minute label");
        }

        private static void TestCodexDesktopProcessMatching()
        {
            Assert(CodexProcessMonitor.IsCodexDesktopHost(
                "ChatGPT",
                @"C:\Program Files\WindowsApps\OpenAI.Codex_1.0_x64__id\app\ChatGPT.exe",
                null,
                true,
                "ChatGPT"),
                "Packaged Codex desktop host should match");
            Assert(CodexProcessMonitor.IsCodexDesktopHost(
                "ChatGPT",
                null,
                "OpenAI.Codex_1.0_x64__id",
                true,
                "ChatGPT"),
                "Codex package identity should match");
            Assert(!CodexProcessMonitor.IsCodexDesktopHost(
                "ChatGPT",
                null,
                "OpenAI.Codex_1.0_x64__id",
                false,
                "ChatGPT"),
                "Background-only Codex package process should not match");
            Assert(!CodexProcessMonitor.IsCodexDesktopHost(
                "ChatGPT",
                @"C:\Program Files\WindowsApps\OpenAI.ChatGPT_1.0_x64__id\app\ChatGPT.exe",
                "OpenAI.ChatGPT_1.0_x64__id",
                true,
                "ChatGPT"),
                "Regular ChatGPT desktop host should not match");
            Assert(!CodexProcessMonitor.IsCodexDesktopHost(
                "codex",
                @"C:\Users\me\AppData\Local\OpenAI\Codex\bin\version\codex.exe",
                null,
                false,
                String.Empty),
                "Background app-server runtime should not match");
            Assert(CodexProcessMonitor.IsCodexDesktopHost(
                "Codex",
                @"C:\Apps\Codex.exe",
                null,
                true,
                "Codex"),
                "Windowed Codex desktop host should match");
            Assert(!CodexProcessMonitor.IsCodexDesktopHost(
                "notepad",
                @"C:\Windows\notepad.exe",
                null,
                true,
                "Notepad"),
                "Unrelated desktop app should not match");
        }

        private static void TestAppIdentity()
        {
            Assert(AppIdentity.ProductName == "Token Orb", "Product name should be Token Orb");
            Assert(AppIdentity.ExecutableFileName == "TokenOrb.exe", "Executable name should be TokenOrb.exe");
            Assert(AppIdentity.DisplayVersion == "v1.2", "Display version should be v1.2");
            Assert(AppIdentity.ProtocolVersion == "1.2.0", "Protocol version should be semantic v1.2");
            Assert(AppIdentity.Publisher == "chenxulin", "Publisher should be chenxulin");
        }

        private static void TestFollowCodexStartupDefaults()
        {
            Assert(FollowCodexStartupBehavior.ShouldCreateDefaultPreference(false, false),
                "A fresh install should enable the login watcher by default");
            Assert(!FollowCodexStartupBehavior.ShouldCreateDefaultPreference(true, false),
                "An existing Token Orb preference should be preserved");
            Assert(!FollowCodexStartupBehavior.ShouldCreateDefaultPreference(false, true),
                "A legacy preference should be preserved during migration");
        }

        private static void TestWatcherTrayBehavior()
        {
            Assert(WatcherTrayBehavior.ShouldAutoStartOrb(true, true, false, false),
                "Watcher should auto-start the orb when Codex starts");
            Assert(!WatcherTrayBehavior.ShouldAutoStartOrb(false, true, false, false),
                "Disabled follow mode should not auto-start the orb");
            Assert(!WatcherTrayBehavior.ShouldAutoStartOrb(true, false, false, false),
                "Stopped Codex should not auto-start the orb");
            Assert(!WatcherTrayBehavior.ShouldAutoStartOrb(true, true, true, false),
                "An existing orb should not be started twice");
            Assert(!WatcherTrayBehavior.ShouldAutoStartOrb(true, true, false, true),
                "A manually hidden orb should stay hidden during the current Codex session");
            Assert(WatcherTrayBehavior.ShouldKeepManualHideSuppressed(true, true),
                "Manual hide suppression should remain while Codex is running");
            Assert(!WatcherTrayBehavior.ShouldKeepManualHideSuppressed(false, true),
                "Manual hide suppression should reset after Codex stops");
            Assert(WatcherTrayBehavior.ShouldStopOrb(true, false, true, false),
                "Watcher should stop a running orb when Codex closes");
            Assert(WatcherTrayBehavior.ShouldStopOrb(true, false, false, true),
                "Watcher should cancel a pending orb launch when Codex closes");
            Assert(!WatcherTrayBehavior.ShouldStopOrb(true, true, true, false),
                "Watcher should keep the orb running while Codex is open");
            Assert(!WatcherTrayBehavior.ShouldStopOrb(false, false, true, false),
                "Disabled follow mode should not stop a manually managed orb");
            Assert(WatcherTrayBehavior.ShouldShowTrayIcon(true, true),
                "Tray icon should be visible while Codex is open");
            Assert(!WatcherTrayBehavior.ShouldShowTrayIcon(true, false),
                "Tray icon should leave the notification area when Codex closes");
            Assert(!WatcherTrayBehavior.ShouldShowTrayIcon(false, true),
                "Disabled follow mode should not expose a watcher tray icon");
        }

        private static void TestWaveColors()
        {
            Assert(UiPalette.WaveColor(100.0) == UiPalette.Green, "100 percent should use a green wave");
            Assert(UiPalette.WaveColor(20.001) == UiPalette.Green, "Values above 20 percent should use a green wave");
            Assert(UiPalette.WaveColor(20.0) == UiPalette.Amber, "20 percent should use an orange wave");
            Assert(UiPalette.WaveColor(10.001) == UiPalette.Amber, "Values above 10 percent should use an orange wave");
            Assert(UiPalette.WaveColor(10.0) == UiPalette.Red, "10 percent should use a red wave");
            Assert(UiPalette.WaveColor(0.0) == UiPalette.Red, "Values below 10 percent should use a red wave");
            Assert(UiPalette.QuotaColor(20.001) == UiPalette.WaveColor(20.001),
                "Green progress ring should match the wave above 20 percent");
            Assert(UiPalette.QuotaColor(20.0) == UiPalette.WaveColor(20.0),
                "Orange progress ring should match the wave at 20 percent");
            Assert(UiPalette.QuotaColor(10.001) == UiPalette.WaveColor(10.001),
                "Orange progress ring should match the wave above 10 percent");
            Assert(UiPalette.QuotaColor(10.0) == UiPalette.WaveColor(10.0),
                "Red progress ring should match the wave at 10 percent");
        }

        private static void TestWaveVisibility()
        {
            const double size = QuotaBallVisual.DefaultDiameter;
            const double radius = 17.66;
            double minimumHeight = 5.0;

            AssertNear(60.0, QuotaBallVisual.DefaultDiameter,
                "The default orb diameter should be 60 pixels");
            AssertNear(0.0, QuotaBallVisual.CalculateVisibleWaveHeight(size, radius, 0.0),
                "Zero-percent quota should not render a wave");
            AssertNear(minimumHeight, QuotaBallVisual.CalculateVisibleWaveHeight(size, radius, 0.01),
                "Positive red quota should retain its minimum visible height");
            AssertNear(minimumHeight, QuotaBallVisual.CalculateVisibleWaveHeight(size, radius, 10.0),
                "Ten-percent red wave should remain visible");
            Assert(QuotaBallVisual.CalculateVisibleWaveHeight(size, radius, 15.0) >= minimumHeight,
                "Fifteen-percent orange wave should remain visible");
            Assert(QuotaBallVisual.CalculateVisibleWaveHeight(size, radius, 25.0) > minimumHeight,
                "Green wave should use the real quota height above the visibility floor");
            AssertNear(10.0, QuotaBallVisual.CalculateVisibleWaveHeight(160.0, 50.0, 10.0),
                "Large orbs should not inflate an already-visible ten-percent wave");
        }

        private static void TestDepletedBallBorder()
        {
            Assert(QuotaBallVisual.ResolveOuterBorderColor(UiPalette.Blue, 0.0) == UiPalette.Red,
                "Zero-percent outer border should use the low-quota red");
            Assert(QuotaBallVisual.ResolveOuterBorderColor(UiPalette.Blue, 0.01) == UiPalette.OuterRingBlue,
                "Positive quota should use the light-blue outer border");
            Assert(QuotaBallVisual.ResolveOuterBorderColor(UiPalette.Amber, null) == UiPalette.OuterRingBlue,
                "Unknown quota should use the light-blue outer border");
            Assert(QuotaBallVisual.ResolveQuotaTextColor(UiPalette.Blue, 0.0) == UiPalette.Red,
                "Zero-percent text should use the same low-quota red");
            Assert(QuotaBallVisual.ResolveQuotaTextColor(UiPalette.Blue, 0.01) != UiPalette.Red,
                "Positive quota text should preserve the normal color");
        }

        private static void TestOuterRingBreathing()
        {
            AssertNear(3.0, QuotaBallVisual.OuterRingBreathingCycleSeconds,
                "Outer-ring breathing should use a gentle three-second cycle");
            AssertNear(0.5, QuotaBallVisual.CalculateBreathStrength(0.0),
                "Breathing should start at medium brightness");
            AssertNear(1.0, QuotaBallVisual.CalculateBreathStrength(Math.PI / 2.0),
                "Breathing should reach full brightness");
            AssertNear(0.0, QuotaBallVisual.CalculateBreathStrength(Math.PI * 3.0 / 2.0),
                "Breathing should fade to its minimum brightness");
            Assert(QuotaBallVisual.CalculateOuterRingAlpha(0.0, false) == 170,
                "Normal outer ring should remain visible at the breathing minimum");
            Assert(QuotaBallVisual.CalculateOuterRingAlpha(1.0, false) == 255,
                "Normal outer ring should become fully opaque at the breathing maximum");
            Assert(QuotaBallVisual.CalculateOuterRingAlpha(0.0, true) == 210,
                "Depleted red warning should remain prominent at the breathing minimum");
            AssertNear(1.8, QuotaBallVisual.CalculateOuterBorderWidth(60.0, false),
                "Default outer ring should use a balanced 1.8-pixel stroke");
            AssertNear(1.1, QuotaBallVisual.CalculateOuterBorderWidth(24.0, false),
                "Small outer rings should retain a visible minimum width");
            AssertNear(4.5, QuotaBallVisual.CalculateOuterBorderWidth(160.0, false),
                "Large outer rings should use a restrained maximum width");
            AssertNear(2.4, QuotaBallVisual.CalculateOuterBorderWidth(60.0, true),
                "Default depleted warning should remain slightly thicker than the normal ring");
        }

        private static void TestBodyLightingMotion()
        {
            AssertNear(5.6, QuotaBallVisual.BodyLightCycleSeconds,
                "Body lighting should use a visible but comfortable cycle");

            System.Windows.Point top = QuotaBallVisual.CalculateBodyLightOffset(0.0);
            AssertNear(0.0, top.X, "Body lighting should begin horizontally centered");
            AssertNear(0.040, top.Y, "Body lighting should begin with a visible vertical offset");

            System.Windows.Point right = QuotaBallVisual.CalculateBodyLightOffset(Math.PI / 2.0);
            AssertNear(0.075, right.X, "Body lighting should drift visibly across the sphere");
            AssertNear(0.0, right.Y, "Body lighting path should remain centered at the side");

            AssertNear(0.5, QuotaBallVisual.CalculateBodyLightStrength(0.0),
                "Body lighting should begin at medium brightness");
            AssertNear(1.0, QuotaBallVisual.CalculateBodyLightStrength(Math.PI / 2.0),
                "Body lighting should reach its gentle brightness peak");
            AssertNear(0.0, QuotaBallVisual.CalculateBodyLightStrength(Math.PI * 3.0 / 2.0),
                "Body lighting should fade smoothly to its minimum");
            AssertNear(1.0, QuotaBallVisual.CalculateBodyPulseScale(0.0),
                "Body pulse should begin at its natural size");
            AssertNear(1.040, QuotaBallVisual.CalculateBodyPulseScale(Math.PI / 2.0),
                "Body pulse should expand gently but visibly");
            AssertNear(0.960, QuotaBallVisual.CalculateBodyPulseScale(Math.PI * 3.0 / 2.0),
                "Body pulse should contract gently without disappearing");

            System.Windows.Point sheenTop = QuotaBallVisual.CalculateBodySheenOffset(0.0);
            AssertNear(0.0, sheenTop.X, "Body sheen should begin horizontally centered");
            AssertNear(-0.30, sheenTop.Y, "Body sheen should remain in the upper hemisphere");
            System.Windows.Point sheenRight = QuotaBallVisual.CalculateBodySheenOffset(Math.PI / 2.0);
            AssertNear(0.36, sheenRight.X, "Body sheen should visibly sweep toward the right edge");
            AssertNear(-0.34, sheenRight.Y, "Body sheen sweep should remain above the quota text");
            Assert(QuotaBallVisual.CalculateBodyHighlightAlpha(0.0) == 28,
                "Body highlight should remain visible at minimum brightness");
            Assert(QuotaBallVisual.CalculateBodyHighlightAlpha(1.0) == 72,
                "Body highlight should become clearly visible at peak brightness");
            Assert(QuotaBallVisual.CalculateBodySheenAlpha(0.0) == 125,
                "Colored body sheen should remain visible at minimum brightness");
            Assert(QuotaBallVisual.CalculateBodySheenAlpha(1.0) == 195,
                "Colored body sheen should be clearly visible at peak brightness");
            Assert(QuotaBallVisual.CalculateBodySheenCoreAlpha(0.0) == 180,
                "White sheen core should remain visible at minimum brightness");
            Assert(QuotaBallVisual.CalculateBodySheenCoreAlpha(1.0) == 235,
                "White sheen core should remain comfortable at peak brightness");
        }

        private static void TestBallPositioning()
        {
            System.Windows.Rect workArea = new System.Windows.Rect(0.0, 0.0, 1920.0, 1040.0);
            System.Windows.Size ballSize = new System.Windows.Size(60.0, 60.0);

            System.Windows.Point centerPosition = BallPositioning.ClampToWorkArea(
                new System.Windows.Point(800.0, 420.0),
                ballSize,
                workArea);
            AssertNear(800.0, centerPosition.X,
                "A valid horizontal position should not snap to a screen edge");
            AssertNear(420.0, centerPosition.Y,
                "A valid vertical position should not snap to a screen edge");

            System.Windows.Point outsidePosition = BallPositioning.ClampToWorkArea(
                new System.Windows.Point(1900.0, -25.0),
                ballSize,
                workArea);
            AssertNear(1860.0, outsidePosition.X,
                "A position beyond the right edge should be clamped inside the work area");
            AssertNear(0.0, outsidePosition.Y,
                "A position above the work area should be clamped inside the work area");

            System.Windows.Point resizedPosition = BallPositioning.PreserveCenterOnResize(
                new System.Windows.Point(800.0, 420.0),
                new System.Windows.Size(60.0, 60.0),
                new System.Windows.Size(100.0, 100.0),
                workArea);
            AssertNear(780.0, resizedPosition.X,
                "Resizing should preserve the orb horizontal center");
            AssertNear(400.0, resizedPosition.Y,
                "Resizing should preserve the orb vertical center");
        }

        private static void Assert(bool condition, string message)
        {
            assertions++;
            if (!condition)
            {
                throw new InvalidOperationException(message);
            }
        }

        private static void AssertNear(double expected, double actual, string message)
        {
            assertions++;
            if (Math.Abs(expected - actual) > 0.001)
            {
                throw new InvalidOperationException(message + ": expected " + expected + ", actual " + actual);
            }
        }
    }
}
