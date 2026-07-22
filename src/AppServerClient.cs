using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Threading;

namespace CodexQuotaBall
{
    public sealed class CodexAppServerClient : IDisposable
    {
        private readonly object stateLock = new object();
        private readonly object inputLock = new object();
        private readonly HashSet<long> rateLimitRequestIds = new HashSet<long>();
        private readonly RealtimeRetryPolicy retryPolicy = new RealtimeRetryPolicy();
        private Process process;
        private Timer retryTimer;
        private bool initialized;
        private bool authenticationInvalidated;
        private bool hasSuccessfulLiveQuery;
        private bool disposed;
        private int retryGeneration;
        private int processGeneration;
        private int nextRequestId = 10;

        public event Action<QuotaSnapshot, bool, int> SnapshotReceived;
        public event Action<string, bool, int> StatusChanged;

        public bool IsRunning
        {
            get
            {
                lock (stateLock)
                {
                    return process != null && !SafeHasExited(process);
                }
            }
        }

        public bool IsInitialized
        {
            get
            {
                lock (stateLock)
                {
                    return initialized;
                }
            }
        }

        public int CurrentGeneration
        {
            get
            {
                lock (stateLock)
                {
                    return processGeneration;
                }
            }
        }

        public void Start()
        {
            lock (stateLock)
            {
                if (disposed || (process != null && !SafeHasExited(process)))
                {
                    return;
                }

                initialized = false;
                authenticationInvalidated = false;
                processGeneration++;
                ResetQueryStateLocked();
                Process newProcess = new Process();
                try
                {
                    RaiseStatus("正在准备 Codex 实时接口…", false);
                    newProcess.StartInfo = CreateStartInfo();
                    newProcess.EnableRaisingEvents = true;
                    newProcess.OutputDataReceived += OnOutputDataReceived;
                    newProcess.ErrorDataReceived += OnErrorDataReceived;
                    newProcess.Exited += OnProcessExited;
                    if (!newProcess.Start())
                    {
                        throw new InvalidOperationException("Codex app-server 未能启动。");
                    }
                    process = newProcess;
                    newProcess.BeginOutputReadLine();
                    newProcess.BeginErrorReadLine();
                }
                catch (Exception exception)
                {
                    AppSettings.LogRealtimeError(
                        "启动 Codex app-server",
                        exception.GetType().Name + ": " + exception.Message);
                    try { newProcess.Dispose(); } catch { }
                    process = null;
                    RaiseStatus("实时接口不可用，使用本地快照", false);
                    return;
                }
            }

            RaiseStatus("正在连接 Codex 实时接口…", false);
            Exception sendError;
            if (!SendLine(
                "{\"method\":\"initialize\",\"id\":0,\"params\":{\"clientInfo\":{\"name\":\"token_orb\",\"title\":\""
                    + AppIdentity.ProductName + "\",\"version\":\"" + AppIdentity.ProtocolVersion + "\"}}}",
                out sendError))
            {
                AppSettings.LogRealtimeError(
                    "发送 initialize",
                    sendError.GetType().Name + ": " + sendError.Message);
                RaiseStatus("实时接口通信失败，使用本地快照", false);
            }
        }

        public void RequestRefresh()
        {
            RequestRefreshCore(true);
        }

        public void Restart()
        {
            StopProcess();
            Start();
        }

        public void InvalidateAuthentication()
        {
            lock (stateLock)
            {
                if (disposed)
                {
                    return;
                }
                authenticationInvalidated = true;
                initialized = false;
                ResetQueryStateLocked();
            }
        }

        private void RequestRefreshCore(bool cancelScheduledRetry)
        {
            int id;
            lock (stateLock)
            {
                if (disposed || !initialized || process == null || SafeHasExited(process))
                {
                    return;
                }
                if (cancelScheduledRetry)
                {
                    CancelRetryTimerLocked();
                }
                id = Interlocked.Increment(ref nextRequestId);
                rateLimitRequestIds.Add(id);
            }

            Exception sendError;
            if (!SendLine(
                "{\"method\":\"account/rateLimits/read\",\"id\":"
                    + id.ToString(CultureInfo.InvariantCulture) + "}",
                out sendError))
            {
                lock (stateLock)
                {
                    rateLimitRequestIds.Remove(id);
                }
                HandleQueryFailure(
                    id,
                    "send_failed",
                    sendError.GetType().Name + ": " + sendError.Message);
            }
        }

        private void OnRetryTimer(object state)
        {
            int generation = (int)state;
            lock (stateLock)
            {
                if (disposed || !initialized || generation != retryGeneration)
                {
                    return;
                }
                if (retryTimer != null)
                {
                    try { retryTimer.Dispose(); } catch { }
                    retryTimer = null;
                }
            }
            RequestRefreshCore(false);
        }

        private static ProcessStartInfo CreateStartInfo()
        {
            string executable = ResolveCodexExecutable();
            string workingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            if (String.IsNullOrWhiteSpace(workingDirectory) || !Directory.Exists(workingDirectory))
            {
                workingDirectory = Environment.CurrentDirectory;
            }

            return new ProcessStartInfo
            {
                FileName = executable,
                Arguments = "app-server",
                WorkingDirectory = workingDirectory,
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
        }

        private static string ResolveCodexExecutable()
        {
            string configured = Environment.GetEnvironmentVariable("CODEX_QUOTA_CODEX_PATH");
            if (!String.IsNullOrWhiteSpace(configured) && File.Exists(configured))
            {
                return PrepareRunnableExecutable(configured);
            }

            string desktopRuntime = TryFindDesktopRuntimeCodex();
            if (!String.IsNullOrWhiteSpace(desktopRuntime))
            {
                return desktopRuntime;
            }

            string path = Environment.GetEnvironmentVariable("PATH") ?? String.Empty;
            string packagedFromPath = null;
            foreach (string rawDirectory in path.Split(Path.PathSeparator))
            {
                string directory = rawDirectory.Trim().Trim('"');
                if (String.IsNullOrWhiteSpace(directory))
                {
                    continue;
                }

                try
                {
                    string candidate = Path.Combine(directory, "codex.exe");
                    if (File.Exists(candidate))
                    {
                        if (IsWindowsAppsPath(candidate))
                        {
                            packagedFromPath = candidate;
                        }
                        else
                        {
                            return Path.GetFullPath(candidate);
                        }
                    }
                    candidate = Path.Combine(directory, "codex");
                    if (File.Exists(candidate))
                    {
                        if (IsWindowsAppsPath(candidate))
                        {
                            packagedFromPath = candidate;
                        }
                        else
                        {
                            return Path.GetFullPath(candidate);
                        }
                    }
                }
                catch
                {
                    // Ignore malformed PATH entries and keep searching.
                }
            }

            if (!String.IsNullOrWhiteSpace(packagedFromPath))
            {
                try { return PrepareRunnableExecutable(packagedFromPath); } catch { }
            }

            string packaged = TryFindPackagedCodex();
            if (!String.IsNullOrWhiteSpace(packaged))
            {
                try { return PrepareRunnableExecutable(packaged); } catch { }
            }

            string cached = FindNewestCachedRuntime();
            if (!String.IsNullOrWhiteSpace(cached))
            {
                return cached;
            }

            return "codex.exe";
        }

        private static string PrepareRunnableExecutable(string candidate)
        {
            string fullPath = Path.GetFullPath(candidate);
            if (!IsWindowsAppsPath(fullPath))
            {
                return fullPath;
            }

            FileInfo source = new FileInfo(fullPath);
            if (!source.Exists || source.Length <= 0)
            {
                throw new FileNotFoundException("Codex CLI 不存在。", fullPath);
            }

            string runtimeDirectory = GetRuntimeDirectory();
            Directory.CreateDirectory(runtimeDirectory);
            string versionKey = source.Length.ToString("x", CultureInfo.InvariantCulture)
                + "-" + source.LastWriteTimeUtc.Ticks.ToString("x", CultureInfo.InvariantCulture);
            string destination = Path.Combine(runtimeDirectory, "codex-" + versionKey + ".exe");
            FileInfo cached = new FileInfo(destination);
            if (cached.Exists && cached.Length == source.Length)
            {
                return destination;
            }

            string partial = destination + ".partial";
            TryDeleteFile(partial);
            TryDeleteFile(destination);
            File.Copy(source.FullName, partial, true);

            FileInfo copied = new FileInfo(partial);
            if (!copied.Exists || copied.Length != source.Length)
            {
                TryDeleteFile(partial);
                throw new IOException("Codex CLI 本地运行时复制不完整。");
            }

            File.Move(partial, destination);
            try { File.SetLastWriteTimeUtc(destination, source.LastWriteTimeUtc); } catch { }
            CleanupOldRuntimes(runtimeDirectory, destination);
            return destination;
        }

        private static bool IsWindowsAppsPath(string path)
        {
            if (String.IsNullOrWhiteSpace(path))
            {
                return false;
            }
            return Path.GetFullPath(path).IndexOf(
                Path.DirectorySeparatorChar + "WindowsApps" + Path.DirectorySeparatorChar,
                StringComparison.OrdinalIgnoreCase) >= 0;
        }

        private static string TryFindDesktopRuntimeCodex()
        {
            try
            {
                string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                List<string> roots = new List<string>();
                string configuredInstallDirectory = Environment.GetEnvironmentVariable("CODEX_INSTALL_DIR");
                if (!String.IsNullOrWhiteSpace(configuredInstallDirectory))
                {
                    roots.Add(configuredInstallDirectory);
                }
                roots.Add(Path.Combine(localAppData, "Programs", "OpenAI", "Codex", "bin"));
                roots.Add(Path.Combine(localAppData, "OpenAI", "Codex", "bin"));

                FileInfo candidate = roots
                    .Where(Directory.Exists)
                    .SelectMany(root => new DirectoryInfo(root).GetFiles("codex.exe", SearchOption.AllDirectories))
                    .Where(file => file.Length > 0)
                    .OrderByDescending(file => file.LastWriteTimeUtc)
                    .FirstOrDefault();
                return candidate == null ? null : candidate.FullName;
            }
            catch
            {
                return null;
            }
        }

        private static string TryFindPackagedCodex()
        {
            try
            {
                string windowsApps = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
                    "WindowsApps");
                if (!Directory.Exists(windowsApps))
                {
                    return null;
                }

                DirectoryInfo[] packages = new DirectoryInfo(windowsApps)
                    .GetDirectories("OpenAI.Codex_*")
                    .OrderByDescending(directory => directory.LastWriteTimeUtc)
                    .ToArray();
                foreach (DirectoryInfo package in packages)
                {
                    string candidate = Path.Combine(package.FullName, "app", "resources", "codex.exe");
                    if (File.Exists(candidate))
                    {
                        return candidate;
                    }
                }
            }
            catch
            {
                return null;
            }
            return null;
        }

        private static string GetRuntimeDirectory()
        {
            return Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                AppIdentity.ProductName,
                "runtime");
        }

        private static string FindNewestCachedRuntime()
        {
            try
            {
                string runtimeDirectory = GetRuntimeDirectory();
                if (!Directory.Exists(runtimeDirectory))
                {
                    return null;
                }
                FileInfo candidate = new DirectoryInfo(runtimeDirectory)
                    .GetFiles("codex-*.exe")
                    .Where(file => file.Length > 0)
                    .OrderByDescending(file => file.LastWriteTimeUtc)
                    .FirstOrDefault();
                return candidate == null ? null : candidate.FullName;
            }
            catch
            {
                return null;
            }
        }

        private static void CleanupOldRuntimes(string runtimeDirectory, string current)
        {
            try
            {
                foreach (string path in Directory.GetFiles(runtimeDirectory, "codex-*.exe"))
                {
                    if (!String.Equals(path, current, StringComparison.OrdinalIgnoreCase))
                    {
                        TryDeleteFile(path);
                    }
                }
                foreach (string path in Directory.GetFiles(runtimeDirectory, "*.partial"))
                {
                    TryDeleteFile(path);
                }
            }
            catch { }
        }

        private static void TryDeleteFile(string path)
        {
            try
            {
                if (File.Exists(path))
                {
                    File.Delete(path);
                }
            }
            catch { }
        }

        private void OnOutputDataReceived(object sender, DataReceivedEventArgs args)
        {
            if (String.IsNullOrWhiteSpace(args.Data))
            {
                return;
            }

            lock (stateLock)
            {
                if (disposed
                    || authenticationInvalidated
                    || !Object.ReferenceEquals(process, sender as Process))
                {
                    return;
                }
            }

            IDictionary<string, object> message = QuotaJsonParser.ParseObject(args.Data);
            if (message == null)
            {
                return;
            }

            object idValue = QuotaJsonParser.GetAny(message, "id");
            if (idValue != null)
            {
                long? id = QuotaJsonParser.AsNullableLong(idValue);
                IDictionary<string, object> result = QuotaJsonParser.AsDictionary(
                    QuotaJsonParser.GetAny(message, "result"));
                IDictionary<string, object> error = QuotaJsonParser.AsDictionary(
                    QuotaJsonParser.GetAny(message, "error"));

                if (id.HasValue && id.Value == 0 && result != null)
                {
                    lock (stateLock)
                    {
                        if (authenticationInvalidated
                            || !Object.ReferenceEquals(process, sender as Process))
                        {
                            return;
                        }
                        initialized = true;
                    }
                    Exception sendError;
                    if (!SendLine("{\"method\":\"initialized\",\"params\":{}}", out sendError))
                    {
                        AppSettings.LogRealtimeError(
                            "发送 initialized",
                            sendError.GetType().Name + ": " + sendError.Message);
                        RaiseStatus("实时接口通信失败，使用本地快照", false);
                        return;
                    }
                    RaiseStatus("实时接口已连接，正在读取额度…", false);
                    RequestRefresh();
                    return;
                }

                bool isRateLimitRequest = false;
                if (id.HasValue)
                {
                    lock (stateLock)
                    {
                        isRateLimitRequest = rateLimitRequestIds.Remove(id.Value);
                    }
                }

                if (isRateLimitRequest && result != null)
                {
                    IDictionary<string, object> rateLimits = FindRateLimits(result);
                    if (rateLimits != null)
                    {
                        QuotaSnapshot snapshot = QuotaJsonParser.FromRateLimitsDictionary(
                            rateLimits,
                            "Codex 实时接口",
                            true);
                        if (snapshot != null && snapshot.HasQuotaData)
                        {
                            if (!MarkQuerySuccess(sender as Process))
                            {
                                return;
                            }
                            int generation = RaiseSnapshot(snapshot, false, sender as Process);
                            if (generation >= 0)
                            {
                                RaiseStatus("实时同步中", true, generation);
                            }
                            return;
                        }
                    }
                    HandleQueryFailure(
                        id,
                        "invalid_result",
                        "额度查询成功响应中没有可用的 rateLimits 数据。",
                        sender as Process);
                    return;
                }

                if (isRateLimitRequest && error != null)
                {
                    HandleQueryFailure(
                        id,
                        QuotaJsonParser.AsString(QuotaJsonParser.GetAny(error, "code")),
                        QuotaJsonParser.AsString(QuotaJsonParser.GetAny(error, "message")),
                        sender as Process);
                    return;
                }

                if (isRateLimitRequest)
                {
                    HandleQueryFailure(
                        id,
                        "invalid_response",
                        "额度查询响应同时缺少 result 和 error。",
                        sender as Process);
                    return;
                }

                if (error != null)
                {
                    string errorDetails = FormatRpcError(id, error);
                    AppSettings.LogRealtimeError("app-server RPC", errorDetails);
                    if (id.HasValue && id.Value == 0)
                    {
                        RaiseStatus("实时接口初始化失败，使用本地快照", false);
                    }
                }
                return;
            }

            string method = QuotaJsonParser.AsString(QuotaJsonParser.GetAny(message, "method"));
            if (String.Equals(method, "account/rateLimits/updated", StringComparison.OrdinalIgnoreCase))
            {
                IDictionary<string, object> parameters = QuotaJsonParser.AsDictionary(
                    QuotaJsonParser.GetAny(message, "params"));
                IDictionary<string, object> rateLimits = parameters == null
                    ? null
                    : QuotaJsonParser.AsDictionary(QuotaJsonParser.GetAny(parameters, "rateLimits", "rate_limits"));
                if (rateLimits != null)
                {
                    QuotaSnapshot update = QuotaJsonParser.FromRateLimitsDictionary(
                        rateLimits,
                        "Codex 实时推送",
                        true);
                    if (update != null && update.HasQuotaData)
                    {
                        if (!MarkQuerySuccess(sender as Process))
                        {
                            return;
                        }
                        int generation = RaiseSnapshot(update, true, sender as Process);
                        if (generation >= 0)
                        {
                            RaiseStatus("实时同步中", true, generation);
                        }
                    }
                }
            }
        }

        private bool MarkQuerySuccess(Process sourceProcess)
        {
            lock (stateLock)
            {
                if (disposed
                    || authenticationInvalidated
                    || !Object.ReferenceEquals(process, sourceProcess))
                {
                    return false;
                }
                retryPolicy.Reset();
                hasSuccessfulLiveQuery = true;
                rateLimitRequestIds.Clear();
                CancelRetryTimerLocked();
                return true;
            }
        }

        private void HandleQueryFailure(long? requestId, string code, string message)
        {
            HandleQueryFailure(requestId, code, message, null);
        }

        private void HandleQueryFailure(
            long? requestId,
            string code,
            string message,
            Process sourceProcess)
        {
            string normalizedCode = String.IsNullOrWhiteSpace(code) ? "unknown" : code;
            string normalizedMessage = String.IsNullOrWhiteSpace(message) ? "未提供错误消息。" : message;
            RealtimeRetryDecision decision;
            bool keepLiveStatus;
            lock (stateLock)
            {
                if (disposed
                    || !initialized
                    || (sourceProcess != null
                        && (authenticationInvalidated
                            || !Object.ReferenceEquals(process, sourceProcess))))
                {
                    return;
                }
                decision = retryPolicy.RegisterFailure();
                keepLiveStatus = hasSuccessfulLiveQuery && !decision.UseLocalFallback;
                ScheduleRetryLocked(decision.Delay);
            }

            string delayText = Convert.ToInt32(decision.Delay.TotalSeconds)
                .ToString(CultureInfo.InvariantCulture);
            AppSettings.LogRealtimeError(
                "额度查询失败",
                "requestId=" + (requestId.HasValue
                    ? requestId.Value.ToString(CultureInfo.InvariantCulture)
                    : "unknown")
                    + "; code=" + normalizedCode
                    + "; consecutiveFailures="
                    + decision.ConsecutiveFailures.ToString(CultureInfo.InvariantCulture)
                    + "; retryDelaySeconds=" + delayText
                    + "; localFallback=" + decision.UseLocalFallback.ToString()
                    + "; message=" + normalizedMessage);
            if (decision.UseLocalFallback)
            {
                RaiseStatus(
                    "实时查询连续失败 "
                        + decision.ConsecutiveFailures.ToString(CultureInfo.InvariantCulture)
                        + " 次，使用本地快照；" + delayText + " 秒后重试",
                    false);
            }
            else
            {
                RaiseStatus(
                    "正在重试实时查询（" + delayText + " 秒后，"
                        + decision.ConsecutiveFailures.ToString(CultureInfo.InvariantCulture)
                        + "/" + RealtimeRetryPolicy.LocalFallbackThreshold.ToString(CultureInfo.InvariantCulture)
                        + "）",
                    keepLiveStatus);
            }
        }

        private void ScheduleRetryLocked(TimeSpan delay)
        {
            CancelRetryTimerLocked();
            if (disposed || !initialized)
            {
                return;
            }

            int generation = retryGeneration;
            int delayMilliseconds = Convert.ToInt32(Math.Min(
                Int32.MaxValue,
                Math.Max(1.0, delay.TotalMilliseconds)));
            retryTimer = new Timer(OnRetryTimer, generation, delayMilliseconds, Timeout.Infinite);
        }

        private void CancelRetryTimerLocked()
        {
            retryGeneration++;
            Timer active = retryTimer;
            retryTimer = null;
            if (active != null)
            {
                try { active.Dispose(); } catch { }
            }
        }

        private void ResetQueryStateLocked()
        {
            retryPolicy.Reset();
            hasSuccessfulLiveQuery = false;
            rateLimitRequestIds.Clear();
            CancelRetryTimerLocked();
        }

        private static string FormatRpcError(long? requestId, IDictionary<string, object> error)
        {
            string code = QuotaJsonParser.AsString(QuotaJsonParser.GetAny(error, "code")) ?? "unknown";
            string message = QuotaJsonParser.AsString(QuotaJsonParser.GetAny(error, "message"))
                ?? "未提供错误消息。";
            return "requestId=" + (requestId.HasValue
                ? requestId.Value.ToString(CultureInfo.InvariantCulture)
                : "unknown")
                + "; code=" + code
                + "; message=" + message;
        }

        private static IDictionary<string, object> FindRateLimits(IDictionary<string, object> result)
        {
            IDictionary<string, object> direct = QuotaJsonParser.AsDictionary(
                QuotaJsonParser.GetAny(result, "rateLimits", "rate_limits"));
            if (direct != null)
            {
                return direct;
            }

            IDictionary<string, object> byId = QuotaJsonParser.AsDictionary(
                QuotaJsonParser.GetAny(result, "rateLimitsByLimitId", "rate_limits_by_limit_id"));
            if (byId == null)
            {
                return null;
            }

            object codex;
            if (byId.TryGetValue("codex", out codex))
            {
                IDictionary<string, object> codexLimits = QuotaJsonParser.AsDictionary(codex);
                if (codexLimits != null)
                {
                    return codexLimits;
                }
            }

            foreach (KeyValuePair<string, object> pair in byId)
            {
                IDictionary<string, object> candidate = QuotaJsonParser.AsDictionary(pair.Value);
                if (candidate != null)
                {
                    return candidate;
                }
            }
            return null;
        }

        private void OnErrorDataReceived(object sender, DataReceivedEventArgs args)
        {
            // App-server writes tracing information to stderr. It is intentionally
            // not shown or persisted because it may contain environment details.
        }

        private void OnProcessExited(object sender, EventArgs args)
        {
            string exitCode = "unknown";
            Process exitedProcess = sender as Process;
            if (exitedProcess != null)
            {
                try { exitCode = exitedProcess.ExitCode.ToString(CultureInfo.InvariantCulture); } catch { }
            }

            lock (stateLock)
            {
                if (!Object.ReferenceEquals(process, exitedProcess))
                {
                    return;
                }
                initialized = false;
                ResetQueryStateLocked();
            }

            if (!disposed)
            {
                AppSettings.LogRealtimeError(
                    "Codex app-server 已退出",
                    "exitCode=" + exitCode);
                RaiseStatus("实时接口已断开，使用本地快照", false);
            }
        }

        private bool SendLine(string line, out Exception error)
        {
            error = null;
            lock (inputLock)
            {
                Process active;
                lock (stateLock)
                {
                    active = process;
                }

                if (active == null || SafeHasExited(active))
                {
                    error = new InvalidOperationException("Codex app-server 当前未运行。");
                    return false;
                }

                try
                {
                    active.StandardInput.WriteLine(line);
                    active.StandardInput.Flush();
                    return true;
                }
                catch (Exception exception)
                {
                    error = exception;
                    return false;
                }
            }
        }

        private static bool SafeHasExited(Process value)
        {
            try
            {
                return value.HasExited;
            }
            catch
            {
                return true;
            }
        }

        private int RaiseSnapshot(QuotaSnapshot snapshot, bool sparse, Process sourceProcess)
        {
            if (snapshot == null || !snapshot.HasQuotaData)
            {
                return -1;
            }

            Action<QuotaSnapshot, bool, int> handler;
            int generation;
            lock (stateLock)
            {
                if (disposed
                    || authenticationInvalidated
                    || !Object.ReferenceEquals(process, sourceProcess))
                {
                    return -1;
                }
                handler = SnapshotReceived;
                generation = processGeneration;
            }
            if (handler != null)
            {
                try { handler(snapshot, sparse, generation); } catch { }
            }
            return generation;
        }

        private void RaiseStatus(string text, bool connected)
        {
            int generation;
            lock (stateLock)
            {
                generation = processGeneration;
            }
            RaiseStatus(text, connected, generation);
        }

        private void RaiseStatus(string text, bool connected, int generation)
        {
            Action<string, bool, int> handler = StatusChanged;
            if (handler != null)
            {
                try { handler(text, connected, generation); } catch { }
            }
        }

        private void StopProcess()
        {
            Process active = null;
            lock (stateLock)
            {
                initialized = false;
                ResetQueryStateLocked();
                active = process;
                process = null;
            }

            if (active == null)
            {
                return;
            }

            try
            {
                active.OutputDataReceived -= OnOutputDataReceived;
                active.ErrorDataReceived -= OnErrorDataReceived;
                active.Exited -= OnProcessExited;
                if (!SafeHasExited(active))
                {
                    try { active.StandardInput.Close(); } catch { }
                    if (!active.WaitForExit(700))
                    {
                        active.Kill();
                        active.WaitForExit(700);
                    }
                }
            }
            catch
            {
                // The child may already have exited.
            }
            finally
            {
                try { active.Dispose(); } catch { }
            }
        }

        public void Dispose()
        {
            disposed = true;
            StopProcess();
        }
    }
}
