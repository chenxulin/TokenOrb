using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Web.Script.Serialization;

namespace CodexQuotaBall
{
    public sealed class QuotaWindowInfo
    {
        public double? UsedPercent { get; set; }
        public int? WindowMinutes { get; set; }
        public long? ResetsAtUnix { get; set; }

        public bool IsMeaningful
        {
            get { return UsedPercent.HasValue || WindowMinutes.HasValue || ResetsAtUnix.HasValue; }
        }

        public double RemainingPercent
        {
            get
            {
                double used = UsedPercent.HasValue ? UsedPercent.Value : 0.0;
                return Math.Max(0.0, Math.Min(100.0, 100.0 - used));
            }
        }

        public QuotaWindowInfo Clone()
        {
            return new QuotaWindowInfo
            {
                UsedPercent = UsedPercent,
                WindowMinutes = WindowMinutes,
                ResetsAtUnix = ResetsAtUnix
            };
        }

        public static QuotaWindowInfo Merge(QuotaWindowInfo current, QuotaWindowInfo update)
        {
            if (current == null)
            {
                return update == null ? null : update.Clone();
            }

            if (update == null)
            {
                return current.Clone();
            }

            return new QuotaWindowInfo
            {
                UsedPercent = update.UsedPercent.HasValue ? update.UsedPercent : current.UsedPercent,
                WindowMinutes = update.WindowMinutes.HasValue ? update.WindowMinutes : current.WindowMinutes,
                ResetsAtUnix = update.ResetsAtUnix.HasValue ? update.ResetsAtUnix : current.ResetsAtUnix
            };
        }
    }

    public sealed class QuotaCreditsInfo
    {
        public bool? HasCredits { get; set; }
        public bool? Unlimited { get; set; }
        public string Balance { get; set; }

        public QuotaCreditsInfo Clone()
        {
            return new QuotaCreditsInfo
            {
                HasCredits = HasCredits,
                Unlimited = Unlimited,
                Balance = Balance
            };
        }

        public static QuotaCreditsInfo Merge(QuotaCreditsInfo current, QuotaCreditsInfo update)
        {
            if (current == null)
            {
                return update == null ? null : update.Clone();
            }

            if (update == null)
            {
                return current.Clone();
            }

            return new QuotaCreditsInfo
            {
                HasCredits = update.HasCredits.HasValue ? update.HasCredits : current.HasCredits,
                Unlimited = update.Unlimited.HasValue ? update.Unlimited : current.Unlimited,
                Balance = !String.IsNullOrWhiteSpace(update.Balance) ? update.Balance : current.Balance
            };
        }
    }

    public sealed class QuotaSnapshot
    {
        public string LimitId { get; set; }
        public string LimitName { get; set; }
        public QuotaWindowInfo Primary { get; set; }
        public QuotaWindowInfo Secondary { get; set; }
        public QuotaCreditsInfo Credits { get; set; }
        public string PlanType { get; set; }
        public string RateLimitReachedType { get; set; }
        public bool? SpendControlReached { get; set; }
        public DateTimeOffset CapturedAt { get; set; }
        public string Source { get; set; }
        public bool IsLive { get; set; }

        public bool HasQuotaData
        {
            get
            {
                return (Primary != null && Primary.IsMeaningful)
                    || (Secondary != null && Secondary.IsMeaningful)
                    || Credits != null;
            }
        }

        public QuotaWindowInfo MostRestrictiveWindow
        {
            get
            {
                List<QuotaWindowInfo> windows = new List<QuotaWindowInfo>();
                if (Primary != null && Primary.UsedPercent.HasValue)
                {
                    windows.Add(Primary);
                }
                if (Secondary != null && Secondary.UsedPercent.HasValue)
                {
                    windows.Add(Secondary);
                }

                if (windows.Count == 0)
                {
                    return null;
                }

                return windows
                    .OrderBy(w => w.RemainingPercent)
                    .ThenBy(w => w.WindowMinutes.HasValue ? w.WindowMinutes.Value : Int32.MaxValue)
                    .First();
            }
        }

        public QuotaSnapshot Clone()
        {
            return new QuotaSnapshot
            {
                LimitId = LimitId,
                LimitName = LimitName,
                Primary = Primary == null ? null : Primary.Clone(),
                Secondary = Secondary == null ? null : Secondary.Clone(),
                Credits = Credits == null ? null : Credits.Clone(),
                PlanType = PlanType,
                RateLimitReachedType = RateLimitReachedType,
                SpendControlReached = SpendControlReached,
                CapturedAt = CapturedAt,
                Source = Source,
                IsLive = IsLive
            };
        }

        public QuotaSnapshot MergeSparse(QuotaSnapshot update)
        {
            if (update == null)
            {
                return Clone();
            }

            return new QuotaSnapshot
            {
                LimitId = !String.IsNullOrWhiteSpace(update.LimitId) ? update.LimitId : LimitId,
                LimitName = !String.IsNullOrWhiteSpace(update.LimitName) ? update.LimitName : LimitName,
                Primary = QuotaWindowInfo.Merge(Primary, update.Primary),
                Secondary = QuotaWindowInfo.Merge(Secondary, update.Secondary),
                Credits = QuotaCreditsInfo.Merge(Credits, update.Credits),
                PlanType = !String.IsNullOrWhiteSpace(update.PlanType) ? update.PlanType : PlanType,
                RateLimitReachedType = !String.IsNullOrWhiteSpace(update.RateLimitReachedType)
                    ? update.RateLimitReachedType
                    : RateLimitReachedType,
                SpendControlReached = update.SpendControlReached.HasValue
                    ? update.SpendControlReached
                    : SpendControlReached,
                CapturedAt = update.CapturedAt == default(DateTimeOffset) ? CapturedAt : update.CapturedAt,
                Source = !String.IsNullOrWhiteSpace(update.Source) ? update.Source : Source,
                IsLive = update.IsLive || IsLive
            };
        }

        public static string FormatWindowName(QuotaWindowInfo window)
        {
            if (window == null || !window.WindowMinutes.HasValue)
            {
                return "额度";
            }

            int minutes = window.WindowMinutes.Value;
            if (minutes == 300)
            {
                return "5小时";
            }
            if (minutes == 10080)
            {
                return "7天";
            }
            if (minutes > 0 && minutes % 1440 == 0)
            {
                return (minutes / 1440).ToString(CultureInfo.InvariantCulture) + "天";
            }
            if (minutes > 0 && minutes % 60 == 0)
            {
                return (minutes / 60).ToString(CultureInfo.InvariantCulture) + "小时";
            }
            return minutes.ToString(CultureInfo.InvariantCulture) + "分钟";
        }
    }

    public static class QuotaJsonParser
    {
        private static JavaScriptSerializer CreateSerializer()
        {
            JavaScriptSerializer serializer = new JavaScriptSerializer();
            serializer.MaxJsonLength = Int32.MaxValue;
            serializer.RecursionLimit = 100;
            return serializer;
        }

        public static IDictionary<string, object> ParseObject(string json)
        {
            if (String.IsNullOrWhiteSpace(json))
            {
                return null;
            }

            try
            {
                return CreateSerializer().DeserializeObject(json) as IDictionary<string, object>;
            }
            catch
            {
                return null;
            }
        }

        public static QuotaSnapshot ParseLocalEventLine(string jsonLine)
        {
            IDictionary<string, object> root = ParseObject(jsonLine);
            if (root == null)
            {
                return null;
            }

            IDictionary<string, object> payload = AsDictionary(GetAny(root, "payload"));
            if (payload == null)
            {
                return null;
            }

            object payloadType = GetAny(payload, "type");
            if (payloadType != null && !String.Equals(Convert.ToString(payloadType, CultureInfo.InvariantCulture), "token_count", StringComparison.OrdinalIgnoreCase))
            {
                return null;
            }

            IDictionary<string, object> limits = AsDictionary(GetAny(payload, "rate_limits", "rateLimits"));
            if (limits == null)
            {
                return null;
            }

            QuotaSnapshot snapshot = FromRateLimitsDictionary(limits, "本地会话快照", false);
            DateTimeOffset timestamp;
            if (TryParseTimestamp(GetAny(root, "timestamp"), out timestamp))
            {
                snapshot.CapturedAt = timestamp;
            }
            return snapshot;
        }

        public static QuotaSnapshot FromRateLimitsDictionary(
            IDictionary<string, object> limits,
            string source,
            bool isLive)
        {
            if (limits == null)
            {
                return null;
            }

            QuotaSnapshot snapshot = new QuotaSnapshot();
            snapshot.LimitId = AsString(GetAny(limits, "limitId", "limit_id"));
            snapshot.LimitName = AsString(GetAny(limits, "limitName", "limit_name"));
            snapshot.Primary = ParseWindow(AsDictionary(GetAny(limits, "primary")));
            snapshot.Secondary = ParseWindow(AsDictionary(GetAny(limits, "secondary")));
            snapshot.Credits = ParseCredits(AsDictionary(GetAny(limits, "credits")));
            snapshot.PlanType = AsString(GetAny(limits, "planType", "plan_type"));
            snapshot.RateLimitReachedType = AsString(GetAny(limits, "rateLimitReachedType", "rate_limit_reached_type"));
            snapshot.SpendControlReached = AsNullableBoolean(GetAny(limits, "spendControlReached", "spend_control_reached"));
            snapshot.CapturedAt = DateTimeOffset.Now;
            snapshot.Source = source;
            snapshot.IsLive = isLive;
            return snapshot;
        }

        private static QuotaWindowInfo ParseWindow(IDictionary<string, object> data)
        {
            if (data == null)
            {
                return null;
            }

            QuotaWindowInfo window = new QuotaWindowInfo();
            window.UsedPercent = AsNullableDouble(GetAny(data, "usedPercent", "used_percent"));
            window.WindowMinutes = AsNullableInt(GetAny(data, "windowDurationMins", "window_minutes", "windowMinutes"));
            window.ResetsAtUnix = AsNullableLong(GetAny(data, "resetsAt", "resets_at"));
            return window.IsMeaningful ? window : null;
        }

        private static QuotaCreditsInfo ParseCredits(IDictionary<string, object> data)
        {
            if (data == null)
            {
                return null;
            }

            return new QuotaCreditsInfo
            {
                HasCredits = AsNullableBoolean(GetAny(data, "hasCredits", "has_credits")),
                Unlimited = AsNullableBoolean(GetAny(data, "unlimited")),
                Balance = AsString(GetAny(data, "balance"))
            };
        }

        public static IDictionary<string, object> AsDictionary(object value)
        {
            return value as IDictionary<string, object>;
        }

        public static object GetAny(IDictionary<string, object> data, params string[] keys)
        {
            if (data == null || keys == null)
            {
                return null;
            }

            foreach (string key in keys)
            {
                object value;
                if (data.TryGetValue(key, out value))
                {
                    return value;
                }
            }
            return null;
        }

        public static string AsString(object value)
        {
            if (value == null)
            {
                return null;
            }
            string text = Convert.ToString(value, CultureInfo.InvariantCulture);
            return String.IsNullOrWhiteSpace(text) ? null : text;
        }

        public static double? AsNullableDouble(object value)
        {
            if (value == null)
            {
                return null;
            }

            try
            {
                return Convert.ToDouble(value, CultureInfo.InvariantCulture);
            }
            catch
            {
                double parsed;
                return Double.TryParse(Convert.ToString(value, CultureInfo.InvariantCulture), NumberStyles.Any, CultureInfo.InvariantCulture, out parsed)
                    ? (double?)parsed
                    : null;
            }
        }

        public static int? AsNullableInt(object value)
        {
            double? number = AsNullableDouble(value);
            if (!number.HasValue)
            {
                return null;
            }
            return Convert.ToInt32(Math.Round(number.Value), CultureInfo.InvariantCulture);
        }

        public static long? AsNullableLong(object value)
        {
            if (value == null)
            {
                return null;
            }

            try
            {
                return Convert.ToInt64(value, CultureInfo.InvariantCulture);
            }
            catch
            {
                long parsed;
                return Int64.TryParse(Convert.ToString(value, CultureInfo.InvariantCulture), NumberStyles.Any, CultureInfo.InvariantCulture, out parsed)
                    ? (long?)parsed
                    : null;
            }
        }

        public static bool? AsNullableBoolean(object value)
        {
            if (value == null)
            {
                return null;
            }

            if (value is bool)
            {
                return (bool)value;
            }

            bool parsed;
            return Boolean.TryParse(Convert.ToString(value, CultureInfo.InvariantCulture), out parsed)
                ? (bool?)parsed
                : null;
        }

        private static bool TryParseTimestamp(object value, out DateTimeOffset timestamp)
        {
            timestamp = default(DateTimeOffset);
            if (value == null)
            {
                return false;
            }

            long unix;
            if (Int64.TryParse(Convert.ToString(value, CultureInfo.InvariantCulture), NumberStyles.Integer, CultureInfo.InvariantCulture, out unix))
            {
                timestamp = UnixTime.ToDateTimeOffset(unix);
                return true;
            }

            return DateTimeOffset.TryParse(
                Convert.ToString(value, CultureInfo.InvariantCulture),
                CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal,
                out timestamp);
        }
    }

    public static class UnixTime
    {
        private static readonly DateTimeOffset Epoch = new DateTimeOffset(1970, 1, 1, 0, 0, 0, TimeSpan.Zero);

        public static DateTimeOffset ToDateTimeOffset(long seconds)
        {
            try
            {
                return Epoch.AddSeconds(seconds);
            }
            catch
            {
                return Epoch;
            }
        }
    }

    public sealed class SessionQuotaReader
    {
        private const int TailBytes = 2 * 1024 * 1024;
        private readonly string sessionsRoot;

        public SessionQuotaReader(string sessionsRoot)
        {
            this.sessionsRoot = sessionsRoot;
        }

        public string SessionsRoot
        {
            get { return sessionsRoot; }
        }

        public static string FindSessionsRoot()
        {
            return Path.Combine(FindCodexHome(), "sessions");
        }

        public static string FindCodexHome()
        {
            string codexHome = Environment.GetEnvironmentVariable("CODEX_HOME");
            if (String.IsNullOrWhiteSpace(codexHome))
            {
                codexHome = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                    ".codex");
            }
            return codexHome;
        }

        public QuotaSnapshot LoadLatest()
        {
            if (String.IsNullOrWhiteSpace(sessionsRoot) || !Directory.Exists(sessionsRoot))
            {
                return null;
            }

            FileInfo[] files;
            try
            {
                files = new DirectoryInfo(sessionsRoot)
                    .GetFiles("rollout-*.jsonl", SearchOption.AllDirectories)
                    .OrderByDescending(f => f.LastWriteTimeUtc)
                    .Take(12)
                    .ToArray();
            }
            catch
            {
                return null;
            }

            QuotaSnapshot newest = null;
            foreach (FileInfo file in files)
            {
                QuotaSnapshot candidate = ReadLatestFromFile(file);
                if (candidate == null)
                {
                    continue;
                }

                if (candidate.CapturedAt == default(DateTimeOffset))
                {
                    candidate.CapturedAt = new DateTimeOffset(file.LastWriteTimeUtc, TimeSpan.Zero);
                }

                if (newest == null || candidate.CapturedAt > newest.CapturedAt)
                {
                    newest = candidate;
                }
            }
            return newest;
        }

        private static QuotaSnapshot ReadLatestFromFile(FileInfo file)
        {
            try
            {
                using (FileStream stream = new FileStream(
                    file.FullName,
                    FileMode.Open,
                    FileAccess.Read,
                    FileShare.ReadWrite | FileShare.Delete))
                {
                    long start = Math.Max(0L, stream.Length - TailBytes);
                    stream.Seek(start, SeekOrigin.Begin);
                    int length = Convert.ToInt32(stream.Length - start);
                    byte[] bytes = new byte[length];
                    int offset = 0;
                    while (offset < bytes.Length)
                    {
                        int read = stream.Read(bytes, offset, bytes.Length - offset);
                        if (read <= 0)
                        {
                            break;
                        }
                        offset += read;
                    }

                    string text = Encoding.UTF8.GetString(bytes, 0, offset);
                    if (start > 0)
                    {
                        int firstNewline = text.IndexOf('\n');
                        if (firstNewline >= 0)
                        {
                            text = text.Substring(firstNewline + 1);
                        }
                    }

                    string[] lines = text.Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries);
                    for (int i = lines.Length - 1; i >= 0; i--)
                    {
                        string line = lines[i].TrimEnd('\r');
                        if (line.IndexOf("\"rate_limits\"", StringComparison.OrdinalIgnoreCase) < 0
                            && line.IndexOf("\"rateLimits\"", StringComparison.OrdinalIgnoreCase) < 0)
                        {
                            continue;
                        }

                        QuotaSnapshot snapshot = QuotaJsonParser.ParseLocalEventLine(line);
                        if (snapshot != null && snapshot.HasQuotaData)
                        {
                            return snapshot;
                        }
                    }
                }
            }
            catch
            {
                return null;
            }
            return null;
        }
    }
}
