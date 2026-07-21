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
        private Process process;
        private bool initialized;
        private bool disposed;
        private int nextRequestId = 10;

        public event Action<QuotaSnapshot, bool> SnapshotReceived;
        public event Action<string, bool> StatusChanged;

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

        public void Start()
        {
            lock (stateLock)
            {
                if (disposed || (process != null && !SafeHasExited(process)))
                {
                    return;
                }

                initialized = false;
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
                catch
                {
                    try { newProcess.Dispose(); } catch { }
                    process = null;
                    RaiseStatus("实时接口不可用，使用本地快照", false);
                    return;
                }
            }

            RaiseStatus("正在连接 Codex 实时接口…", false);
            SendLine("{\"method\":\"initialize\",\"id\":0,\"params\":{\"clientInfo\":{\"name\":\"token_orb\",\"title\":\""
                + AppIdentity.ProductName + "\",\"version\":\"" + AppIdentity.ProtocolVersion + "\"}}}");
        }

        public void RequestRefresh()
        {
            if (!IsInitialized)
            {
                return;
            }

            int id = Interlocked.Increment(ref nextRequestId);
            SendLine("{\"method\":\"account/rateLimits/read\",\"id\":"
                + id.ToString(CultureInfo.InvariantCulture) + "}");
        }

        public void Restart()
        {
            StopProcess();
            Start();
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
                        initialized = true;
                    }
                    SendLine("{\"method\":\"initialized\",\"params\":{}}");
                    RaiseStatus("实时接口已连接，正在读取额度…", false);
                    RequestRefresh();
                    return;
                }

                if (result != null)
                {
                    IDictionary<string, object> rateLimits = FindRateLimits(result);
                    if (rateLimits != null)
                    {
                        QuotaSnapshot snapshot = QuotaJsonParser.FromRateLimitsDictionary(
                            rateLimits,
                            "Codex 实时接口",
                            true);
                        RaiseSnapshot(snapshot, false);
                        RaiseStatus("实时同步中", true);
                    }
                    return;
                }

                if (error != null)
                {
                    RaiseStatus("实时查询失败，使用本地快照", false);
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
                    RaiseSnapshot(update, true);
                    RaiseStatus("实时同步中", true);
                }
            }
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
            lock (stateLock)
            {
                initialized = false;
            }

            if (!disposed)
            {
                RaiseStatus("实时接口已断开，使用本地快照", false);
            }
        }

        private void SendLine(string line)
        {
            lock (inputLock)
            {
                Process active;
                lock (stateLock)
                {
                    active = process;
                }

                if (active == null || SafeHasExited(active))
                {
                    return;
                }

                try
                {
                    active.StandardInput.WriteLine(line);
                    active.StandardInput.Flush();
                }
                catch
                {
                    RaiseStatus("实时接口通信失败，使用本地快照", false);
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

        private void RaiseSnapshot(QuotaSnapshot snapshot, bool sparse)
        {
            if (snapshot == null || !snapshot.HasQuotaData)
            {
                return;
            }

            Action<QuotaSnapshot, bool> handler = SnapshotReceived;
            if (handler != null)
            {
                try { handler(snapshot, sparse); } catch { }
            }
        }

        private void RaiseStatus(string text, bool connected)
        {
            Action<string, bool> handler = StatusChanged;
            if (handler != null)
            {
                try { handler(text, connected); } catch { }
            }
        }

        private void StopProcess()
        {
            Process active = null;
            lock (stateLock)
            {
                initialized = false;
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
