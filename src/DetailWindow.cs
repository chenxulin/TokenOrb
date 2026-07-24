using System;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;

namespace CodexQuotaBall
{
    public sealed class QuotaWindowRow : Border
    {
        private readonly TextBlock titleText;
        private readonly TextBlock remainingText;
        private readonly TextBlock resetText;
        private readonly QuotaBar bar;

        public QuotaWindowRow()
        {
            Background = UiPalette.Brush(UiPalette.PanelAlt);
            BorderBrush = UiPalette.Brush(Color.FromArgb(190, UiPalette.Border.R, UiPalette.Border.G, UiPalette.Border.B));
            BorderThickness = new Thickness(1);
            CornerRadius = new CornerRadius(12);
            Padding = new Thickness(12, 10, 12, 10);
            Margin = new Thickness(0, 0, 0, 10);

            Grid grid = new Grid();
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(9) });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(8) });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            Grid header = new Grid();
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            titleText = CreateText(12.5, FontWeights.SemiBold, UiPalette.Text);
            remainingText = CreateText(14.0, FontWeights.Bold, UiPalette.Green);
            Grid.SetColumn(remainingText, 1);
            header.Children.Add(titleText);
            header.Children.Add(remainingText);
            Grid.SetRow(header, 0);
            grid.Children.Add(header);

            bar = new QuotaBar();
            Grid.SetRow(bar, 2);
            grid.Children.Add(bar);

            Grid resetContent = new Grid();
            resetContent.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            resetContent.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(9) });
            resetContent.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            TextBlock resetLabel = CreateText(10.0, FontWeights.Normal, Color.FromRgb(92, 102, 110));
            resetLabel.Text = "下轮重置";
            resetText = CreateText(10.5, FontWeights.SemiBold, Color.FromRgb(56, 103, 130));
            resetText.TextTrimming = TextTrimming.CharacterEllipsis;
            Grid.SetColumn(resetText, 2);
            resetContent.Children.Add(resetLabel);
            resetContent.Children.Add(resetText);

            Border resetPanel = new Border
            {
                Background = UiPalette.Brush(Color.FromRgb(218, 241, 253)),
                BorderBrush = UiPalette.Brush(Color.FromArgb(145, UiPalette.Border.R, UiPalette.Border.G, UiPalette.Border.B)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(8, 5, 8, 5),
                Child = resetContent
            };
            Grid.SetRow(resetPanel, 4);
            grid.Children.Add(resetPanel);

            Child = grid;
        }

        public void UpdateValue(QuotaWindowInfo window)
        {
            if (window == null || !window.UsedPercent.HasValue)
            {
                Visibility = Visibility.Collapsed;
                return;
            }

            Visibility = Visibility.Visible;
            double remaining = window.RemainingPercent;
            Color accent = UiPalette.QuotaColor(remaining);
            titleText.Text = QuotaSnapshot.FormatWindowName(window) + "额度";
            remainingText.Text = "剩余 " + Math.Round(remaining).ToString("0", CultureInfo.InvariantCulture) + "%";
            remainingText.Foreground = UiPalette.Brush(accent);
            bar.RemainingPercent = remaining;
            bar.AccentColor = accent;
            resetText.Text = QuotaFormatting.FormatReset(window);
        }

        private static TextBlock CreateText(double size, FontWeight weight, Color color)
        {
            return new TextBlock
            {
                FontFamily = new FontFamily("Microsoft YaHei UI"),
                FontSize = size,
                FontWeight = weight,
                Foreground = UiPalette.Brush(color),
                VerticalAlignment = VerticalAlignment.Center
            };
        }
    }

    public sealed class DetailWindow : Window
    {
        private readonly TextBlock statusText;
        private readonly Border statusPill;
        private readonly QuotaWindowRow primaryRow;
        private readonly QuotaWindowRow secondaryRow;
        private readonly TextBlock creditsValue;
        private readonly TextBlock planValue;
        private readonly TextBlock sourceValue;
        private QuotaSnapshot snapshot;
        private string connectionText = "正在连接";
        private bool connected;

        public DateTime LastAutoDismissedUtc { get; private set; }

        public DetailWindow()
        {
            Width = 344;
            SizeToContent = SizeToContent.Height;
            WindowStyle = WindowStyle.None;
            ResizeMode = ResizeMode.NoResize;
            AllowsTransparency = true;
            Background = Brushes.Transparent;
            ShowInTaskbar = false;
            Topmost = true;
            FontFamily = new FontFamily("Microsoft YaHei UI");
            LastAutoDismissedUtc = DateTime.MinValue;
            Deactivated += OnDeactivated;

            Border shell = new Border
            {
                Background = UiPalette.Brush(Color.FromArgb(252, 248, 253, 255)),
                BorderBrush = UiPalette.Brush(UiPalette.Border),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(18),
                Padding = new Thickness(16),
                Margin = new Thickness(12),
                Effect = new DropShadowEffect
                {
                    Color = Color.FromRgb(78, 132, 164),
                    BlurRadius = 24,
                    ShadowDepth = 5,
                    Opacity = 0.28
                }
            };

            StackPanel content = new StackPanel();
            shell.Child = content;

            Grid header = new Grid { Margin = new Thickness(2, 0, 2, 14) };
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(8) });
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            StackPanel heading = new StackPanel();
            heading.Children.Add(new TextBlock
            {
                Text = "Codex 额度",
                Foreground = UiPalette.Brush(UiPalette.Text),
                FontSize = 18,
                FontWeight = FontWeights.Bold
            });
            header.Children.Add(heading);

            statusText = new TextBlock
            {
                Text = "连接中",
                FontSize = 10.5,
                FontWeight = FontWeights.SemiBold,
                VerticalAlignment = VerticalAlignment.Center
            };
            statusPill = new Border
            {
                CornerRadius = new CornerRadius(10),
                Padding = new Thickness(8, 4, 8, 4),
                VerticalAlignment = VerticalAlignment.Top,
                Child = statusText
            };
            Grid.SetColumn(statusPill, 1);
            header.Children.Add(statusPill);

            Border closeButton = new Border
            {
                Width = 25,
                Height = 25,
                CornerRadius = new CornerRadius(8),
                Background = UiPalette.Brush(Color.FromRgb(225, 244, 253)),
                Cursor = Cursors.Hand,
                Child = new TextBlock
                {
                    Text = "×",
                    Foreground = UiPalette.Brush(UiPalette.Muted),
                    FontSize = 16,
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center,
                    Margin = new Thickness(0, -2, 0, 0)
                }
            };
            closeButton.MouseLeftButtonUp += delegate { Hide(); };
            Grid.SetColumn(closeButton, 3);
            header.Children.Add(closeButton);
            content.Children.Add(header);

            primaryRow = new QuotaWindowRow();
            secondaryRow = new QuotaWindowRow();
            content.Children.Add(primaryRow);
            content.Children.Add(secondaryRow);

            Border accountBox = new Border
            {
                Background = UiPalette.Brush(Color.FromRgb(238, 249, 255)),
                CornerRadius = new CornerRadius(12),
                Padding = new Thickness(12, 8, 12, 8),
                Margin = new Thickness(0, 0, 0, 12)
            };
            Grid accountGrid = new Grid();
            accountGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            accountGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            accountGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            accountGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(7) });
            accountGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            TextBlock creditLabel = CreateInfoLabel("额外积分");
            creditsValue = CreateInfoValue("—");
            Grid.SetColumn(creditsValue, 1);
            accountGrid.Children.Add(creditLabel);
            accountGrid.Children.Add(creditsValue);

            TextBlock planLabel = CreateInfoLabel("当前套餐");
            planValue = CreateInfoValue("—");
            Grid.SetRow(planLabel, 2);
            Grid.SetRow(planValue, 2);
            Grid.SetColumn(planValue, 1);
            accountGrid.Children.Add(planLabel);
            accountGrid.Children.Add(planValue);
            accountBox.Child = accountGrid;
            content.Children.Add(accountBox);

            Border footer = new Border
            {
                BorderBrush = UiPalette.Brush(Color.FromRgb(190, 225, 243)),
                BorderThickness = new Thickness(0, 1, 0, 0),
                Padding = new Thickness(2, 10, 2, 0)
            };
            StackPanel footerContent = new StackPanel();
            sourceValue = new TextBlock
            {
                Foreground = UiPalette.Brush(UiPalette.Muted),
                FontSize = 10.5,
                TextWrapping = TextWrapping.Wrap
            };
            footerContent.Children.Add(sourceValue);
            footerContent.Children.Add(new TextBlock
            {
                Text = "只调用本机 Codex；不会读取 auth.json 或保存登录凭据",
                Foreground = UiPalette.Brush(Color.FromRgb(117, 149, 168)),
                FontSize = 9.5,
                Margin = new Thickness(0, 4, 0, 0),
                TextWrapping = TextWrapping.Wrap
            });
            footer.Child = footerContent;
            content.Children.Add(footer);

            Content = shell;
            UpdateConnection("正在连接", false);
        }

        private void OnDeactivated(object sender, EventArgs args)
        {
            if (!IsVisible)
            {
                return;
            }
            LastAutoDismissedUtc = DateTime.UtcNow;
            Hide();
        }

        public void UpdateSnapshot(QuotaSnapshot value)
        {
            snapshot = value;
            if (snapshot == null)
            {
                primaryRow.UpdateValue(null);
                secondaryRow.UpdateValue(null);
                creditsValue.Text = "—";
                planValue.Text = "—";
                sourceValue.Text = "等待 Codex 额度数据…";
                return;
            }

            primaryRow.UpdateValue(snapshot.Primary);
            secondaryRow.UpdateValue(snapshot.Secondary);
            creditsValue.Text = QuotaFormatting.FormatCredits(snapshot.Credits);
            planValue.Text = QuotaFormatting.FormatPlan(snapshot.PlanType);
            sourceValue.Text = "数据：" + (snapshot.Source ?? "Codex")
                + " · " + QuotaFormatting.FormatCapturedAt(snapshot);
        }

        public void UpdateConnection(string text, bool isConnected)
        {
            connectionText = String.IsNullOrWhiteSpace(text) ? "正在连接" : text;
            connected = isConnected;
            bool connecting = !connected
                && (connectionText.IndexOf("正在", StringComparison.OrdinalIgnoreCase) >= 0
                    || connectionText.IndexOf("已连接", StringComparison.OrdinalIgnoreCase) >= 0
                    || connectionText.IndexOf("准备", StringComparison.OrdinalIgnoreCase) >= 0);
            statusText.Text = connected ? "实时" : (connecting ? "连接中" : "本地");
            statusText.Foreground = UiPalette.Brush(connected ? UiPalette.Green : UiPalette.Amber);
            statusPill.Background = UiPalette.Brush(connected
                ? Color.FromArgb(35, UiPalette.Green.R, UiPalette.Green.G, UiPalette.Green.B)
                : Color.FromArgb(35, UiPalette.Amber.R, UiPalette.Amber.G, UiPalette.Amber.B));
            statusPill.ToolTip = connectionText;
        }

        public void RefreshTimeLabels()
        {
            if (snapshot != null)
            {
                primaryRow.UpdateValue(snapshot.Primary);
                secondaryRow.UpdateValue(snapshot.Secondary);
            }
        }

        public void PositionBeside(Window owner)
        {
            UpdateLayout();
            double actualWidth = ActualWidth > 0.0 ? ActualWidth : Width;
            double actualHeight = ActualHeight > 0.0 ? ActualHeight : 390.0;
            Rect workArea = GetWorkArea(owner);

            double right = owner.Left + owner.ActualWidth + 8.0;
            double left = owner.Left - actualWidth - 8.0;
            Left = right + actualWidth <= workArea.Right ? right : Math.Max(workArea.Left, left);
            Top = Math.Max(workArea.Top, Math.Min(owner.Top - 12.0, workArea.Bottom - actualHeight));
        }

        private static Rect GetWorkArea(Window window)
        {
            try
            {
                IntPtr handle = new WindowInteropHelper(window).Handle;
                System.Windows.Forms.Screen screen = System.Windows.Forms.Screen.FromHandle(handle);
                System.Drawing.Rectangle pixels = screen.WorkingArea;
                PresentationSource source = PresentationSource.FromVisual(window);
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

        private static TextBlock CreateInfoLabel(string text)
        {
            return new TextBlock
            {
                Text = text,
                Foreground = UiPalette.Brush(UiPalette.Muted),
                FontSize = 11,
                VerticalAlignment = VerticalAlignment.Center
            };
        }

        private static TextBlock CreateInfoValue(string text)
        {
            return new TextBlock
            {
                Text = text,
                Foreground = UiPalette.Brush(UiPalette.Text),
                FontSize = 11,
                FontWeight = FontWeights.SemiBold,
                TextAlignment = TextAlignment.Right,
                VerticalAlignment = VerticalAlignment.Center
            };
        }
    }
}
