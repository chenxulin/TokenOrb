using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Windows;
using System.Windows.Threading;

namespace CodexQuotaBall
{
    public static class Program
    {
        private const string UiMutexName = "Local\\CodexQuotaBall.Singleton";
        private const string WatcherMutexName = "Local\\CodexQuotaBall.Watcher";

        [STAThread]
        public static void Main(string[] args)
        {
            bool demoMode = HasArgument(args, "--demo");
#if QA
            RunUi(true, false);
#else
            bool companionUi = HasArgument(args, "--companion-ui");
            bool watcherMode = HasArgument(args, "--watch");
            if (!demoMode && (watcherMode || (!companionUi && AppSettings.IsFollowCodexEnabled())))
            {
                if (!watcherMode)
                {
                    try { AppSettings.EnsureFollowCodexRegistration(); }
                    catch (Exception exception) { AppSettings.LogError(exception); }
                }
                RunWatcher();
                return;
            }
            RunUi(demoMode, companionUi);
#endif
        }

        private static void RunUi(bool demoMode, bool companionUi)
        {
            bool created;
            using (Mutex mutex = new Mutex(true, UiMutexName, out created))
            {
                if (!created)
                {
                    if (!companionUi)
                    {
                        MessageBox.Show(
                            AppIdentity.ProductName + " 已经在运行。",
                            AppIdentity.ProductName,
                            MessageBoxButton.OK,
                            MessageBoxImage.Information);
                    }
                    return;
                }

                try
                {
                    Application application = new Application();
                    application.ShutdownMode = ShutdownMode.OnExplicitShutdown;
                    application.DispatcherUnhandledException += OnDispatcherUnhandledException;

                    MainWindow window = new MainWindow(demoMode, companionUi);
                    application.Run(window);
                }
                catch (Exception exception)
                {
                    AppSettings.LogError(exception);
                    MessageBox.Show(
                        "悬浮球启动失败：" + exception.Message,
                        AppIdentity.ProductName,
                        MessageBoxButton.OK,
                        MessageBoxImage.Error);
                }

                GC.KeepAlive(mutex);
            }
        }

        private static void RunWatcher()
        {
            bool created;
            using (Mutex watcher = new Mutex(true, WatcherMutexName, out created))
            {
                if (!created)
                {
                    return;
                }

                using (EventWaitHandle exit = AppSettings.CreateWatcherExitEvent())
                {
                    while (AppSettings.IsFollowCodexEnabled() && !exit.WaitOne(0))
                    {
                        try
                        {
                            if (CodexProcessMonitor.IsCodexDesktopRunning() && !IsUiRunning())
                            {
                                StartCompanionUi();
                            }
                        }
                        catch (Exception exception)
                        {
                            AppSettings.LogError(exception);
                        }

                        if (exit.WaitOne(TimeSpan.FromSeconds(2)))
                        {
                            break;
                        }
                    }
                }
                GC.KeepAlive(watcher);
            }
        }

        private static bool IsUiRunning()
        {
            try
            {
                using (Mutex existing = Mutex.OpenExisting(UiMutexName))
                {
                    return existing != null;
                }
            }
            catch (WaitHandleCannotBeOpenedException)
            {
                return false;
            }
            catch
            {
                return false;
            }
        }

        private static void StartCompanionUi()
        {
            string executable = Assembly.GetExecutingAssembly().Location;
            Process child = Process.Start(new ProcessStartInfo
            {
                FileName = executable,
                Arguments = "--companion-ui",
                WorkingDirectory = Path.GetDirectoryName(executable) ?? Environment.CurrentDirectory,
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            });
            if (child != null)
            {
                child.Dispose();
            }
        }

        private static bool HasArgument(string[] args, string expected)
        {
            if (args == null)
            {
                return false;
            }

            foreach (string arg in args)
            {
                if (String.Equals(arg, expected, StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
            }
            return false;
        }

        private static void OnDispatcherUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs args)
        {
            AppSettings.LogError(args.Exception);
            args.Handled = true;
        }
    }
}
