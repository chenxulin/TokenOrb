using System;
using System.Globalization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using Forms = System.Windows.Forms;
using DrawingColor = System.Drawing.Color;

namespace CodexQuotaBall
{
    public sealed class AppearanceWindow : Window
    {
        private readonly Slider sizeSlider;
        private readonly TextBox sizeText;
        private readonly Border colorPreview;
        private readonly TextBlock colorCode;
        private Color selectedColor;
        private bool syncingSize;

        public AppearanceWindow(BallAppearanceSettings initial)
        {
            BallAppearanceSettings safeInitial = initial ?? new BallAppearanceSettings
            {
                Size = QuotaBallVisual.DefaultDiameter,
                AccentColor = UiPalette.Blue
            };
            SelectedSize = Math.Round(safeInitial.Size);
            SelectedColor = safeInitial.AccentColor;
            selectedColor = safeInitial.AccentColor;

            Title = "悬浮球外观";
            Width = 382;
            SizeToContent = SizeToContent.Height;
            WindowStyle = WindowStyle.None;
            ResizeMode = ResizeMode.NoResize;
            AllowsTransparency = true;
            Background = Brushes.Transparent;
            ShowInTaskbar = false;
            Topmost = true;
            WindowStartupLocation = WindowStartupLocation.CenterOwner;
            FontFamily = new FontFamily("Microsoft YaHei UI");

            Border shell = new Border
            {
                Background = UiPalette.Brush(Color.FromRgb(248, 253, 255)),
                BorderBrush = UiPalette.Brush(UiPalette.Border),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(18),
                Padding = new Thickness(20),
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

            Grid header = new Grid { Margin = new Thickness(0, 0, 0, 18) };
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            StackPanel heading = new StackPanel();
            heading.Children.Add(new TextBlock
            {
                Text = "悬浮球外观",
                FontSize = 18,
                FontWeight = FontWeights.Bold,
                Foreground = UiPalette.Brush(UiPalette.Text)
            });
            heading.Children.Add(new TextBlock
            {
                Text = "尺寸按 1 px 调节，颜色可使用预设或自定义",
                FontSize = 10.5,
                Foreground = UiPalette.Brush(UiPalette.Muted),
                Margin = new Thickness(0, 3, 0, 0)
            });
            header.Children.Add(heading);

            Border close = new Border
            {
                Width = 26,
                Height = 26,
                CornerRadius = new CornerRadius(13),
                Background = UiPalette.Brush(Color.FromRgb(225, 244, 253)),
                Cursor = Cursors.Hand,
                Child = new TextBlock
                {
                    Text = "×",
                    FontSize = 16,
                    Foreground = UiPalette.Brush(UiPalette.Muted),
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center,
                    Margin = new Thickness(0, -2, 0, 0)
                }
            };
            close.MouseLeftButtonUp += delegate { DialogResult = false; };
            Grid.SetColumn(close, 1);
            header.Children.Add(close);
            content.Children.Add(header);

            content.Children.Add(CreateSectionLabel("大小"));
            Grid sizeRow = new Grid { Margin = new Thickness(0, 8, 0, 20) };
            sizeRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            sizeRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
            sizeRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(58) });
            sizeRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(26) });

            sizeSlider = new Slider
            {
                Minimum = QuotaBallVisual.MinimumDiameter,
                Maximum = QuotaBallVisual.MaximumDiameter,
                TickFrequency = 1.0,
                IsSnapToTickEnabled = true,
                Value = SelectedSize,
                VerticalAlignment = VerticalAlignment.Center,
                ToolTip = "悬浮球直径"
            };
            AutomationProperties.SetName(sizeSlider, "悬浮球大小");
            sizeSlider.ValueChanged += OnSliderChanged;
            sizeRow.Children.Add(sizeSlider);

            sizeText = new TextBox
            {
                Text = SelectedSize.ToString("0", CultureInfo.InvariantCulture),
                Height = 30,
                Padding = new Thickness(6, 4, 6, 4),
                TextAlignment = TextAlignment.Center,
                VerticalContentAlignment = VerticalAlignment.Center,
                Foreground = UiPalette.Brush(UiPalette.Text),
                Background = UiPalette.Brush(Colors.White),
                BorderBrush = UiPalette.Brush(UiPalette.Border),
                BorderThickness = new Thickness(1)
            };
            AutomationProperties.SetName(sizeText, "大小像素值");
            sizeText.TextChanged += OnSizeTextChanged;
            Grid.SetColumn(sizeText, 2);
            sizeRow.Children.Add(sizeText);

            TextBlock px = new TextBlock
            {
                Text = "px",
                FontSize = 11,
                Foreground = UiPalette.Brush(UiPalette.Muted),
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(5, 0, 0, 0)
            };
            Grid.SetColumn(px, 3);
            sizeRow.Children.Add(px);
            content.Children.Add(sizeRow);

            content.Children.Add(CreateSectionLabel("颜色预设"));
            WrapPanel presets = new WrapPanel { Margin = new Thickness(-4, 7, -4, 10) };
            presets.Children.Add(CreateColorButton("浅蓝", Color.FromRgb(47, 164, 235)));
            presets.Children.Add(CreateColorButton("薄荷", Color.FromRgb(49, 190, 145)));
            presets.Children.Add(CreateColorButton("薰衣草", Color.FromRgb(141, 131, 246)));
            presets.Children.Add(CreateColorButton("晴空", Color.FromRgb(77, 141, 247)));
            presets.Children.Add(CreateColorButton("蜜桃", Color.FromRgb(244, 154, 106)));
            presets.Children.Add(CreateColorButton("玫瑰", Color.FromRgb(234, 113, 140)));
            content.Children.Add(presets);

            Grid customRow = new Grid { Margin = new Thickness(0, 0, 0, 22) };
            customRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            customRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
            customRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            customRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            Button custom = CreateActionButton("自定义颜色…", false);
            AutomationProperties.SetName(custom, "自定义颜色");
            custom.Click += OnCustomColor;
            customRow.Children.Add(custom);

            colorPreview = new Border
            {
                Width = 28,
                Height = 28,
                CornerRadius = new CornerRadius(14),
                BorderBrush = UiPalette.Brush(Color.FromArgb(90, 24, 72, 99)),
                BorderThickness = new Thickness(1),
                Background = UiPalette.Brush(selectedColor),
                VerticalAlignment = VerticalAlignment.Center
            };
            Grid.SetColumn(colorPreview, 2);
            customRow.Children.Add(colorPreview);

            colorCode = new TextBlock
            {
                Text = FormatColor(selectedColor),
                Foreground = UiPalette.Brush(UiPalette.Muted),
                FontSize = 11,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(8, 0, 0, 0)
            };
            Grid.SetColumn(colorCode, 3);
            customRow.Children.Add(colorCode);
            content.Children.Add(customRow);

            Grid actions = new Grid();
            actions.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            actions.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(10) });
            actions.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            Button cancel = CreateActionButton("取消", false);
            cancel.Click += delegate { DialogResult = false; };
            actions.Children.Add(cancel);
            Button save = CreateActionButton("保存", true);
            save.Click += OnSave;
            Grid.SetColumn(save, 2);
            actions.Children.Add(save);
            content.Children.Add(actions);

            Content = shell;
            KeyDown += OnWindowKeyDown;
        }

        public double SelectedSize { get; private set; }

        public Color SelectedColor { get; private set; }

        private static TextBlock CreateSectionLabel(string text)
        {
            return new TextBlock
            {
                Text = text,
                FontSize = 12,
                FontWeight = FontWeights.SemiBold,
                Foreground = UiPalette.Brush(UiPalette.Text)
            };
        }

        private Button CreateColorButton(string name, Color color)
        {
            Button button = new Button
            {
                Width = 48,
                Height = 42,
                Margin = new Thickness(4),
                Padding = new Thickness(4),
                Background = Brushes.Transparent,
                BorderBrush = UiPalette.Brush(UiPalette.Border),
                BorderThickness = new Thickness(1),
                Cursor = Cursors.Hand,
                ToolTip = name,
                Tag = color,
                Content = new Border
                {
                    Width = 25,
                    Height = 25,
                    CornerRadius = new CornerRadius(13),
                    Background = UiPalette.Brush(color)
                }
            };
            AutomationProperties.SetName(button, name);
            button.Click += delegate(object sender, RoutedEventArgs args)
            {
                Button selected = sender as Button;
                if (selected != null && selected.Tag is Color)
                {
                    SelectColor((Color)selected.Tag);
                }
            };
            return button;
        }

        private static Button CreateActionButton(string text, bool primary)
        {
            return new Button
            {
                Content = text,
                Height = 34,
                Padding = new Thickness(14, 5, 14, 5),
                Cursor = Cursors.Hand,
                FontSize = 11.5,
                FontWeight = primary ? FontWeights.SemiBold : FontWeights.Normal,
                Foreground = primary ? Brushes.White : UiPalette.Brush(UiPalette.Text),
                Background = primary ? UiPalette.Brush(UiPalette.Blue) : UiPalette.Brush(Color.FromRgb(232, 247, 255)),
                BorderBrush = UiPalette.Brush(primary ? UiPalette.Blue : UiPalette.Border),
                BorderThickness = new Thickness(1)
            };
        }

        private void OnSliderChanged(object sender, RoutedPropertyChangedEventArgs<double> args)
        {
            if (syncingSize || sizeText == null)
            {
                return;
            }
            syncingSize = true;
            sizeText.Text = Math.Round(sizeSlider.Value).ToString("0", CultureInfo.InvariantCulture);
            syncingSize = false;
        }

        private void OnSizeTextChanged(object sender, TextChangedEventArgs args)
        {
            if (syncingSize || sizeSlider == null)
            {
                return;
            }
            double value;
            if (!Double.TryParse(sizeText.Text, NumberStyles.Float, CultureInfo.InvariantCulture, out value))
            {
                return;
            }
            value = Math.Max(QuotaBallVisual.MinimumDiameter, Math.Min(value, QuotaBallVisual.MaximumDiameter));
            syncingSize = true;
            sizeSlider.Value = Math.Round(value);
            syncingSize = false;
        }

        private void OnCustomColor(object sender, RoutedEventArgs args)
        {
            using (Forms.ColorDialog dialog = new Forms.ColorDialog())
            {
                dialog.FullOpen = true;
                dialog.Color = DrawingColor.FromArgb(selectedColor.R, selectedColor.G, selectedColor.B);
                NativeWindowOwner owner = new NativeWindowOwner(new WindowInteropHelper(this).Handle);
                if (dialog.ShowDialog(owner) == Forms.DialogResult.OK)
                {
                    SelectColor(Color.FromRgb(dialog.Color.R, dialog.Color.G, dialog.Color.B));
                }
            }
        }

        private void SelectColor(Color color)
        {
            selectedColor = color;
            colorPreview.Background = UiPalette.Brush(color);
            colorCode.Text = FormatColor(color);
        }

        private void OnSave(object sender, RoutedEventArgs args)
        {
            double size;
            if (!Double.TryParse(sizeText.Text, NumberStyles.Float, CultureInfo.InvariantCulture, out size))
            {
                size = sizeSlider.Value;
            }
            SelectedSize = Math.Round(Math.Max(
                QuotaBallVisual.MinimumDiameter,
                Math.Min(size, QuotaBallVisual.MaximumDiameter)));
            SelectedColor = selectedColor;
            DialogResult = true;
        }

        private void OnWindowKeyDown(object sender, KeyEventArgs args)
        {
            if (args.Key == Key.Escape)
            {
                DialogResult = false;
                args.Handled = true;
            }
        }

        private static string FormatColor(Color color)
        {
            return "#"
                + color.R.ToString("X2", CultureInfo.InvariantCulture)
                + color.G.ToString("X2", CultureInfo.InvariantCulture)
                + color.B.ToString("X2", CultureInfo.InvariantCulture);
        }

        private sealed class NativeWindowOwner : Forms.IWin32Window
        {
            private readonly IntPtr handle;

            public NativeWindowOwner(IntPtr handle)
            {
                this.handle = handle;
            }

            public IntPtr Handle
            {
                get { return handle; }
            }
        }
    }
}
