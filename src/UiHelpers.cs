using Microsoft.Win32;
using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Windows.Media;

namespace CodexQuotaBall
{
    public static class QuotaFormatting
    {
        public static string FormatReset(QuotaWindowInfo window)
        {
            if (window == null || !window.ResetsAtUnix.HasValue)
            {
                return "重置时间未知";
            }

            DateTimeOffset reset = UnixTime.ToDateTimeOffset(window.ResetsAtUnix.Value).ToLocalTime();
            TimeSpan remaining = reset - DateTimeOffset.Now;
            string countdown;
            if (remaining.TotalSeconds <= 0)
            {
                countdown = "等待 Codex 刷新";
            }
            else if (remaining.TotalDays >= 1.0)
            {
                countdown = ((int)remaining.TotalDays).ToString(CultureInfo.InvariantCulture)
                    + "天 " + remaining.Hours.ToString(CultureInfo.InvariantCulture) + "小时后";
            }
            else if (remaining.TotalHours >= 1.0)
            {
                countdown = ((int)remaining.TotalHours).ToString(CultureInfo.InvariantCulture)
                    + "小时 " + remaining.Minutes.ToString(CultureInfo.InvariantCulture) + "分后";
            }
            else
            {
                countdown = Math.Max(0, remaining.Minutes).ToString(CultureInfo.InvariantCulture)
                    + "分 " + Math.Max(0, remaining.Seconds).ToString(CultureInfo.InvariantCulture) + "秒后";
            }

            return countdown + " · " + reset.ToString("MM-dd HH:mm", CultureInfo.CurrentCulture);
        }

        public static string FormatCredits(QuotaCreditsInfo credits)
        {
            if (credits == null || (credits.HasCredits.HasValue && !credits.HasCredits.Value))
            {
                return "未启用";
            }
            if (credits.Unlimited.HasValue && credits.Unlimited.Value)
            {
                return "无限";
            }
            if (String.IsNullOrWhiteSpace(credits.Balance))
            {
                return "可用";
            }

            decimal balance;
            if (Decimal.TryParse(credits.Balance, NumberStyles.Any, CultureInfo.InvariantCulture, out balance))
            {
                return balance.ToString("N2", CultureInfo.CurrentCulture);
            }
            return credits.Balance;
        }

        public static string FormatPlan(string planType)
        {
            if (String.IsNullOrWhiteSpace(planType))
            {
                return "未知套餐";
            }

            switch (planType.Trim().ToLowerInvariant())
            {
                case "plus": return "ChatGPT Plus";
                case "pro": return "ChatGPT Pro";
                case "team": return "ChatGPT Team";
                case "business": return "ChatGPT Business";
                case "enterprise": return "ChatGPT Enterprise";
                case "edu": return "ChatGPT Edu";
                default: return planType;
            }
        }

        public static string FormatCapturedAt(QuotaSnapshot snapshot)
        {
            if (snapshot == null || snapshot.CapturedAt == default(DateTimeOffset))
            {
                return "尚未更新";
            }
            return snapshot.CapturedAt.ToLocalTime().ToString("MM-dd HH:mm:ss", CultureInfo.CurrentCulture);
        }
    }

    public sealed class BallAppearanceSettings
    {
        public double Size { get; set; }
        public Color AccentColor { get; set; }
    }

    public static class AppSettings
    {
        private const string RunValueName = "Token Orb";
        private const string LegacyRunValueName = "CodexQuotaBall";
#if QA
        private const string WatcherExitEventName = "Local\\CodexQuotaBall.QA.WatcherExit";
        private const string UiExitEventName = "Local\\CodexQuotaBall.QA.UiExit";
        private const string UiShowEventName = "Local\\CodexQuotaBall.QA.UiShow";
        private const string UiHideEventName = "Local\\CodexQuotaBall.QA.UiHide";
        private const string UiVisibleStateEventName = "Local\\CodexQuotaBall.QA.UiVisible";
#else
        private const string WatcherExitEventName = "Local\\CodexQuotaBall.WatcherExit";
        private const string UiExitEventName = "Local\\CodexQuotaBall.UiExit";
        private const string UiShowEventName = "Local\\CodexQuotaBall.UiShow";
        private const string UiHideEventName = "Local\\CodexQuotaBall.UiHide";
        private const string UiVisibleStateEventName = "Local\\CodexQuotaBall.UiVisible";
#endif
        private const long MaximumRealtimeErrorLogBytes = 1024 * 1024;
        private static readonly object RealtimeErrorLogLock = new object();

        private static string AppDataDirectory
        {
            get
            {
                return Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
#if QA
                    "Token Orb-QA");
#else
                    "Token Orb");
#endif
            }
        }

        private static string LegacyAppDataDirectory
        {
            get
            {
                return Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
#if QA
                    "CodexQuotaBall-QA");
#else
                    "CodexQuotaBall");
#endif
            }
        }

        private static string PositionFile
        {
            get { return Path.Combine(AppDataDirectory, "position.txt"); }
        }

        private static string AppearanceFile
        {
            get { return Path.Combine(AppDataDirectory, "appearance.txt"); }
        }

        private static string FollowCodexFile
        {
            get { return Path.Combine(AppDataDirectory, "follow-codex.txt"); }
        }

        private static string FindReadableSettingsFile(string fileName)
        {
            string current = Path.Combine(AppDataDirectory, fileName);
            if (File.Exists(current))
            {
                return current;
            }

            string legacy = Path.Combine(LegacyAppDataDirectory, fileName);
            return File.Exists(legacy) ? legacy : current;
        }

        public static BallAppearanceSettings LoadAppearance()
        {
            BallAppearanceSettings settings = new BallAppearanceSettings
            {
                Size = QuotaBallVisual.DefaultDiameter,
                AccentColor = UiPalette.Blue
            };

            try
            {
                string path = FindReadableSettingsFile("appearance.txt");
                if (!File.Exists(path))
                {
                    return settings;
                }

                string[] parts = File.ReadAllText(path).Split('|');
                double size;
                Color color;
                if (parts.Length >= 1
                    && Double.TryParse(parts[0], NumberStyles.Float, CultureInfo.InvariantCulture, out size))
                {
                    settings.Size = Math.Max(
                        QuotaBallVisual.MinimumDiameter,
                        Math.Min(size, QuotaBallVisual.MaximumDiameter));
                }
                if (parts.Length >= 2 && TryParseColor(parts[1], out color))
                {
                    settings.AccentColor = color;
                }
            }
            catch { }
            return settings;
        }

        public static void SaveAppearance(double size, Color color)
        {
            try
            {
                Directory.CreateDirectory(AppDataDirectory);
                double safeSize = Math.Max(
                    QuotaBallVisual.MinimumDiameter,
                    Math.Min(size, QuotaBallVisual.MaximumDiameter));
                string value = safeSize.ToString("0", CultureInfo.InvariantCulture)
                    + "|#"
                    + color.R.ToString("X2", CultureInfo.InvariantCulture)
                    + color.G.ToString("X2", CultureInfo.InvariantCulture)
                    + color.B.ToString("X2", CultureInfo.InvariantCulture);
                File.WriteAllText(AppearanceFile, value);
            }
            catch { }
        }

        private static bool TryParseColor(string text, out Color color)
        {
            color = UiPalette.Blue;
            if (String.IsNullOrWhiteSpace(text))
            {
                return false;
            }

            string value = text.Trim().TrimStart('#');
            if (value.Length != 6)
            {
                return false;
            }

            byte red;
            byte green;
            byte blue;
            if (!Byte.TryParse(value.Substring(0, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out red)
                || !Byte.TryParse(value.Substring(2, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out green)
                || !Byte.TryParse(value.Substring(4, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out blue))
            {
                return false;
            }
            color = Color.FromRgb(red, green, blue);
            return true;
        }

        public static bool TryLoadPosition(out double left, out double top)
        {
            left = 0.0;
            top = 0.0;
            try
            {
                string path = FindReadableSettingsFile("position.txt");
                if (!File.Exists(path))
                {
                    return false;
                }
                string[] parts = File.ReadAllText(path).Split('|');
                return parts.Length == 2
                    && Double.TryParse(parts[0], NumberStyles.Float, CultureInfo.InvariantCulture, out left)
                    && Double.TryParse(parts[1], NumberStyles.Float, CultureInfo.InvariantCulture, out top);
            }
            catch
            {
                return false;
            }
        }

        public static void SavePosition(double left, double top)
        {
            try
            {
                Directory.CreateDirectory(AppDataDirectory);
                File.WriteAllText(
                    PositionFile,
                    left.ToString("R", CultureInfo.InvariantCulture)
                        + "|" + top.ToString("R", CultureInfo.InvariantCulture));
            }
            catch { }
        }

        public static bool IsAutoStartEnabled()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(
                    "Software\\Microsoft\\Windows\\CurrentVersion\\Run",
                    false))
                {
                    return key != null
                        && (key.GetValue(RunValueName) != null
                            || key.GetValue(LegacyRunValueName) != null);
                }
            }
            catch
            {
                return false;
            }
        }

        public static bool IsFollowCodexEnabled()
        {
            try
            {
                string path = FindReadableSettingsFile("follow-codex.txt");
                if (!File.Exists(path))
                {
                    return true;
                }
                return !String.Equals(
                    File.ReadAllText(path).Trim(),
                    "0",
                    StringComparison.OrdinalIgnoreCase);
            }
            catch
            {
                return true;
            }
        }

        public static void InitializeFollowCodexDefault()
        {
            string legacyPreference = Path.Combine(
                LegacyAppDataDirectory,
                "follow-codex.txt");
            if (!FollowCodexStartupBehavior.ShouldCreateDefaultPreference(
                File.Exists(FollowCodexFile),
                File.Exists(legacyPreference)))
            {
                return;
            }

            Directory.CreateDirectory(AppDataDirectory);
            File.WriteAllText(FollowCodexFile, "1");
        }

        public static void EnsureFollowCodexRegistration()
        {
            if (IsFollowCodexEnabled())
            {
                SetAutoStart(true);
            }
        }

        public static void SetFollowCodexEnabled(bool enabled)
        {
            SetAutoStart(enabled);
            Directory.CreateDirectory(AppDataDirectory);
            File.WriteAllText(FollowCodexFile, enabled ? "1" : "0");
        }

        public static EventWaitHandle CreateWatcherExitEvent()
        {
            return new EventWaitHandle(false, EventResetMode.AutoReset, WatcherExitEventName);
        }

        public static EventWaitHandle CreateUiExitEvent()
        {
            return new EventWaitHandle(false, EventResetMode.AutoReset, UiExitEventName);
        }

        public static EventWaitHandle CreateUiShowEvent()
        {
            return new EventWaitHandle(false, EventResetMode.AutoReset, UiShowEventName);
        }

        public static EventWaitHandle CreateUiHideEvent()
        {
            return new EventWaitHandle(false, EventResetMode.AutoReset, UiHideEventName);
        }

        public static EventWaitHandle CreateUiVisibleStateEvent()
        {
            return new EventWaitHandle(false, EventResetMode.ManualReset, UiVisibleStateEventName);
        }

        public static void SignalWatcherExit()
        {
            try
            {
                using (EventWaitHandle exit = EventWaitHandle.OpenExisting(WatcherExitEventName))
                {
                    exit.Set();
                }
            }
            catch (WaitHandleCannotBeOpenedException) { }
            catch { }
        }

        public static void StartWatcherProcess()
        {
            string executable = Assembly.GetExecutingAssembly().Location;
            Process process = Process.Start(new ProcessStartInfo
            {
                FileName = executable,
                Arguments = "--watch",
                WorkingDirectory = Path.GetDirectoryName(executable) ?? Environment.CurrentDirectory,
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            });
            if (process != null)
            {
                process.Dispose();
            }
        }

        public static void SetAutoStart(bool enabled)
        {
            using (RegistryKey key = Registry.CurrentUser.CreateSubKey(
                "Software\\Microsoft\\Windows\\CurrentVersion\\Run"))
            {
                if (key == null)
                {
                    throw new InvalidOperationException("无法打开 Windows 启动项注册表。");
                }

                if (enabled)
                {
                    string executable = Assembly.GetExecutingAssembly().Location;
                    key.SetValue(RunValueName, "\"" + executable + "\" --watch");
                }
                else
                {
                    key.DeleteValue(RunValueName, false);
                }
                key.DeleteValue(LegacyRunValueName, false);
            }
        }

        public static void LogError(Exception exception)
        {
            try
            {
                Directory.CreateDirectory(AppDataDirectory);
                string path = Path.Combine(AppDataDirectory, "error.log");
                File.AppendAllText(
                    path,
                    DateTimeOffset.Now.ToString("u", CultureInfo.InvariantCulture)
                        + Environment.NewLine
                        + exception.ToString()
                        + Environment.NewLine
                        + Environment.NewLine);
            }
            catch { }
        }

        public static void LogRealtimeError(string operation, string details)
        {
            try
            {
                Directory.CreateDirectory(AppDataDirectory);
                string path = Path.Combine(AppDataDirectory, "realtime-errors.log");
                string previousPath = Path.Combine(AppDataDirectory, "realtime-errors.previous.log");
                string safeOperation = SanitizeRealtimeLogValue(operation, 120);
                string safeDetails = SanitizeRealtimeLogValue(details, 2000);
                string line = DateTimeOffset.Now.ToString("u", CultureInfo.InvariantCulture)
                    + " [" + safeOperation + "] " + safeDetails + Environment.NewLine;

                lock (RealtimeErrorLogLock)
                {
                    FileInfo current = new FileInfo(path);
                    if (current.Exists && current.Length >= MaximumRealtimeErrorLogBytes)
                    {
                        if (File.Exists(previousPath))
                        {
                            File.Delete(previousPath);
                        }
                        File.Move(path, previousPath);
                    }
                    File.AppendAllText(path, line);
                }
            }
            catch { }
        }

        private static string SanitizeRealtimeLogValue(string value, int maximumLength)
        {
            string text = String.IsNullOrWhiteSpace(value) ? "unknown" : value.Trim();
            text = text.Replace('\r', ' ').Replace('\n', ' ').Replace('\t', ' ');

            string userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            if (!String.IsNullOrWhiteSpace(userProfile))
            {
                int index = text.IndexOf(userProfile, StringComparison.OrdinalIgnoreCase);
                while (index >= 0)
                {
                    text = text.Substring(0, index)
                        + "%USERPROFILE%"
                        + text.Substring(index + userProfile.Length);
                    index = text.IndexOf(userProfile, StringComparison.OrdinalIgnoreCase);
                }
            }

            return text.Length <= maximumLength ? text : text.Substring(0, maximumLength) + "…";
        }

    }
}
