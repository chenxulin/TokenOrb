using System;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
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

        public MainWindow(bool demoMode, bool companionUi)
        {
            this.demoMode = demoMode;
            this.companionUi = companionUi;
            appearance = AppSettings.LoadAppearance();
            Title = AppIdentity.ProductName;
            Width = appearance.Size;
            Height = appearance.Size;
            MinWidth = appearance.Size;
            MinHeight = appearance.Size;
            MaxWidth = appearance.Size;
            MaxHeight = appearance.Size;
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
            ball.SetAppearance(appearance.Size, appearance.AccentColor);
            AutomationProperties.SetName(ball, "Codex 剩余额度");
            ball.SetState(null, false, connectionText);
            ball.ContextMenu = CreateContextMenu();
            Content = ball;

            detail = new DetailWindow();
            processMonitor = new CodexProcessMonitor(Dispatcher);
            processMonitor.StateChanged += OnCodexRunningChanged;

            secondTimer = new DispatcherTimer(DispatcherPriority.Background, Dispatcher);
            secondTimer.Interval = TimeSpan.FromSeconds(1);
            secondTimer.Tick += delegate
            {
                detail.RefreshTimeLabels();
                ball.SetState(snapshot, connected, connectionText);
                UpdateToolTip();
            };

            Loaded += OnLoaded;
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

            processMonitor.Start();
            if (!followCodexEnabled)
            {
                ActivateForCodex();
            }
        }

        private void OnClosed(object sender, EventArgs args)
        {
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

        private void OnSnapshotChanged(QuotaSnapshot value)
        {
            snapshot = value;
            ball.SetState(snapshot, connected, connectionText);
            detail.UpdateSnapshot(snapshot);
            UpdateToolTip();
        }

        private void OnConnectionChanged(string text, bool isConnected)
        {
            connectionText = text;
            connected = isConnected;
            ball.SetState(snapshot, connected, connectionText);
            detail.UpdateConnection(connectionText, connected);
            UpdateToolTip();
        }

        private void OnMouseLeftButtonDown(object sender, MouseButtonEventArgs args)
        {
            if (args.ChangedButton != MouseButton.Left)
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
                SnapToEdgeAndSave();
                if (detail.IsVisible)
                {
                    detail.PositionBeside(this);
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
                OverridesDefaultStyle = true,
                Template = CreateContextMenuTemplate()
            };
            menu.Resources[typeof(MenuItem)] = CreateMenuItemStyle();
            menu.Resources[typeof(Separator)] = CreateSeparatorStyle();

            MenuItem detailsItem = new MenuItem { Header = "查看详细额度" };
            detailsItem.Click += delegate { ToggleDetail(); };
            menu.Items.Add(detailsItem);

            MenuItem refreshItem = new MenuItem { Header = "立即刷新" };
            refreshItem.Click += delegate
            {
                connectionText = "正在刷新…";
                connected = false;
                ball.SetState(snapshot, connected, connectionText);
                detail.UpdateConnection(connectionText, connected);
                if (service != null)
                {
                    service.ManualRefresh();
                }
            };
            menu.Items.Add(refreshItem);

            MenuItem appearanceItem = new MenuItem { Header = "外观" };
            appearanceItem.Click += delegate { OpenAppearanceWindow(); };
            menu.Items.Add(appearanceItem);
            menu.Items.Add(new Separator());

            MenuItem followCodexItem = new MenuItem
            {
                Header = "跟随 Codex 启动/关闭",
                IsCheckable = true,
                IsChecked = demoMode ? false : AppSettings.IsFollowCodexEnabled(),
                IsEnabled = !demoMode
            };
            followCodexItem.Click += delegate
            {
                try
                {
                    AppSettings.SetFollowCodexEnabled(followCodexItem.IsChecked);
                    followCodexEnabled = followCodexItem.IsChecked;
                    if (followCodexEnabled)
                    {
                        companionUi = true;
                        AppSettings.StartWatcherProcess();
                        OnCodexRunningChanged(processMonitor.CheckNow());
                    }
                    else
                    {
                        companionUi = false;
                        AppSettings.SignalWatcherExit();
                        ActivateForCodex();
                    }
                }
                catch (Exception exception)
                {
                    AppSettings.LogError(exception);
                    followCodexItem.IsChecked = !followCodexItem.IsChecked;
                    MessageBox.Show(
                        "无法更新 Codex 跟随设置：" + exception.Message,
                        AppIdentity.ProductName,
                        MessageBoxButton.OK,
                        MessageBoxImage.Warning);
                }
            };
            menu.Items.Add(followCodexItem);

            MenuItem aboutItem = new MenuItem { Header = "关于" };
            aboutItem.Click += delegate { OpenAboutWindow(); };
            menu.Items.Add(aboutItem);
            menu.Items.Add(new Separator());

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
            try
            {
                if (detail.IsVisible)
                {
                    detail.Hide();
                }

                AppearanceWindow window = new AppearanceWindow(appearance);
                window.Owner = this;
                bool? accepted = window.ShowDialog();
                if (accepted == true)
                {
                    ApplyAppearance(window.SelectedSize, window.SelectedColor, true);
                }
            }
            catch (Exception exception)
            {
                AppSettings.LogError(exception);
                MessageBox.Show(
                    "无法打开外观设置：" + exception.Message,
                    AppIdentity.ProductName,
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning);
            }
        }

        private void OpenAboutWindow()
        {
            try
            {
                if (detail.IsVisible)
                {
                    detail.Hide();
                }

                AboutWindow window = new AboutWindow();
                window.Owner = this;
                window.ShowDialog();
            }
            catch (Exception exception)
            {
                AppSettings.LogError(exception);
                MessageBox.Show(
                    "无法打开关于页面：" + exception.Message,
                    AppIdentity.ProductName,
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning);
            }
        }

        private void ApplyAppearance(double size, Color color, bool save)
        {
            double safeSize = Math.Round(Math.Max(
                QuotaBallVisual.MinimumDiameter,
                Math.Min(size, QuotaBallVisual.MaximumDiameter)));
            Rect workArea = GetWorkArea();
            bool onRight = Left + ActualWidth / 2.0 >= workArea.Left + workArea.Width / 2.0;

            MinWidth = 0.0;
            MinHeight = 0.0;
            MaxWidth = Double.PositiveInfinity;
            MaxHeight = Double.PositiveInfinity;
            Width = safeSize;
            Height = safeSize;
            MinWidth = safeSize;
            MinHeight = safeSize;
            MaxWidth = safeSize;
            MaxHeight = safeSize;
            ball.SetAppearance(safeSize, color);
            appearance = new BallAppearanceSettings { Size = safeSize, AccentColor = color };

            Left = onRight ? workArea.Right - safeSize - 10.0 : workArea.Left + 10.0;
            ClampToWorkArea();
            AppSettings.SavePosition(Left, Top);
            if (save)
            {
                AppSettings.SaveAppearance(safeSize, color);
            }
            if (detail.IsVisible)
            {
                detail.PositionBeside(this);
            }
        }

        private void OnCodexRunningChanged(bool running)
        {
            if (!loaded || demoMode || !followCodexEnabled)
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
            StartService();
        }

        private void DeactivateForCodex()
        {
            if (detail.IsVisible)
            {
                detail.Hide();
            }
            secondTimer.Stop();
            StopService();
            if (IsVisible)
            {
                Hide();
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
            ball.SetState(snapshot, connected, connectionText);
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
            ball.SetState(snapshot, connected, connectionText);
            detail.UpdateSnapshot(null);
            detail.UpdateConnection(connectionText, false);
            UpdateToolTip();
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

        private static Style CreateSeparatorStyle()
        {
            Style style = new Style(typeof(Separator));
            style.Setters.Add(new Setter(Control.OverridesDefaultStyleProperty, true));
            style.Setters.Add(new Setter(FrameworkElement.HeightProperty, 9.0));

            ControlTemplate template = new ControlTemplate(typeof(Separator));
            FrameworkElementFactory line = new FrameworkElementFactory(typeof(Border));
            line.SetValue(Border.HeightProperty, 1.0);
            line.SetValue(Border.MarginProperty, new Thickness(8, 4, 8, 4));
            line.SetValue(Border.BackgroundProperty, UiPalette.Brush(Color.FromRgb(198, 229, 245)));
            template.VisualTree = line;
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
            detail.PositionBeside(this);
            detail.Activate();
        }

        private void UpdateToolTip()
        {
            QuotaWindowInfo limiting = snapshot == null ? null : snapshot.MostRestrictiveWindow;
            if (limiting == null)
            {
                ball.ToolTip = connectionText + "\n点击查看详情，右键打开菜单";
                return;
            }

            ball.ToolTip = "Codex " + QuotaSnapshot.FormatWindowName(limiting)
                + "剩余 " + Math.Round(limiting.RemainingPercent).ToString("0") + "%\n"
                + QuotaFormatting.FormatReset(limiting) + "\n"
                + connectionText + " · 点击查看详情";
        }

        private void RestorePosition()
        {
            double savedLeft;
            double savedTop;
            if (AppSettings.TryLoadPosition(out savedLeft, out savedTop))
            {
                Left = savedLeft;
                Top = savedTop;
                ClampToWorkArea();
                return;
            }

            Rect workArea = SystemParameters.WorkArea;
            Left = workArea.Right - Width - 22.0;
            Top = workArea.Top + workArea.Height * 0.38;
        }

        private void SnapToEdgeAndSave()
        {
            Rect workArea = GetWorkArea();
            double center = Left + ActualWidth / 2.0;
            Left = center < workArea.Left + workArea.Width / 2.0
                ? workArea.Left + 10.0
                : workArea.Right - ActualWidth - 10.0;
            Top = Math.Max(workArea.Top + 8.0, Math.Min(Top, workArea.Bottom - ActualHeight - 8.0));
            AppSettings.SavePosition(Left, Top);
        }

        private void ClampToWorkArea()
        {
            Rect workArea = GetWorkArea();
            Left = Math.Max(workArea.Left, Math.Min(Left, workArea.Right - Width));
            Top = Math.Max(workArea.Top, Math.Min(Top, workArea.Bottom - Height));
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
