using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Threading;

namespace CodexQuotaBall
{
    public sealed class CodexProcessMonitor : IDisposable
    {
        private const int ErrorInsufficientBuffer = 122;
        private readonly DispatcherTimer timer;
        private bool? lastState;
        private bool disposed;

        public CodexProcessMonitor(Dispatcher dispatcher)
        {
            timer = new DispatcherTimer(DispatcherPriority.Background, dispatcher);
            timer.Interval = TimeSpan.FromSeconds(2);
            timer.Tick += delegate { CheckAndRaise(); };
        }

        public event Action<bool> StateChanged;

        public void Start()
        {
            if (disposed)
            {
                return;
            }
            CheckAndRaise();
            timer.Start();
        }

        public bool CheckNow()
        {
            return IsCodexDesktopRunning();
        }

        private void CheckAndRaise()
        {
            if (disposed)
            {
                return;
            }
            bool running = IsCodexDesktopRunning();
            if (lastState.HasValue && lastState.Value == running)
            {
                return;
            }
            lastState = running;
            Action<bool> handler = StateChanged;
            if (handler != null)
            {
                handler(running);
            }
        }

        public static bool IsCodexDesktopRunning()
        {
            Process[] processes = Process.GetProcesses();
            try
            {
                foreach (Process process in processes)
                {
                    try
                    {
                        string name = process.ProcessName;
                        if (!IsCandidateName(name))
                        {
                            continue;
                        }

                        string path = TryGetExecutablePath(process);
                        string package = TryGetPackageFullName(process);
                        bool hasWindow = false;
                        string title = String.Empty;
                        try
                        {
                            IntPtr mainWindow = process.MainWindowHandle;
                            hasWindow = mainWindow != IntPtr.Zero && IsWindowVisible(mainWindow);
                            title = process.MainWindowTitle ?? String.Empty;
                        }
                        catch { }

                        if (IsCodexDesktopHost(name, path, package, hasWindow, title))
                        {
                            return true;
                        }
                    }
                    catch { }
                    finally
                    {
                        process.Dispose();
                    }
                }
            }
            finally
            {
                // Candidate processes are disposed in the loop. Dispose any entries
                // not reached when a match returned early.
                foreach (Process process in processes)
                {
                    try { process.Dispose(); } catch { }
                }
            }
            return false;
        }

        internal static bool IsCodexDesktopHost(
            string processName,
            string executablePath,
            string packageFullName,
            bool hasMainWindow,
            string mainWindowTitle)
        {
            string name = (processName ?? String.Empty).Trim().ToLowerInvariant();
            string path = (executablePath ?? String.Empty).Replace('/', '\\').ToLowerInvariant();
            string package = (packageFullName ?? String.Empty).ToLowerInvariant();
            string title = (mainWindowTitle ?? String.Empty).ToLowerInvariant();

            bool codexPackage = package.StartsWith("openai.codex_", StringComparison.OrdinalIgnoreCase);
            bool codexAppPath = path.IndexOf("\\windowsapps\\openai.codex_", StringComparison.OrdinalIgnoreCase) >= 0
                || path.IndexOf("\\openai\\codex\\app\\", StringComparison.OrdinalIgnoreCase) >= 0
                || path.IndexOf("\\programs\\openai\\codex\\app\\", StringComparison.OrdinalIgnoreCase) >= 0;

            if (name == "chatgpt")
            {
                return (hasMainWindow && (codexPackage || codexAppPath))
                    || (hasMainWindow && title.IndexOf("codex", StringComparison.OrdinalIgnoreCase) >= 0);
            }

            if (name == "codex" || name == "codexdesktop" || name == "openai.codex")
            {
                // The CLI and this app's app-server child are also named codex.exe.
                // Requiring a desktop window avoids treating those background
                // processes as the Codex desktop application.
                return hasMainWindow;
            }
            return false;
        }

        private static bool IsCandidateName(string processName)
        {
            return String.Equals(processName, "ChatGPT", StringComparison.OrdinalIgnoreCase)
                || String.Equals(processName, "Codex", StringComparison.OrdinalIgnoreCase)
                || String.Equals(processName, "CodexDesktop", StringComparison.OrdinalIgnoreCase)
                || String.Equals(processName, "OpenAI.Codex", StringComparison.OrdinalIgnoreCase);
        }

        private static string TryGetExecutablePath(Process process)
        {
            try
            {
                return process.MainModule == null ? null : process.MainModule.FileName;
            }
            catch
            {
                return null;
            }
        }

        private static string TryGetPackageFullName(Process process)
        {
            try
            {
                int length = 0;
                int result = GetPackageFullName(process.Handle, ref length, null);
                if (result != ErrorInsufficientBuffer || length <= 0)
                {
                    return null;
                }

                StringBuilder value = new StringBuilder(length);
                result = GetPackageFullName(process.Handle, ref length, value);
                return result == 0 ? value.ToString() : null;
            }
            catch
            {
                return null;
            }
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern int GetPackageFullName(
            IntPtr process,
            ref int packageFullNameLength,
            StringBuilder packageFullName);

        [DllImport("user32.dll")]
        private static extern bool IsWindowVisible(IntPtr window);

        public void Dispose()
        {
            if (disposed)
            {
                return;
            }
            disposed = true;
            timer.Stop();
        }
    }
}
