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
        private const int WeeklyWindowMinutes = 7 * 24 * 60;
        private static readonly TimeSpan WeeklyResetInterval = TimeSpan.FromDays(7.0);

        public static DateTimeOffset? ResolveResetAt(
            QuotaWindowInfo window,
            DateTimeOffset now)
        {
            if (window == null || !window.ResetsAtUnix.HasValue)
            {
                return null;
            }

            DateTimeOffset resetUtc = UnixTime
                .ToDateTimeOffset(window.ResetsAtUnix.Value)
                .ToUniversalTime();
            DateTimeOffset nowUtc = now.ToUniversalTime();
            if (window.WindowMinutes == WeeklyWindowMinutes && resetUtc <= nowUtc)
            {
                long elapsedTicks = (nowUtc - resetUtc).Ticks;
                long cycles = elapsedTicks / WeeklyResetInterval.Ticks + 1L;
                try
                {
                    resetUtc = resetUtc.AddTicks(checked(cycles * WeeklyResetInterval.Ticks));
                }
                catch (ArgumentOutOfRangeException)
                {
                    return resetUtc.ToLocalTime();
                }
                catch (OverflowException)
                {
                    return resetUtc.ToLocalTime();
                }
            }

            return resetUtc.ToLocalTime();
        }

        public static string FormatResetDate(
            QuotaWindowInfo window,
            DateTimeOffset now)
        {
            DateTimeOffset? reset = ResolveResetAt(window, now);
            return reset.HasValue
                ? reset.Value.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.CurrentCulture)
                : "时间未知";
        }

        public static string FormatResetCountdown(
            QuotaWindowInfo window,
            DateTimeOffset now)
        {
            DateTimeOffset? reset = ResolveResetAt(window, now);
            if (!reset.HasValue)
            {
                return String.Empty;
            }

            TimeSpan remaining = reset.Value - now.ToLocalTime();
            if (remaining.TotalSeconds <= 0)
            {
                return "等待 Codex 刷新";
            }
            if (remaining.TotalDays >= 1.0)
            {
                return ((int)remaining.TotalDays).ToString(CultureInfo.InvariantCulture)
                    + "天"
                    + remaining.Hours.ToString(CultureInfo.InvariantCulture)
                    + "小时后";
            }
            if (remaining.TotalHours >= 1.0)
            {
                return ((int)remaining.TotalHours).ToString(CultureInfo.InvariantCulture)
                    + "小时"
                    + remaining.Minutes.ToString(CultureInfo.InvariantCulture)
                    + "分后";
            }

            return Math.Max(0, remaining.Minutes).ToString(CultureInfo.InvariantCulture)
                + "分"
                + Math.Max(0, remaining.Seconds).ToString(CultureInfo.InvariantCulture)
                + "秒后";
        }

        public static string FormatCredits(QuotaCreditsInfo credits)
        {
            if (credits == null || (credits.HasCredits.HasValue && !credits.HasCredits.Value))
            {
                return "0";
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
            return snapshot.CapturedAt.ToLocalTime().ToString(
                "yyyy-MM-dd HH:mm:ss",
                CultureInfo.CurrentCulture);
        }

        public static string FormatDataSource(QuotaSnapshot snapshot)
        {
            return snapshot != null && snapshot.IsLive ? "实时数据" : "本地快照";
        }
    }

    public enum QuotaTextStyle
    {
        Minimal,
        Geometric,
        Condensed,
        Rounded,
        Emphasis
    }

    public static class QuotaTextStyleCatalog
    {
        public static QuotaTextStyle Default
        {
            get { return QuotaTextStyle.Minimal; }
        }

        public static QuotaTextStyle Normalize(QuotaTextStyle style)
        {
            switch (style)
            {
                case QuotaTextStyle.Minimal:
                case QuotaTextStyle.Geometric:
                case QuotaTextStyle.Condensed:
                case QuotaTextStyle.Rounded:
                case QuotaTextStyle.Emphasis:
                    return style;
                default:
                    return Default;
            }
        }

        public static QuotaTextStyle Parse(string value)
        {
            if (String.IsNullOrWhiteSpace(value))
            {
                return Default;
            }

            switch (value.Trim().ToLowerInvariant())
            {
                case "minimal": return QuotaTextStyle.Minimal;
                case "geometric": return QuotaTextStyle.Geometric;
                case "condensed": return QuotaTextStyle.Condensed;
                case "rounded": return QuotaTextStyle.Rounded;
                case "emphasis": return QuotaTextStyle.Emphasis;
                default: return Default;
            }
        }

        public static string ToStorageValue(QuotaTextStyle style)
        {
            switch (Normalize(style))
            {
                case QuotaTextStyle.Geometric: return "geometric";
                case QuotaTextStyle.Condensed: return "condensed";
                case QuotaTextStyle.Rounded: return "rounded";
                case QuotaTextStyle.Emphasis: return "emphasis";
                default: return "minimal";
            }
        }

        public static string GetDisplayName(QuotaTextStyle style)
        {
            switch (Normalize(style))
            {
                case QuotaTextStyle.Geometric: return "Aureole";
                case QuotaTextStyle.Condensed: return "Spear";
                case QuotaTextStyle.Rounded: return "Pearl";
                case QuotaTextStyle.Emphasis: return "Thunder";
                default: return "Wing";
            }
        }
    }

    public static class AnimationFrameRateCatalog
    {
        public const int Default = 60;

        public static int[] GetOptions()
        {
            return new int[] { 30, 60, 90, 120, 180 };
        }

        public static int Normalize(int frameRate)
        {
            switch (frameRate)
            {
                case 30:
                case 60:
                case 90:
                case 120:
                case 180:
                    return frameRate;
                default:
                    return Default;
            }
        }
    }

    public sealed class BallAppearanceSettings
    {
        public double Size { get; set; }
        public Color AccentColor { get; set; }
        public QuotaTextStyle TextStyle { get; set; }
        public int AnimationFrameRate { get; set; }
    }

    // Used only when no saved appearance exists, so upgrades keep user choices.
    public static class BallAppearanceDefaults
    {
        public const double Size = 65.0;
        public const string AccentHex = "#2FA4EB";
        public const QuotaTextStyle TextStyle = QuotaTextStyle.Condensed;
        public const int AnimationFrameRate = 60;

        public static Color AccentColor
        {
            get { return Color.FromRgb(47, 164, 235); }
        }

        public static BallAppearanceSettings Create()
        {
            return new BallAppearanceSettings
            {
                Size = Size,
                AccentColor = AccentColor,
                TextStyle = TextStyle,
                AnimationFrameRate = AnimationFrameRate
            };
        }
    }

    public static class WindowSwitcherVisibilityPolicy
    {
        public const int ToolWindowExtendedStyle = 0x00000080;
        public const int ApplicationWindowExtendedStyle = 0x00040000;

        public static int HideFromSwitcher(int extendedStyle)
        {
            return (extendedStyle | ToolWindowExtendedStyle)
                & ~ApplicationWindowExtendedStyle;
        }
    }

    public static class AppSettings
    {
        private const string RunValueName = "TokenOrb";
        private const string PreviousRunValueName = "Token Orb";
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
                    "TokenOrb-QA");
#else
                    "TokenOrb");
#endif
            }
        }

        private static string[] PreviousAppDataDirectories
        {
            get
            {
                string localApplicationData = Environment.GetFolderPath(
                    Environment.SpecialFolder.LocalApplicationData);
                return new string[]
                {
                    Path.Combine(
                        localApplicationData,
#if QA
                        "Token Orb-QA"),
#else
                        "Token Orb"),
#endif
                    Path.Combine(
                        localApplicationData,
#if QA
                        "CodexQuotaBall-QA")
#else
                        "CodexQuotaBall")
#endif
                };
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

            foreach (string directory in PreviousAppDataDirectories)
            {
                string previous = Path.Combine(directory, fileName);
                if (File.Exists(previous))
                {
                    return previous;
                }
            }
            return current;
        }

        private static bool HasPreviousSettingsFile(string fileName)
        {
            foreach (string directory in PreviousAppDataDirectories)
            {
                if (File.Exists(Path.Combine(directory, fileName)))
                {
                    return true;
                }
            }
            return false;
        }

        public static BallAppearanceSettings LoadAppearance()
        {
            BallAppearanceSettings settings = BallAppearanceDefaults.Create();

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
                if (parts.Length >= 3)
                {
                    settings.TextStyle = QuotaTextStyleCatalog.Parse(parts[2]);
                }
                int frameRate;
                if (parts.Length >= 4
                    && Int32.TryParse(
                        parts[3],
                        NumberStyles.Integer,
                        CultureInfo.InvariantCulture,
                        out frameRate))
                {
                    settings.AnimationFrameRate = AnimationFrameRateCatalog.Normalize(frameRate);
                }
            }
            catch { }
            return settings;
        }

        public static void SaveAppearance(
            double size,
            Color color,
            QuotaTextStyle textStyle,
            int animationFrameRate)
        {
            try
            {
                Directory.CreateDirectory(AppDataDirectory);
                File.WriteAllText(
                    AppearanceFile,
                    FormatAppearanceValue(size, color, textStyle, animationFrameRate));
            }
            catch { }
        }

        internal static string FormatAppearanceValue(
            double size,
            Color color,
            QuotaTextStyle textStyle,
            int animationFrameRate)
        {
            double safeSize = Math.Max(
                QuotaBallVisual.MinimumDiameter,
                Math.Min(size, QuotaBallVisual.MaximumDiameter));
            return safeSize.ToString("0", CultureInfo.InvariantCulture)
                + "|#"
                + color.R.ToString("X2", CultureInfo.InvariantCulture)
                + color.G.ToString("X2", CultureInfo.InvariantCulture)
                + color.B.ToString("X2", CultureInfo.InvariantCulture)
                + "|"
                + QuotaTextStyleCatalog.ToStorageValue(textStyle)
                + "|"
                + AnimationFrameRateCatalog.Normalize(animationFrameRate)
                    .ToString(CultureInfo.InvariantCulture);
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
            if (!FollowCodexStartupBehavior.ShouldCreateDefaultPreference(
                File.Exists(FollowCodexFile),
                HasPreviousSettingsFile("follow-codex.txt")))
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
                key.DeleteValue(PreviousRunValueName, false);
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
