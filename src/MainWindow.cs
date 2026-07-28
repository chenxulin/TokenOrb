using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Threading;

namespace CodexQuotaBall
{
    public sealed class MainWindow : Window
    {
        private readonly QuotaBallVisual ball;
        private readonly DetailWindow detail;
        private AppearanceWindow appearanceWindow;
        private readonly bool demoMode;
        private readonly CodexProcessMonitor processMonitor;
        private readonly DispatcherTimer secondTimer;
        private QuotaService service;
        private BallAppearanceSettings appearance;
        private QuotaSnapshot snapshot;
        private string connectionText = "正在连接 Codex…";
        private bool connected;
        private bool loaded;
        private bool followCodexEnabled;
        private bool companionUi;
        private readonly bool manualUi;
        private bool orbVisible;
        private HwndSource windowSource;

        private const int WindowMessageNonClientHitTest = 0x0084;
        private const int HitTestTransparent = -1;
        private const int ExtendedWindowStyleIndex = -20;

        [DllImport("user32.dll", EntryPoint = "GetWindowLongW", SetLastError = true)]
        private static extern int GetWindowLong(IntPtr windowHandle, int index);

        [DllImport("user32.dll", EntryPoint = "SetWindowLongW", SetLastError = true)]
        private static extern int SetWindowLong(IntPtr windowHandle, int index, int value);

        public event Action<bool> OrbVisibilityChanged;

        public bool IsOrbVisible
        {
            get { return orbVisible; }
        }

        public MainWindow(bool demoMode, bool companionUi, bool manualUi)
        {
            this.demoMode = demoMode;
            this.companionUi = companionUi;
            this.manualUi = manualUi;
            appearance = AppSettings.LoadAppearance();
#if QA
            Title = AppIdentity.ProductName + " QA 演示";
#else
            Title = AppIdentity.ProductName;
#endif
            Width = OrbWindowMetrics.PreviewWidth;
            Height = OrbWindowMetrics.PreviewHeight;
            MinWidth = OrbWindowMetrics.PreviewWidth;
            MinHeight = OrbWindowMetrics.PreviewHeight;
            MaxWidth = OrbWindowMetrics.PreviewWidth;
            MaxHeight = OrbWindowMetrics.PreviewHeight;
            WindowStyle = WindowStyle.None;
            ResizeMode = ResizeMode.NoResize;
            AllowsTransparency = true;
            Background = Brushes.Transparent;
            Opacity = 0.0;
#if QA
            ShowInTaskbar = true;
#else
            ShowInTaskbar = false;
#endif
            Topmost = true;
            WindowStartupLocation = WindowStartupLocation.Manual;

            ball = new QuotaBallVisual();
            ball.SetAppearance(
                appearance.Size,
                appearance.AccentColor,
                appearance.TextStyle,
                appearance.AnimationFrameRate);
            AutomationProperties.SetName(ball, "Codex 剩余额度");
            ball.SetState(null, false);
            ball.ContextMenu = CreateContextMenu();
            ball.HorizontalAlignment = HorizontalAlignment.Center;
            ball.VerticalAlignment = VerticalAlignment.Center;

            Grid previewSurface = new Grid
            {
                Width = OrbWindowMetrics.PreviewWidth,
                Height = OrbWindowMetrics.PreviewHeight,
                Background = Brushes.Transparent,
                Clip = new RectangleGeometry(
                    new Rect(
                        0.0,
                        0.0,
                        OrbWindowMetrics.PreviewWidth,
                        OrbWindowMetrics.PreviewHeight),
                    OrbWindowMetrics.PreviewCornerRadius,
                    OrbWindowMetrics.PreviewCornerRadius)
            };
            previewSurface.Children.Add(ball);
            Content = previewSurface;

            detail = new DetailWindow();
            processMonitor = new CodexProcessMonitor(Dispatcher);
            processMonitor.StateChanged += OnCodexRunningChanged;

            secondTimer = new DispatcherTimer(DispatcherPriority.Background, Dispatcher);
            secondTimer.Interval = TimeSpan.FromSeconds(1);
            secondTimer.Tick += delegate
            {
                detail.RefreshTimeLabels();
                ball.SetState(snapshot, connected);
            };

            Loaded += OnLoaded;
            SourceInitialized += OnSourceInitialized;
            Closed += OnClosed;
            MouseLeftButtonDown += OnMouseLeftButtonDown;
        }

        private void OnLoaded(object sender, RoutedEventArgs args)
        {
            loaded = true;
            RestorePosition();
            try { detail.Owner = this; } catch { }

            if (demoMode)
            {
                followCodexEnabled = false;
                ActivateForCodex();
                return;
            }

            followCodexEnabled = AppSettings.IsFollowCodexEnabled();
            if (followCodexEnabled)
            {
                try
                {
                    AppSettings.EnsureFollowCodexRegistration();
                }
                catch (Exception exception)
                {
                    AppSettings.LogError(exception);
                }
            }

            if (manualUi)
            {
                ActivateForCodex();
                return;
            }

            processMonitor.Start();
            if (!followCodexEnabled)
            {
                ActivateForCodex();
            }
        }

        private void OnClosed(object sender, EventArgs args)
        {
            if (windowSource != null)
            {
                try { windowSource.RemoveHook(OnWindowMessage); } catch { }
                windowSource = null;
            }
            SetOrbVisible(false);
            secondTimer.Stop();
            try { detail.Close(); } catch { }
            processMonitor.StateChanged -= OnCodexRunningChanged;
            processMonitor.Dispose();
            StopService();

            if (Application.Current != null
                && !Application.Current.Dispatcher.HasShutdownStarted)
            {
                Application.Current.Shutdown();
            }
        }

        private void OnSourceInitialized(object sender, EventArgs args)
        {
            windowSource = PresentationSource.FromVisual(this) as HwndSource;
            if (windowSource != null)
            {
#if !QA
                HideFromWindowSwitcher(windowSource.Handle);
#endif
                windowSource.AddHook(OnWindowMessage);
            }
        }

        private static void HideFromWindowSwitcher(IntPtr windowHandle)
        {
            if (windowHandle == IntPtr.Zero)
            {
                return;
            }

            int currentStyle = GetWindowLong(windowHandle, ExtendedWindowStyleIndex);
            int hiddenStyle = WindowSwitcherVisibilityPolicy.HideFromSwitcher(currentStyle);
            if (hiddenStyle != currentStyle)
            {
                SetWindowLong(windowHandle, ExtendedWindowStyleIndex, hiddenStyle);
            }
        }

        private IntPtr OnWindowMessage(
            IntPtr handle,
            int message,
            IntPtr wParam,
            IntPtr lParam,
            ref bool handled)
        {
            if (message != WindowMessageNonClientHitTest)
            {
                return IntPtr.Zero;
            }

            try
            {
                long packed = lParam.ToInt64();
                Point screenPoint = new Point(
                    unchecked((short)(packed & 0xFFFF)),
                    unchecked((short)((packed >> 16) & 0xFFFF)));
                Point windowPoint = PointFromScreen(screenPoint);
                if (!OrbWindowMetrics.GetOrbBounds(appearance.Size).Contains(windowPoint))
                {
                    handled = true;
                    return new IntPtr(HitTestTransparent);
                }
            }
            catch
            {
                // Fall back to normal WPF hit testing if coordinate conversion is unavailable.
            }

            return IntPtr.Zero;
        }

        protected override void OnContextMenuOpening(ContextMenuEventArgs args)
        {
            // ContextMenu raises this event before creating its Popup.  Make the
            // orb the foreground window first so WPF's built-in mouse capture can
            // receive clicks outside the Popup, including clicks in other apps.
            // A background window's SetCapture is limited to its visible bounds.
            if (!args.Handled && !IsActive)
            {
                try
                {
                    if (!Activate())
                    {
                        args.Handled = true;
                        AppSettings.LogError(new InvalidOperationException(
                            "Unable to activate the orb before opening its context menu."));
                    }
                }
                catch (Exception exception)
                {
                    args.Handled = true;
                    AppSettings.LogError(exception);
                }
            }

            base.OnContextMenuOpening(args);
        }

        private void OnSnapshotChanged(QuotaSnapshot value)
        {
            snapshot = value;
            ball.SetState(snapshot, connected);
            detail.UpdateSnapshot(snapshot);
        }

        private void OnConnectionChanged(string text, bool isConnected)
        {
            connectionText = text;
            connected = isConnected;
            ball.SetState(snapshot, connected);
            detail.UpdateConnection(connectionText, connected);
        }

        private void OnMouseLeftButtonDown(object sender, MouseButtonEventArgs args)
        {
            if (args.ChangedButton != MouseButton.Left)
            {
                return;
            }
            if (!OrbWindowMetrics.GetOrbBounds(appearance.Size).Contains(args.GetPosition(this)))
            {
                return;
            }

            double oldLeft = Left;
            double oldTop = Top;
            try
            {
                DragMove();
            }
            catch
            {
                return;
            }

            double distance = Math.Abs(Left - oldLeft) + Math.Abs(Top - oldTop);
            if (distance < 4.0)
            {
                ToggleDetail();
            }
            else
            {
                ClampAndSavePosition();
                if (detail.IsVisible)
                {
                    detail.PositionBeside(this, GetOrbScreenBounds());
                }
            }
            args.Handled = true;
        }

        private ContextMenu CreateContextMenu()
        {
            ContextMenu menu = new ContextMenu
            {
                Background = UiPalette.Brush(UiPalette.Panel),
                Foreground = UiPalette.Brush(UiPalette.Text),
                BorderBrush = UiPalette.Brush(UiPalette.Border),
                BorderThickness = new Thickness(1),
                FontFamily = new FontFamily("Microsoft YaHei UI"),
                FontSize = 11.5,
                Padding = new Thickness(4),
                MinWidth = 164,
                StaysOpen = false,
                OverridesDefaultStyle = true,
                Template = CreateContextMenuTemplate()
            };
            menu.Resources[typeof(MenuItem)] = CreateMenuItemStyle();

            MenuItem detailsItem = new MenuItem { Header = "查看额度" };
            detailsItem.Click += delegate { ToggleDetail(); };
            menu.Items.Add(detailsItem);

            MenuItem refreshItem = new MenuItem { Header = "立即刷新" };
            refreshItem.Click += delegate
            {
                connectionText = "正在刷新…";
                connected = false;
                ball.SetState(snapshot, connected);
                detail.UpdateConnection(connectionText, connected);
                if (service != null)
                {
                    service.ManualRefresh();
                }
            };
            menu.Items.Add(refreshItem);

            MenuItem appearanceItem = new MenuItem { Header = "个性化外观" };
            appearanceItem.Click += delegate { OpenAppearanceWindow(); };
            menu.Items.Add(appearanceItem);

            MenuItem visibilityItem = new MenuItem
            {
                Header = "显示悬浮球",
                IsCheckable = true,
                IsChecked = IsOrbVisible
            };
            visibilityItem.Click += delegate
            {
                bool shouldShow = !IsOrbVisible;
                Dispatcher.BeginInvoke(
                    new Action(delegate
                    {
                        if (shouldShow)
                        {
                            ShowFromTray();
                        }
                        else
                        {
                            HideFromTray();
                        }
                    }),
                    DispatcherPriority.Background);
            };
            menu.Opened += delegate { visibilityItem.IsChecked = IsOrbVisible; };
            menu.Items.Add(visibilityItem);

            MenuItem exitItem = new MenuItem { Header = "退出" };
            exitItem.Click += delegate
            {
                AppSettings.SignalWatcherExit();
                Application.Current.Shutdown();
            };
            menu.Items.Add(exitItem);
            return menu;
        }

        private void OpenAppearanceWindow()
        {
            AppearanceWindow openWindow = appearanceWindow;
            if (openWindow != null)
            {
                try
                {
                    if (openWindow.WindowState == WindowState.Minimized)
                    {
                        openWindow.WindowState = WindowState.Normal;
                    }
                    openWindow.Activate();
                }
                catch (Exception exception)
                {
                    ReportAppearanceError("无法激活外观设置：", exception);
                }
                return;
            }

            try
            {
                if (detail.IsVisible)
                {
                    detail.Hide();
                }

                // Keep this window unowned and modeless. An owned window follows
                // the topmost orb's Z-order and would stay above other apps.
                AppearanceWindow window = new AppearanceWindow(appearance);
                window.Closed += OnAppearanceWindowClosed;
                appearanceWindow = window;
                window.Show();
            }
            catch (Exception exception)
            {
                AppearanceWindow failedWindow = appearanceWindow;
                appearanceWindow = null;
                if (failedWindow != null)
                {
                    failedWindow.Closed -= OnAppearanceWindowClosed;
                    try { failedWindow.Close(); } catch { }
                }
                ReportAppearanceError("无法打开外观设置：", exception);
            }
        }

        private void OnAppearanceWindowClosed(object sender, EventArgs args)
        {
            AppearanceWindow window = sender as AppearanceWindow;
            if (window == null)
            {
                return;
            }

            window.Closed -= OnAppearanceWindowClosed;
            if (ReferenceEquals(appearanceWindow, window))
            {
                appearanceWindow = null;
            }
            if (!window.WasAccepted)
            {
                return;
            }

            try
            {
                ApplyAppearance(
                    window.SelectedSize,
                    window.SelectedColor,
                    window.SelectedTextStyle,
                    window.SelectedAnimationFrameRate,
                    true);
            }
            catch (Exception exception)
            {
                ReportAppearanceError("无法保存外观设置：", exception);
            }
        }

        private static void ReportAppearanceError(string prefix, Exception exception)
        {
            AppSettings.LogError(exception);
            MessageBox.Show(
                prefix + exception.Message,
                AppIdentity.ProductName,
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }

        private void ApplyAppearance(
            double size,
            Color color,
            QuotaTextStyle textStyle,
            int animationFrameRate,
            bool save)
        {
            double safeSize = Math.Round(Math.Max(
                QuotaBallVisual.MinimumDiameter,
                Math.Min(size, QuotaBallVisual.MaximumDiameter)));
            Rect workArea = GetWorkArea();
            Point currentPosition = GetOrbOrigin();
            Size currentSize = new Size(appearance.Size, appearance.Size);
            QuotaTextStyle safeTextStyle = QuotaTextStyleCatalog.Normalize(textStyle);
            int safeFrameRate = AnimationFrameRateCatalog.Normalize(animationFrameRate);
            ball.SetAppearance(safeSize, color, safeTextStyle, safeFrameRate);
            appearance = new BallAppearanceSettings
            {
                Size = safeSize,
                AccentColor = color,
                TextStyle = safeTextStyle,
                AnimationFrameRate = safeFrameRate
            };

            Point resizedPosition = BallPositioning.PreserveCenterOnResize(
                currentPosition,
                currentSize,
                new Size(safeSize, safeSize),
                workArea);
            SetOrbOrigin(resizedPosition);
            AppSettings.SavePosition(resizedPosition.X, resizedPosition.Y);
            if (save)
            {
                AppSettings.SaveAppearance(
                    safeSize,
                    color,
                    safeTextStyle,
                    safeFrameRate);
            }
            if (detail.IsVisible)
            {
                detail.PositionBeside(this, GetOrbScreenBounds());
            }
        }

        private void OnCodexRunningChanged(bool running)
        {
            if (!demoMode)
            {
                followCodexEnabled = AppSettings.IsFollowCodexEnabled();
            }
            if (!loaded || demoMode || manualUi || !followCodexEnabled)
            {
                return;
            }

            if (running)
            {
                ActivateForCodex();
            }
            else if (companionUi)
            {
                Application.Current.Shutdown();
            }
            else
            {
                DeactivateForCodex();
            }
        }

        private void ActivateForCodex()
        {
            if (!IsVisible)
            {
                Show();
                try { detail.Owner = this; } catch { }
            }
            Opacity = 1.0;
            ClampToWorkArea();
            secondTimer.Start();
            SetOrbVisible(true);
            StartService();
        }

        private void DeactivateForCodex()
        {
            if (detail.IsVisible)
            {
                detail.Hide();
            }
            if (IsVisible)
            {
                Hide();
            }
            SetOrbVisible(false);
            secondTimer.Stop();
            StopService();
        }

        public void ShowFromTray()
        {
            if (!loaded)
            {
                return;
            }
            ActivateForCodex();
        }

        public void HideFromTray()
        {
            if (!loaded)
            {
                return;
            }
            DeactivateForCodex();
        }

        private void SetOrbVisible(bool visible)
        {
            if (orbVisible == visible)
            {
                return;
            }

            orbVisible = visible;
            Action<bool> changed = OrbVisibilityChanged;
            if (changed != null)
            {
                changed(visible);
            }
        }

        private void StartService()
        {
            if (service != null)
            {
                return;
            }

            connectionText = "正在连接 Codex…";
            connected = false;
            ball.SetState(snapshot, connected);
            detail.UpdateConnection(connectionText, connected);

            service = new QuotaService(Dispatcher, demoMode);
            service.SnapshotChanged += OnSnapshotChanged;
            service.ConnectionChanged += OnConnectionChanged;
            service.Start();
        }

        private void StopService()
        {
            QuotaService active = service;
            service = null;
            if (active != null)
            {
                active.SnapshotChanged -= OnSnapshotChanged;
                active.ConnectionChanged -= OnConnectionChanged;
                active.Dispose();
            }

            snapshot = null;
            connected = false;
            connectionText = "等待 Codex 启动…";
            ball.SetState(snapshot, connected);
            detail.UpdateSnapshot(null);
            detail.UpdateConnection(connectionText, false);
        }

        private static ControlTemplate CreateContextMenuTemplate()
        {
            ControlTemplate template = new ControlTemplate(typeof(ContextMenu));
            FrameworkElementFactory shell = new FrameworkElementFactory(typeof(Border));
            shell.Name = "MenuShell";
            shell.SetBinding(Border.BackgroundProperty, new Binding("Background")
            {
                RelativeSource = RelativeSource.TemplatedParent
            });
            shell.SetBinding(Border.BorderBrushProperty, new Binding("BorderBrush")
            {
                RelativeSource = RelativeSource.TemplatedParent
            });
            shell.SetBinding(Border.BorderThicknessProperty, new Binding("BorderThickness")
            {
                RelativeSource = RelativeSource.TemplatedParent
            });
            shell.SetBinding(Border.PaddingProperty, new Binding("Padding")
            {
                RelativeSource = RelativeSource.TemplatedParent
            });
            shell.SetValue(Border.CornerRadiusProperty, new CornerRadius(10));
            shell.SetValue(Border.SnapsToDevicePixelsProperty, true);
            shell.SetValue(Border.EffectProperty, new DropShadowEffect
            {
                Color = Color.FromRgb(78, 132, 164),
                BlurRadius = 16,
                ShadowDepth = 3,
                Opacity = 0.24
            });

            FrameworkElementFactory itemsHost = new FrameworkElementFactory(typeof(StackPanel));
            itemsHost.SetValue(Panel.IsItemsHostProperty, true);
            itemsHost.SetValue(KeyboardNavigation.DirectionalNavigationProperty, KeyboardNavigationMode.Cycle);
            shell.AppendChild(itemsHost);
            template.VisualTree = shell;
            return template;
        }

        private static Style CreateMenuItemStyle()
        {
            Style style = new Style(typeof(MenuItem));
            style.Setters.Add(new Setter(Control.OverridesDefaultStyleProperty, true));
            style.Setters.Add(new Setter(Control.BackgroundProperty, Brushes.Transparent));
            style.Setters.Add(new Setter(Control.ForegroundProperty, UiPalette.Brush(UiPalette.Text)));
            style.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(9, 6, 12, 6)));
            style.Setters.Add(new Setter(Control.CursorProperty, Cursors.Hand));
            style.Setters.Add(new Setter(Control.HorizontalContentAlignmentProperty, HorizontalAlignment.Stretch));

            ControlTemplate template = new ControlTemplate(typeof(MenuItem));
            FrameworkElementFactory itemBorder = new FrameworkElementFactory(typeof(Border));
            itemBorder.Name = "ItemBorder";
            itemBorder.SetBinding(Border.BackgroundProperty, new Binding("Background")
            {
                RelativeSource = RelativeSource.TemplatedParent
            });
            itemBorder.SetBinding(Border.PaddingProperty, new Binding("Padding")
            {
                RelativeSource = RelativeSource.TemplatedParent
            });
            itemBorder.SetValue(Border.CornerRadiusProperty, new CornerRadius(7));
            itemBorder.SetValue(Border.MarginProperty, new Thickness(0.5));

            FrameworkElementFactory row = new FrameworkElementFactory(typeof(DockPanel));
            row.SetValue(DockPanel.LastChildFillProperty, true);

            FrameworkElementFactory checkMark = new FrameworkElementFactory(typeof(TextBlock));
            checkMark.Name = "CheckMark";
            checkMark.SetValue(TextBlock.TextProperty, "✓");
            checkMark.SetValue(TextBlock.WidthProperty, 18.0);
            checkMark.SetValue(TextBlock.FontSizeProperty, 11.0);
            checkMark.SetValue(TextBlock.FontWeightProperty, FontWeights.Bold);
            checkMark.SetValue(TextBlock.ForegroundProperty, UiPalette.Brush(UiPalette.Blue));
            checkMark.SetValue(TextBlock.OpacityProperty, 0.0);
            checkMark.SetValue(TextBlock.VerticalAlignmentProperty, VerticalAlignment.Center);
            checkMark.SetValue(DockPanel.DockProperty, Dock.Left);
            row.AppendChild(checkMark);

            FrameworkElementFactory presenter = new FrameworkElementFactory(typeof(ContentPresenter));
            presenter.SetBinding(ContentPresenter.ContentProperty, new Binding("Header")
            {
                RelativeSource = RelativeSource.TemplatedParent
            });
            presenter.SetBinding(ContentPresenter.ContentTemplateProperty, new Binding("HeaderTemplate")
            {
                RelativeSource = RelativeSource.TemplatedParent
            });
            presenter.SetBinding(TextElement.ForegroundProperty, new Binding("Foreground")
            {
                RelativeSource = RelativeSource.TemplatedParent
            });
            presenter.SetValue(ContentPresenter.RecognizesAccessKeyProperty, true);
            presenter.SetValue(ContentPresenter.VerticalAlignmentProperty, VerticalAlignment.Center);
            row.AppendChild(presenter);
            itemBorder.AppendChild(row);
            template.VisualTree = itemBorder;

            Trigger highlighted = new Trigger
            {
                Property = MenuItem.IsHighlightedProperty,
                Value = true
            };
            highlighted.Setters.Add(new Setter(
                Control.BackgroundProperty,
                UiPalette.Brush(Color.FromRgb(220, 243, 255))));
            template.Triggers.Add(highlighted);

            Trigger checkedTrigger = new Trigger
            {
                Property = MenuItem.IsCheckedProperty,
                Value = true
            };
            checkedTrigger.Setters.Add(new Setter(TextBlock.OpacityProperty, 1.0, "CheckMark"));
            template.Triggers.Add(checkedTrigger);

            Trigger disabled = new Trigger
            {
                Property = MenuItem.IsEnabledProperty,
                Value = false
            };
            disabled.Setters.Add(new Setter(UIElement.OpacityProperty, 0.45));
            template.Triggers.Add(disabled);

            style.Setters.Add(new Setter(Control.TemplateProperty, template));
            return style;
        }

        private void ToggleDetail()
        {
            if (!loaded)
            {
                return;
            }

            if (detail.IsVisible)
            {
                detail.Hide();
                return;
            }

            if ((DateTime.UtcNow - detail.LastAutoDismissedUtc).TotalMilliseconds < 450.0)
            {
                return;
            }

            detail.UpdateSnapshot(snapshot);
            detail.UpdateConnection(connectionText, connected);
            detail.Show();
            detail.PositionBeside(this, GetOrbScreenBounds());
            detail.Activate();
        }

        private void RestorePosition()
        {
            double savedLeft;
            double savedTop;
            if (AppSettings.TryLoadPosition(out savedLeft, out savedTop))
            {
                SetOrbOrigin(new Point(savedLeft, savedTop));
                ClampToWorkArea();
                return;
            }

            Rect workArea = SystemParameters.WorkArea;
            SetOrbOrigin(new Point(
                workArea.Right - appearance.Size - 22.0,
                workArea.Top + workArea.Height * 0.38));
        }

        private void ClampAndSavePosition()
        {
            ClampToWorkArea();
            Point orbOrigin = GetOrbOrigin();
            AppSettings.SavePosition(orbOrigin.X, orbOrigin.Y);
        }

        private void ClampToWorkArea()
        {
            Rect workArea = GetWorkArea();
            Point position = OrbWindowMetrics.ClampWindowOriginByOrb(
                new Point(Left, Top),
                appearance.Size,
                workArea);
            Left = position.X;
            Top = position.Y;
        }

        private Point GetOrbOrigin()
        {
            return OrbWindowMetrics.OrbOriginFromWindowOrigin(
                new Point(Left, Top),
                appearance.Size);
        }

        private void SetOrbOrigin(Point orbOrigin)
        {
            Point windowOrigin = OrbWindowMetrics.WindowOriginFromOrbOrigin(
                orbOrigin,
                appearance.Size);
            Left = windowOrigin.X;
            Top = windowOrigin.Y;
        }

        private Rect GetOrbScreenBounds()
        {
            Point origin = GetOrbOrigin();
            return new Rect(origin, new Size(appearance.Size, appearance.Size));
        }

        private Rect GetWorkArea()
        {
            try
            {
                IntPtr handle = new WindowInteropHelper(this).Handle;
                System.Windows.Forms.Screen screen = System.Windows.Forms.Screen.FromHandle(handle);
                System.Drawing.Rectangle pixels = screen.WorkingArea;
                PresentationSource source = PresentationSource.FromVisual(this);
                if (source != null && source.CompositionTarget != null)
                {
                    Matrix matrix = source.CompositionTarget.TransformFromDevice;
                    Point topLeft = matrix.Transform(new Point(pixels.Left, pixels.Top));
                    Point bottomRight = matrix.Transform(new Point(pixels.Right, pixels.Bottom));
                    return new Rect(topLeft, bottomRight);
                }
                return new Rect(pixels.Left, pixels.Top, pixels.Width, pixels.Height);
            }
            catch
            {
                return SystemParameters.WorkArea;
            }
        }
    }
}
