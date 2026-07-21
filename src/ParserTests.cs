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
                TestWindowNames();
                TestCodexDesktopProcessMatching();
                TestWatcherTrayBehavior();
                TestAppIdentity();
                TestWaveColors();
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
            Assert(AppIdentity.DisplayVersion == "v1.1", "Display version should be v1.1");
            Assert(AppIdentity.ProtocolVersion == "1.1.0", "Protocol version should be semantic v1.1");
            Assert(AppIdentity.Publisher == "chenxulin", "Publisher should be chenxulin");
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
        }

        private static void TestWaveColors()
        {
            Assert(UiPalette.WaveColor(100.0) == UiPalette.Green, "100 percent should use a green wave");
            Assert(UiPalette.WaveColor(20.001) == UiPalette.Green, "Values above 20 percent should use a green wave");
            Assert(UiPalette.WaveColor(20.0) == UiPalette.Amber, "20 percent should use an orange wave");
            Assert(UiPalette.WaveColor(10.001) == UiPalette.Amber, "Values above 10 percent should use an orange wave");
            Assert(UiPalette.WaveColor(10.0) == UiPalette.Red, "10 percent should use a red wave");
            Assert(UiPalette.WaveColor(0.0) == UiPalette.Red, "Values below 10 percent should use a red wave");
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
