using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Windows;
using System.Windows.Threading;
using Drawing = System.Drawing;
using Drawing2D = System.Drawing.Drawing2D;
using Forms = System.Windows.Forms;

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
            RunUi(true, false, false);
#else
            bool companionUi = HasArgument(args, "--companion-ui");
            bool manualUi = HasArgument(args, "--manual-ui");
            bool watcherMode = HasArgument(args, "--watch");
            if (!demoMode && !manualUi
                && (watcherMode || (!companionUi && AppSettings.IsFollowCodexEnabled())))
            {
                if (!watcherMode)
                {
                    try { AppSettings.EnsureFollowCodexRegistration(); }
                    catch (Exception exception) { AppSettings.LogError(exception); }
                }
                RunWatcher();
                return;
            }
            RunUi(demoMode, companionUi, manualUi);
#endif
        }

        private static void RunUi(bool demoMode, bool companionUi, bool manualUi)
        {
            bool created;
            using (Mutex mutex = new Mutex(true, UiMutexName, out created))
            {
                if (!created)
                {
                    if (!companionUi && !manualUi)
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

                    MainWindow window = new MainWindow(demoMode, companionUi, manualUi);
                    using (EventWaitHandle uiExit = AppSettings.CreateUiExitEvent())
                    using (EventWaitHandle uiShow = AppSettings.CreateUiShowEvent())
                    using (EventWaitHandle uiHide = AppSettings.CreateUiHideEvent())
                    using (EventWaitHandle uiVisible = AppSettings.CreateUiVisibleStateEvent())
                    {
                        RegisteredWaitHandle uiExitWait = null;
                        RegisteredWaitHandle uiShowWait = null;
                        RegisteredWaitHandle uiHideWait = null;
                        Action<bool> visibilityChanged = delegate(bool visible)
                        {
                            try
                            {
                                if (visible)
                                {
                                    uiVisible.Set();
                                }
                                else
                                {
                                    uiVisible.Reset();
                                }
                            }
                            catch { }
                        };
                        try
                        {
                            uiVisible.Reset();
                            window.OrbVisibilityChanged += visibilityChanged;
                            uiExitWait = RegisterUiSignalWait(
                                uiExit,
                                application.Dispatcher,
                                application.Shutdown,
                                true);
                            uiShowWait = RegisterUiSignalWait(
                                uiShow,
                                application.Dispatcher,
                                window.ShowFromTray,
                                false);
                            uiHideWait = RegisterUiSignalWait(
                                uiHide,
                                application.Dispatcher,
                                window.HideFromTray,
                                false);
                            application.Run(window);
                        }
                        finally
                        {
                            window.OrbVisibilityChanged -= visibilityChanged;
                            try { uiVisible.Reset(); } catch { }
                            UnregisterWait(uiHideWait);
                            UnregisterWait(uiShowWait);
                            UnregisterWait(uiExitWait);
                        }
                    }
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
                using (EventWaitHandle uiExit = AppSettings.CreateUiExitEvent())
                using (EventWaitHandle uiShow = AppSettings.CreateUiShowEvent())
                using (EventWaitHandle uiHide = AppSettings.CreateUiHideEvent())
                using (EventWaitHandle uiVisible = AppSettings.CreateUiVisibleStateEvent())
                {
                    if (!AppSettings.IsFollowCodexEnabled())
                    {
                        return;
                    }

                    Forms.Application.EnableVisualStyles();
                    using (WatcherTrayContext context = new WatcherTrayContext(
                        exit,
                        uiExit,
                        uiShow,
                        uiHide,
                        uiVisible))
                    {
                        Forms.Application.Run(context);
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
            StartUiProcess("--companion-ui");
        }

        private static RegisteredWaitHandle RegisterUiSignalWait(
            EventWaitHandle signal,
            Dispatcher dispatcher,
            Action action,
            bool executeOnlyOnce)
        {
            return ThreadPool.RegisterWaitForSingleObject(
                signal,
                delegate
                {
                    try
                    {
                        dispatcher.BeginInvoke(new Action(delegate
                        {
                            if (!dispatcher.HasShutdownStarted)
                            {
                                action();
                            }
                        }));
                    }
                    catch { }
                },
                null,
                Timeout.Infinite,
                executeOnlyOnce);
        }

        private static void UnregisterWait(RegisteredWaitHandle wait)
        {
            if (wait != null)
            {
                try { wait.Unregister(null); } catch { }
            }
        }

        private static void StartManualUi()
        {
            StartUiProcess("--manual-ui");
        }

        private static void StartUiProcess(string arguments)
        {
            string executable = Assembly.GetExecutingAssembly().Location;
            Process child = Process.Start(new ProcessStartInfo
            {
                FileName = executable,
                Arguments = arguments,
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

        private sealed class WatcherTrayContext : Forms.ApplicationContext
        {
            private readonly EventWaitHandle watcherExit;
            private readonly EventWaitHandle uiExit;
            private readonly EventWaitHandle uiShow;
            private readonly EventWaitHandle uiHide;
            private readonly EventWaitHandle uiVisible;
            private readonly Forms.ContextMenuStrip menu;
            private readonly Forms.ToolStripMenuItem orbItem;
            private readonly Forms.NotifyIcon notifyIcon;
            private readonly Forms.Timer timer;
            private readonly Drawing.Icon icon;
            private bool manuallyHiddenForCurrentCodexSession;
            private bool exiting;
            private DateTime launchPendingUntilUtc = DateTime.MinValue;
            private DateTime exitDeadlineUtc = DateTime.MinValue;

            public WatcherTrayContext(
                EventWaitHandle watcherExit,
                EventWaitHandle uiExit,
                EventWaitHandle uiShow,
                EventWaitHandle uiHide,
                EventWaitHandle uiVisible)
            {
                this.watcherExit = watcherExit;
                this.uiExit = uiExit;
                this.uiShow = uiShow;
                this.uiHide = uiHide;
                this.uiVisible = uiVisible;

                orbItem = new Forms.ToolStripMenuItem("显示/隐藏悬浮球");
                orbItem.CheckOnClick = false;
                orbItem.Padding = new Forms.Padding(8, 5, 12, 5);
                orbItem.Click += delegate { ToggleOrb(); };
                Forms.ToolStripMenuItem exitItem = new Forms.ToolStripMenuItem("退出");
                exitItem.Padding = new Forms.Padding(8, 5, 12, 5);
                exitItem.Click += delegate { ExitFromTray(); };

                menu = new Forms.ContextMenuStrip();
                menu.BackColor = Drawing.Color.White;
                menu.ForeColor = Drawing.Color.FromArgb(31, 31, 31);
                menu.Font = new Drawing.Font("Microsoft YaHei UI", 9.5F, Drawing.FontStyle.Regular);
                menu.MinimumSize = new Drawing.Size(144, 0);
                menu.Padding = new Forms.Padding(3);
                menu.ShowImageMargin = false;
                menu.ShowCheckMargin = true;
                menu.Renderer = new TokenOrbMenuRenderer();
                menu.Items.Add(orbItem);
                menu.Items.Add(exitItem);
                menu.Opening += delegate
                {
                    RefreshMenuState();
                    ApplyRoundedMenuRegion();
                };
                menu.Opened += delegate { ApplyRoundedMenuRegion(); };
                menu.SizeChanged += delegate { ApplyRoundedMenuRegion(); };

                icon = Drawing.Icon.ExtractAssociatedIcon(Assembly.GetExecutingAssembly().Location)
                    ?? (Drawing.Icon)Drawing.SystemIcons.Application.Clone();
                notifyIcon = new Forms.NotifyIcon();
                notifyIcon.Icon = icon;
                notifyIcon.Text = AppIdentity.ProductName + " - 后台运行中";
                notifyIcon.ContextMenuStrip = menu;
                notifyIcon.Visible = true;
                notifyIcon.MouseDoubleClick += delegate(object sender, Forms.MouseEventArgs args)
                {
                    if (args.Button == Forms.MouseButtons.Left)
                    {
                        ShowOrb();
                    }
                };

                timer = new Forms.Timer();
                timer.Interval = 2000;
                timer.Tick += OnTimerTick;
                timer.Start();
                RefreshMenuState();
            }

            private bool IsLaunchPending
            {
                get { return DateTime.UtcNow < launchPendingUntilUtc; }
            }

            private void OnTimerTick(object sender, EventArgs args)
            {
                if (exiting)
                {
                    try { uiExit.Set(); } catch { }
                    if ((!IsUiRunning() && !IsLaunchPending) || DateTime.UtcNow >= exitDeadlineUtc)
                    {
                        ExitWatcherNow();
                    }
                    return;
                }

                if (watcherExit.WaitOne(0) || !AppSettings.IsFollowCodexEnabled())
                {
                    ExitWatcherNow();
                    return;
                }

                try
                {
                    bool codexRunning = CodexProcessMonitor.IsCodexDesktopRunning();
                    manuallyHiddenForCurrentCodexSession =
                        WatcherTrayBehavior.ShouldKeepManualHideSuppressed(
                            codexRunning,
                            manuallyHiddenForCurrentCodexSession);

                    bool uiRunning = IsUiRunning();
                    if (uiRunning)
                    {
                        launchPendingUntilUtc = DateTime.MinValue;
                    }

                    if (!IsLaunchPending
                        && WatcherTrayBehavior.ShouldAutoStartOrb(
                            true,
                            codexRunning,
                            uiRunning,
                            manuallyHiddenForCurrentCodexSession))
                    {
                        LaunchOrb(false);
                    }
                }
                catch (Exception exception)
                {
                    AppSettings.LogError(exception);
                }

                RefreshMenuState();
            }

            private void StartOrb()
            {
                if (exiting || IsLaunchPending)
                {
                    return;
                }

                if (IsUiRunning())
                {
                    ShowOrb();
                    return;
                }

                manuallyHiddenForCurrentCodexSession = false;
                LaunchOrb(true);
                RefreshMenuState();
            }

            private void ToggleOrb()
            {
                if (exiting || IsLaunchPending)
                {
                    return;
                }

                if (IsOrbVisible())
                {
                    HideOrb();
                }
                else
                {
                    ShowOrb();
                }
            }

            private bool IsOrbVisible()
            {
                if (!IsUiRunning())
                {
                    return false;
                }

                try { return uiVisible.WaitOne(0); }
                catch { return false; }
            }

            private void ShowOrb()
            {
                if (exiting || IsLaunchPending)
                {
                    return;
                }

                manuallyHiddenForCurrentCodexSession = false;
                if (!IsUiRunning())
                {
                    StartOrb();
                    return;
                }

                try { uiShow.Set(); }
                catch (Exception exception) { AppSettings.LogError(exception); }
                RefreshMenuState();
            }

            private void LaunchOrb(bool manual)
            {
                try
                {
                    uiExit.Reset();
                    uiShow.Reset();
                    uiHide.Reset();
                    uiVisible.Reset();
                    if (manual)
                    {
                        StartManualUi();
                    }
                    else
                    {
                        StartCompanionUi();
                    }
                    launchPendingUntilUtc = DateTime.UtcNow.AddSeconds(5);
                }
                catch (Exception exception)
                {
                    launchPendingUntilUtc = DateTime.MinValue;
                    AppSettings.LogError(exception);
                }
            }

            private void HideOrb()
            {
                if (exiting || !IsUiRunning())
                {
                    return;
                }

                try
                {
                    manuallyHiddenForCurrentCodexSession =
                        CodexProcessMonitor.IsCodexDesktopRunning();
                }
                catch
                {
                    manuallyHiddenForCurrentCodexSession = false;
                }

                try
                {
                    uiVisible.Reset();
                    uiHide.Set();
                }
                catch (Exception exception)
                {
                    AppSettings.LogError(exception);
                }
                RefreshMenuState();
            }

            private void ExitFromTray()
            {
                if (exiting)
                {
                    return;
                }

                exiting = true;
                exitDeadlineUtc = DateTime.UtcNow.AddSeconds(2);
                notifyIcon.Visible = false;
                timer.Interval = 100;
                try { uiExit.Set(); } catch { }
                try { watcherExit.Set(); } catch { }

                if (!IsUiRunning() && !IsLaunchPending)
                {
                    ExitWatcherNow();
                }
            }

            private void RefreshMenuState()
            {
                bool running = IsUiRunning();
                bool visible = running && IsOrbVisible();
                bool pending = IsLaunchPending;
                orbItem.Checked = visible;
                orbItem.Enabled = !exiting && !pending;
                notifyIcon.Text = visible
                    ? AppIdentity.ProductName + " - 悬浮球运行中"
                    : running
                        ? AppIdentity.ProductName + " - 悬浮球已隐藏"
                        : pending
                            ? AppIdentity.ProductName + " - 正在显示悬浮球"
                            : AppIdentity.ProductName + " - 后台运行中";
            }

            private void ApplyRoundedMenuRegion()
            {
                if (menu.Width < 2 || menu.Height < 2)
                {
                    return;
                }

                Drawing.Rectangle bounds = new Drawing.Rectangle(0, 0, menu.Width, menu.Height);
                using (Drawing2D.GraphicsPath path =
                    TokenOrbMenuRenderer.CreateRoundedRectangle(bounds, 6))
                {
                    Drawing.Region oldRegion = menu.Region;
                    menu.Region = new Drawing.Region(path);
                    if (oldRegion != null)
                    {
                        oldRegion.Dispose();
                    }
                }
            }

            private void ExitWatcherNow()
            {
                if (timer.Enabled)
                {
                    timer.Stop();
                }
                notifyIcon.Visible = false;
                ExitThread();
            }

            protected override void Dispose(bool disposing)
            {
                if (disposing)
                {
                    timer.Stop();
                    notifyIcon.Visible = false;
                    timer.Dispose();
                    notifyIcon.Dispose();
                    Drawing.Region menuRegion = menu.Region;
                    menu.Region = null;
                    if (menuRegion != null)
                    {
                        menuRegion.Dispose();
                    }
                    menu.Dispose();
                    icon.Dispose();
                }
                base.Dispose(disposing);
            }
        }

        private sealed class TokenOrbMenuRenderer : Forms.ToolStripProfessionalRenderer
        {
            private static readonly Drawing.Color Panel = Drawing.Color.White;
            private static readonly Drawing.Color Border = Drawing.Color.FromArgb(220, 222, 225);
            private static readonly Drawing.Color Highlight = Drawing.Color.FromArgb(238, 238, 238);
            private static readonly Drawing.Color Separator = Drawing.Color.FromArgb(226, 227, 229);
            private static readonly Drawing.Color Accent = Drawing.Color.FromArgb(31, 31, 31);

            public TokenOrbMenuRenderer()
                : base(new TokenOrbColorTable())
            {
                RoundedEdges = true;
            }

            protected override void OnRenderToolStripBackground(Forms.ToolStripRenderEventArgs args)
            {
                args.Graphics.Clear(Panel);
            }

            protected override void OnRenderToolStripBorder(Forms.ToolStripRenderEventArgs args)
            {
                Drawing.Rectangle bounds = new Drawing.Rectangle(
                    0,
                    0,
                    Math.Max(0, args.ToolStrip.Width - 1),
                    Math.Max(0, args.ToolStrip.Height - 1));
                Drawing2D.SmoothingMode oldMode = args.Graphics.SmoothingMode;
                args.Graphics.SmoothingMode = Drawing2D.SmoothingMode.AntiAlias;
                using (Drawing.Pen pen = new Drawing.Pen(Border))
                using (Drawing2D.GraphicsPath path = CreateRoundedRectangle(bounds, 6))
                {
                    args.Graphics.DrawPath(pen, path);
                }
                args.Graphics.SmoothingMode = oldMode;
            }

            protected override void OnRenderMenuItemBackground(Forms.ToolStripItemRenderEventArgs args)
            {
                if (!args.Item.Selected)
                {
                    return;
                }

                Drawing.Rectangle bounds = new Drawing.Rectangle(
                    4,
                    1,
                    Math.Max(1, args.Item.Width - 9),
                    Math.Max(1, args.Item.Height - 3));
                Drawing2D.SmoothingMode oldMode = args.Graphics.SmoothingMode;
                args.Graphics.SmoothingMode = Drawing2D.SmoothingMode.AntiAlias;
                using (Drawing2D.GraphicsPath path = CreateRoundedRectangle(bounds, 5))
                using (Drawing.SolidBrush brush = new Drawing.SolidBrush(Highlight))
                {
                    args.Graphics.FillPath(brush, path);
                }
                args.Graphics.SmoothingMode = oldMode;
            }

            protected override void OnRenderSeparator(Forms.ToolStripSeparatorRenderEventArgs args)
            {
                int y = args.Item.Height / 2;
                using (Drawing.Pen pen = new Drawing.Pen(Separator))
                {
                    args.Graphics.DrawLine(pen, 8, y, Math.Max(8, args.Item.Width - 8), y);
                }
            }

            protected override void OnRenderItemCheck(Forms.ToolStripItemImageRenderEventArgs args)
            {
                Drawing.Rectangle bounds = args.ImageRectangle;
                if (bounds.Width <= 0 || bounds.Height <= 0)
                {
                    bounds = new Drawing.Rectangle(4, 0, 18, args.Item.Height);
                }
                Forms.TextRenderer.DrawText(
                    args.Graphics,
                    "✓",
                    args.Item.Font,
                    bounds,
                    Accent,
                    Forms.TextFormatFlags.HorizontalCenter
                        | Forms.TextFormatFlags.VerticalCenter
                        | Forms.TextFormatFlags.NoPadding);
            }

            public static Drawing2D.GraphicsPath CreateRoundedRectangle(
                Drawing.Rectangle bounds,
                int radius)
            {
                Drawing2D.GraphicsPath path = new Drawing2D.GraphicsPath();
                int diameter = Math.Max(2, Math.Min(radius * 2, Math.Min(bounds.Width, bounds.Height)));
                Drawing.Rectangle arc = new Drawing.Rectangle(bounds.Location, new Drawing.Size(diameter, diameter));
                path.AddArc(arc, 180, 90);
                arc.X = bounds.Right - diameter;
                path.AddArc(arc, 270, 90);
                arc.Y = bounds.Bottom - diameter;
                path.AddArc(arc, 0, 90);
                arc.X = bounds.Left;
                path.AddArc(arc, 90, 90);
                path.CloseFigure();
                return path;
            }
        }

        private sealed class TokenOrbColorTable : Forms.ProfessionalColorTable
        {
            private static readonly Drawing.Color Panel = Drawing.Color.White;
            private static readonly Drawing.Color Border = Drawing.Color.FromArgb(220, 222, 225);
            private static readonly Drawing.Color Highlight = Drawing.Color.FromArgb(238, 238, 238);
            private static readonly Drawing.Color Check = Drawing.Color.FromArgb(238, 238, 238);

            public override Drawing.Color ToolStripDropDownBackground { get { return Panel; } }
            public override Drawing.Color ImageMarginGradientBegin { get { return Panel; } }
            public override Drawing.Color ImageMarginGradientMiddle { get { return Panel; } }
            public override Drawing.Color ImageMarginGradientEnd { get { return Panel; } }
            public override Drawing.Color MenuBorder { get { return Border; } }
            public override Drawing.Color MenuItemBorder { get { return Highlight; } }
            public override Drawing.Color MenuItemSelected { get { return Highlight; } }
            public override Drawing.Color MenuItemSelectedGradientBegin { get { return Highlight; } }
            public override Drawing.Color MenuItemSelectedGradientEnd { get { return Highlight; } }
            public override Drawing.Color MenuItemPressedGradientBegin { get { return Highlight; } }
            public override Drawing.Color MenuItemPressedGradientMiddle { get { return Highlight; } }
            public override Drawing.Color MenuItemPressedGradientEnd { get { return Highlight; } }
            public override Drawing.Color CheckBackground { get { return Check; } }
            public override Drawing.Color CheckSelectedBackground { get { return Highlight; } }
            public override Drawing.Color CheckPressedBackground { get { return Highlight; } }
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
