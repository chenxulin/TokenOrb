using System;
using System.Collections.Generic;
using System.Globalization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;

namespace CodexQuotaBall
{
    public sealed class AppearanceWindow : Window
    {
        private const double PreviewMinimumDiameter = 54.0;
        private const double PreviewMaximumDiameter = 82.0;
        private const double PreviewCardChromeHeight = 16.0;

        private readonly Slider sizeSlider;
        private readonly TextBox sizeText;
        private readonly TextBlock currentSizeText;
        private readonly Border colorPreview;
        private readonly TextBlock colorCode;
        private readonly QuotaBallVisual previewBall;
        private readonly TextBlock previewStyleName;
        private readonly List<Button> colorButtons = new List<Button>();
        private readonly Dictionary<QuotaTextStyle, Button> textStyleButtons =
            new Dictionary<QuotaTextStyle, Button>();
        private readonly Dictionary<int, Button> frameRateButtons =
            new Dictionary<int, Button>();
        private Color selectedColor;
        private QuotaTextStyle selectedTextStyle;
        private int selectedAnimationFrameRate;
        private bool syncingSize;

        public AppearanceWindow(BallAppearanceSettings initial)
        {
            BallAppearanceSettings safeInitial = initial ?? BallAppearanceDefaults.Create();
            SelectedSize = Math.Round(safeInitial.Size);
            SelectedColor = safeInitial.AccentColor;
            SelectedTextStyle = QuotaTextStyleCatalog.Normalize(safeInitial.TextStyle);
            SelectedAnimationFrameRate = AnimationFrameRateCatalog.Normalize(
                safeInitial.AnimationFrameRate);
            selectedColor = SelectedColor;
            selectedTextStyle = SelectedTextStyle;
            selectedAnimationFrameRate = SelectedAnimationFrameRate;

            Title = "个性化外观";
            Width = 740;
            Height = 500;
            WindowStyle = WindowStyle.None;
            ResizeMode = ResizeMode.NoResize;
            AllowsTransparency = true;
            Background = Brushes.Transparent;
            ShowInTaskbar = false;
            Topmost = false;
            WindowStartupLocation = WindowStartupLocation.CenterOwner;
            FontFamily = new FontFamily("Microsoft YaHei UI");
            UseLayoutRounding = true;
            SnapsToDevicePixels = true;
            AutomationProperties.SetName(this, "个性化外观设置");

            Border shell = AppearanceUi.CreateWindowShell();
            Grid layout = new Grid();
            layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            layout.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            shell.Child = layout;

            Grid header = new Grid { Margin = new Thickness(0, 0, 0, 12) };
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            StackPanel heading = new StackPanel
            {
                Cursor = Cursors.SizeAll,
                VerticalAlignment = VerticalAlignment.Top,
                Margin = new Thickness(0, 10, 0, 0)
            };
            heading.MouseLeftButtonDown += delegate
            {
                try { DragMove(); } catch { }
            };
            heading.Children.Add(new TextBlock
            {
                Text = "个性化外观",
                FontSize = 20,
                FontWeight = FontWeights.Bold,
                Foreground = UiPalette.Brush(UiPalette.Text)
            });
            heading.Children.Add(new TextBlock
            {
                Text = "调整尺寸、主题色、数字样式和动画帧率",
                FontSize = 11,
                Foreground = UiPalette.Brush(UiPalette.Muted),
                Margin = new Thickness(0, 4, 0, 0)
            });
            header.Children.Add(heading);
            layout.Children.Add(header);

            Grid sections = new Grid();
            sections.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            Grid.SetRow(sections, 1);
            layout.Children.Add(sections);

            previewBall = new QuotaBallVisual
            {
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                IsHitTestVisible = false
            };
            previewBall.SetState(
                new QuotaSnapshot
                {
                    Primary = new QuotaWindowInfo { UsedPercent = 70.0 },
                    CapturedAt = DateTimeOffset.Now,
                    Source = "外观预览",
                    IsLive = true
                },
                true);
            previewStyleName = new TextBlock
            {
                FontSize = 18,
                FontWeight = FontWeights.Bold,
                Foreground = UiPalette.Brush(UiPalette.Text),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                TextAlignment = TextAlignment.Center
            };
            Border previewCard = CreatePreviewCard();
            Grid.SetColumn(previewCard, 1);
            header.Children.Add(previewCard);

            sizeSlider = new Slider
            {
                Minimum = QuotaBallVisual.MinimumDiameter,
                Maximum = QuotaBallVisual.MaximumDiameter,
                TickFrequency = 1.0,
                IsSnapToTickEnabled = true,
                IsMoveToPointEnabled = true,
                Value = SelectedSize,
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = UiPalette.Brush(UiPalette.Blue),
                ToolTip = "悬浮球直径"
            };
            AutomationProperties.SetName(sizeSlider, "悬浮球大小");
            sizeSlider.ValueChanged += OnSliderChanged;

            sizeText = new TextBox
            {
                Text = SelectedSize.ToString("0", CultureInfo.InvariantCulture),
                Width = 35,
                Padding = new Thickness(0),
                HorizontalAlignment = HorizontalAlignment.Right,
                TextAlignment = TextAlignment.Right,
                VerticalContentAlignment = VerticalAlignment.Center,
                Foreground = UiPalette.Brush(UiPalette.Text),
                Background = Brushes.Transparent,
                BorderThickness = new Thickness(0),
                FontFamily = new FontFamily("Segoe UI"),
                FontSize = 12,
                FontWeight = FontWeights.SemiBold,
                CaretBrush = UiPalette.Brush(UiPalette.Blue)
            };
            AutomationProperties.SetName(sizeText, "大小像素值");
            currentSizeText = new TextBlock
            {
                FontSize = 10.5,
                FontWeight = FontWeights.SemiBold,
                Foreground = UiPalette.Brush(UiPalette.Blue),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            };
            UpdateCurrentSizeText(SelectedSize);
            sizeText.TextChanged += OnSizeTextChanged;
            Border sizeCard = CreateSizeCard();

            colorPreview = new Border
            {
                Width = 30,
                Height = 30,
                CornerRadius = new CornerRadius(15),
                BorderBrush = UiPalette.Brush(Color.FromArgb(95, 24, 72, 99)),
                BorderThickness = new Thickness(1),
                Background = UiPalette.Brush(selectedColor),
                VerticalAlignment = VerticalAlignment.Center
            };
            colorCode = new TextBlock
            {
                Text = AppearanceUi.FormatColor(selectedColor),
                Foreground = UiPalette.Brush(UiPalette.Text),
                FontFamily = new FontFamily("Consolas"),
                FontSize = 11,
                FontWeight = FontWeights.SemiBold,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(8, 0, 0, 0)
            };
            Border colorCard = CreateColorCard();
            Border textStyleCard = CreateTextStyleCard();
            Border frameRateCard = CreateFrameRateCard();

            Grid controlColumns = new Grid();
            controlColumns.RowDefinitions.Add(new RowDefinition
            {
                Height = GridLength.Auto
            });
            controlColumns.RowDefinitions.Add(new RowDefinition
            {
                Height = GridLength.Auto
            });
            controlColumns.ColumnDefinitions.Add(new ColumnDefinition
            {
                Width = new GridLength(1, GridUnitType.Star)
            });
            controlColumns.ColumnDefinitions.Add(new ColumnDefinition
            {
                Width = new GridLength(12)
            });
            controlColumns.ColumnDefinitions.Add(new ColumnDefinition
            {
                Width = new GridLength(1, GridUnitType.Star)
            });
            controlColumns.Children.Add(sizeCard);
            Grid.SetColumn(frameRateCard, 2);
            controlColumns.Children.Add(frameRateCard);
            Grid.SetRow(colorCard, 1);
            controlColumns.Children.Add(colorCard);
            Grid.SetRow(textStyleCard, 1);
            Grid.SetColumn(textStyleCard, 2);
            controlColumns.Children.Add(textStyleCard);
            Grid.SetRow(controlColumns, 0);
            sections.Children.Add(controlColumns);

            Grid actions = new Grid { Margin = new Thickness(0, 10, 0, 0) };
            actions.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            actions.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            actions.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(10) });
            actions.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            Button cancel = AppearanceUi.CreateActionButton("取消", false, 96);
            cancel.Click += delegate { DialogResult = false; };
            Grid.SetColumn(cancel, 1);
            actions.Children.Add(cancel);
            Button save = AppearanceUi.CreateActionButton("保存", true, 132);
            save.Click += OnSave;
            Grid.SetColumn(save, 3);
            actions.Children.Add(save);
            Grid.SetRow(actions, 2);
            layout.Children.Add(actions);

            Content = shell;
            KeyDown += OnWindowKeyDown;
            Loaded += delegate
            {
                UpdateColorSelection();
                UpdateTextStyleSelection();
                UpdateFrameRateSelection();
                UpdatePreview();
            };
        }

        public double SelectedSize { get; private set; }

        public Color SelectedColor { get; private set; }

        public QuotaTextStyle SelectedTextStyle { get; private set; }

        public int SelectedAnimationFrameRate { get; private set; }

        private Border CreatePreviewCard()
        {
            Grid previewLayout = new Grid();
            previewLayout.ColumnDefinitions.Add(new ColumnDefinition
            {
                Width = new GridLength(1, GridUnitType.Star)
            });
            previewLayout.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            Grid labels = new Grid();
            StackPanel status = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                HorizontalAlignment = HorizontalAlignment.Left,
                VerticalAlignment = VerticalAlignment.Top
            };
            status.Children.Add(new Border
            {
                Width = 7,
                Height = 7,
                CornerRadius = new CornerRadius(3.5),
                Background = UiPalette.Brush(Color.FromRgb(49, 190, 145)),
                Margin = new Thickness(0, 0, 6, 0),
                VerticalAlignment = VerticalAlignment.Center
            });
            TextBlock eyebrow = new TextBlock
            {
                Text = "实时预览",
                FontSize = 10,
                FontWeight = FontWeights.SemiBold,
                Foreground = UiPalette.Brush(UiPalette.Blue)
            };
            status.Children.Add(eyebrow);
            labels.Children.Add(previewStyleName);
            labels.Children.Add(status);
            previewLayout.Children.Add(labels);
            previewBall.Margin = new Thickness(18, 0, 0, 0);
            Grid.SetColumn(previewBall, 1);
            previewLayout.Children.Add(previewBall);

            return new Border
            {
                Background = UiPalette.Brush(Color.FromRgb(232, 247, 255)),
                BorderBrush = UiPalette.Brush(Color.FromArgb(190, UiPalette.Border.R, UiPalette.Border.G, UiPalette.Border.B)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(14),
                Padding = new Thickness(12, 7, 10, 7),
                Width = 236,
                Height = PreviewMaximumDiameter + PreviewCardChromeHeight,
                HorizontalAlignment = HorizontalAlignment.Right,
                VerticalAlignment = VerticalAlignment.Center,
                Child = previewLayout
            };
        }

        private Border CreateSizeCard()
        {
            Grid row = new Grid { Margin = new Thickness(0, 8, 0, 0) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(10) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(72) });
            row.Children.Add(sizeSlider);

            Grid fieldContent = new Grid();
            fieldContent.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            fieldContent.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            fieldContent.Children.Add(sizeText);
            TextBlock unit = new TextBlock
            {
                Text = "px",
                FontSize = 10.5,
                Foreground = UiPalette.Brush(UiPalette.Muted),
                Margin = new Thickness(4, 0, 0, 0),
                VerticalAlignment = VerticalAlignment.Center
            };
            Grid.SetColumn(unit, 1);
            fieldContent.Children.Add(unit);
            Border field = AppearanceUi.CreateFieldShell(fieldContent);
            field.Height = 30;
            Grid.SetColumn(field, 2);
            row.Children.Add(field);

            StackPanel body = new StackPanel();
            body.Children.Add(row);
            Grid limits = new Grid { Margin = new Thickness(1, 4, 82, 0) };
            limits.Children.Add(new TextBlock
            {
                Text = "24",
                FontSize = 9.5,
                Foreground = UiPalette.Brush(UiPalette.Muted),
                HorizontalAlignment = HorizontalAlignment.Left
            });
            limits.Children.Add(currentSizeText);
            TextBlock maximum = new TextBlock
            {
                Text = "160",
                FontSize = 9.5,
                Foreground = UiPalette.Brush(UiPalette.Muted),
                HorizontalAlignment = HorizontalAlignment.Right
            };
            limits.Children.Add(maximum);
            body.Children.Add(limits);
            return AppearanceUi.CreateSectionCard("悬浮球大小", body);
        }

        private Border CreateColorCard()
        {
            StackPanel body = new StackPanel();
            WrapPanel presets = new WrapPanel { Margin = new Thickness(-3, 8, -3, 6) };
            presets.Children.Add(CreateColorButton("浅蓝", Color.FromRgb(47, 164, 235)));
            presets.Children.Add(CreateColorButton("薄荷", Color.FromRgb(49, 190, 145)));
            presets.Children.Add(CreateColorButton("薰衣草", Color.FromRgb(141, 131, 246)));
            presets.Children.Add(CreateColorButton("晴空", Color.FromRgb(77, 141, 247)));
            presets.Children.Add(CreateColorButton("蜜桃", Color.FromRgb(244, 154, 106)));
            presets.Children.Add(CreateColorButton("玫瑰", Color.FromRgb(234, 113, 140)));
            body.Children.Add(presets);

            Grid customRow = new Grid { Margin = new Thickness(0, 2, 0, 0) };
            customRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            customRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(14) });
            customRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            customRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            Button custom = AppearanceUi.CreateActionButton("自定义取色", false, 118);
            custom.Height = 36;
            AutomationProperties.SetName(custom, "自定义取色");
            custom.Click += OnCustomColor;
            customRow.Children.Add(custom);
            Grid.SetColumn(colorPreview, 2);
            customRow.Children.Add(colorPreview);
            Grid.SetColumn(colorCode, 3);
            customRow.Children.Add(colorCode);
            body.Children.Add(customRow);
            return AppearanceUi.CreateSectionCard("主题颜色", body);
        }

        private Border CreateTextStyleCard()
        {
            UniformGrid options = new UniformGrid
            {
                Columns = 5,
                Margin = new Thickness(-4, 8, -4, 0)
            };
            options.Children.Add(CreateTextStyleButton(QuotaTextStyle.Minimal));
            options.Children.Add(CreateTextStyleButton(QuotaTextStyle.Geometric));
            options.Children.Add(CreateTextStyleButton(QuotaTextStyle.Condensed));
            options.Children.Add(CreateTextStyleButton(QuotaTextStyle.Rounded));
            options.Children.Add(CreateTextStyleButton(QuotaTextStyle.Emphasis));
            return AppearanceUi.CreateSectionCard(
                "数字样式",
                options);
        }

        private Border CreateFrameRateCard()
        {
            UniformGrid options = new UniformGrid
            {
                Columns = 5,
                Margin = new Thickness(-4, 8, -4, 0)
            };
            foreach (int frameRate in AnimationFrameRateCatalog.GetOptions())
            {
                options.Children.Add(CreateFrameRateButton(frameRate));
            }
            return AppearanceUi.CreateSectionCard("动画帧率", options);
        }

        private Button CreateColorButton(string name, Color color)
        {
            Border swatch = new Border
            {
                Width = 24,
                Height = 24,
                CornerRadius = new CornerRadius(12),
                Background = UiPalette.Brush(color),
                BorderBrush = UiPalette.Brush(Color.FromArgb(85, 255, 255, 255)),
                BorderThickness = new Thickness(1)
            };
            Button button = new Button
            {
                Width = 43,
                Height = 43,
                Margin = new Thickness(3),
                Padding = new Thickness(4),
                Background = Brushes.Transparent,
                BorderBrush = Brushes.Transparent,
                BorderThickness = new Thickness(1),
                Cursor = Cursors.Hand,
                ToolTip = name + " · " + AppearanceUi.FormatColor(color),
                Tag = color,
                Content = swatch,
                Template = AppearanceUi.CreateRoundedButtonTemplate(11)
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
            colorButtons.Add(button);
            return button;
        }

        private Button CreateTextStyleButton(QuotaTextStyle style)
        {
            StackPanel content = new StackPanel();
            content.Children.Add(new QuotaTextStylePreview
            {
                TextStyle = style,
                Width = 48,
                Height = 36
            });
            content.Children.Add(new TextBlock
            {
                Text = QuotaTextStyleCatalog.GetDisplayName(style),
                FontSize = 10.5,
                TextAlignment = TextAlignment.Center,
                HorizontalAlignment = HorizontalAlignment.Center,
                Foreground = UiPalette.Brush(UiPalette.Text),
                Margin = new Thickness(0, 2, 0, 0)
            });
            Button button = new Button
            {
                Height = 76,
                Margin = new Thickness(3),
                Padding = new Thickness(1),
                Background = UiPalette.Brush(Color.FromRgb(250, 254, 255)),
                BorderBrush = UiPalette.Brush(Color.FromArgb(150, UiPalette.Border.R, UiPalette.Border.G, UiPalette.Border.B)),
                BorderThickness = new Thickness(1),
                Cursor = Cursors.Hand,
                Tag = style,
                Content = content,
                Template = AppearanceUi.CreateRoundedButtonTemplate(12)
            };
            AutomationProperties.SetName(button, "数字样式 " + QuotaTextStyleCatalog.GetDisplayName(style));
            button.Click += delegate(object sender, RoutedEventArgs args)
            {
                Button selected = sender as Button;
                if (selected != null && selected.Tag is QuotaTextStyle)
                {
                    SelectTextStyle((QuotaTextStyle)selected.Tag);
                }
            };
            textStyleButtons[style] = button;
            return button;
        }

        private Button CreateFrameRateButton(int frameRate)
        {
            Button button = new Button
            {
                Height = 40,
                Margin = new Thickness(4),
                Padding = new Thickness(2),
                Background = UiPalette.Brush(Color.FromRgb(250, 254, 255)),
                BorderBrush = UiPalette.Brush(Color.FromArgb(
                    150,
                    UiPalette.Border.R,
                    UiPalette.Border.G,
                    UiPalette.Border.B)),
                BorderThickness = new Thickness(1),
                Cursor = Cursors.Hand,
                Tag = frameRate,
                Content = new TextBlock
                {
                    Text = frameRate.ToString(CultureInfo.InvariantCulture) + " FPS",
                    FontSize = 10.5,
                    FontWeight = FontWeights.SemiBold,
                    Foreground = UiPalette.Brush(UiPalette.Text),
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center
                },
                Template = AppearanceUi.CreateRoundedButtonTemplate(11)
            };
            AutomationProperties.SetName(button, frameRate + " FPS");
            button.Click += delegate(object sender, RoutedEventArgs args)
            {
                Button selected = sender as Button;
                if (selected != null && selected.Tag is int)
                {
                    SelectAnimationFrameRate((int)selected.Tag);
                }
            };
            frameRateButtons[frameRate] = button;
            return button;
        }

        private void OnSliderChanged(object sender, RoutedPropertyChangedEventArgs<double> args)
        {
            if (syncingSize || sizeText == null)
            {
                return;
            }
            double roundedSize = Math.Round(sizeSlider.Value);
            syncingSize = true;
            sizeText.Text = roundedSize.ToString("0", CultureInfo.InvariantCulture);
            syncingSize = false;
            UpdateCurrentSizeText(roundedSize);
            UpdatePreview();
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
            UpdateCurrentSizeText(sizeSlider.Value);
            UpdatePreview();
        }

        private void UpdateCurrentSizeText(double value)
        {
            string pixels = Math.Round(value).ToString("0", CultureInfo.InvariantCulture);
            currentSizeText.Text = pixels + " px";
            AutomationProperties.SetName(currentSizeText, "当前悬浮球大小 " + pixels + " 像素");
        }

        private void OnCustomColor(object sender, RoutedEventArgs args)
        {
            ThemedColorPickerWindow picker = new ThemedColorPickerWindow(selectedColor)
            {
                Owner = this
            };
            if (picker.ShowDialog() == true)
            {
                SelectColor(picker.SelectedColor);
            }
        }

        private void SelectColor(Color color)
        {
            selectedColor = Color.FromRgb(color.R, color.G, color.B);
            colorPreview.Background = UiPalette.Brush(selectedColor);
            colorCode.Text = AppearanceUi.FormatColor(selectedColor);
            UpdateColorSelection();
            UpdatePreview();
        }

        private void SelectTextStyle(QuotaTextStyle style)
        {
            selectedTextStyle = QuotaTextStyleCatalog.Normalize(style);
            UpdateTextStyleSelection();
            UpdatePreview();
        }

        private void SelectAnimationFrameRate(int frameRate)
        {
            selectedAnimationFrameRate = AnimationFrameRateCatalog.Normalize(frameRate);
            UpdateFrameRateSelection();
            UpdatePreview();
        }

        private void UpdateColorSelection()
        {
            string selectedHex = AppearanceUi.FormatColor(selectedColor);
            foreach (Button button in colorButtons)
            {
                Color color = (Color)button.Tag;
                bool selected = AppearanceUi.FormatColor(color) == selectedHex;
                button.Background = selected
                    ? UiPalette.Brush(Color.FromArgb(36, color.R, color.G, color.B))
                    : Brushes.Transparent;
                button.BorderBrush = selected
                    ? UiPalette.Brush(color)
                    : Brushes.Transparent;
                button.BorderThickness = new Thickness(selected ? 2 : 1);
            }
        }

        private void UpdateTextStyleSelection()
        {
            foreach (KeyValuePair<QuotaTextStyle, Button> pair in textStyleButtons)
            {
                bool selected = pair.Key == selectedTextStyle;
                pair.Value.Background = selected
                    ? UiPalette.Brush(Color.FromRgb(226, 245, 255))
                    : UiPalette.Brush(Color.FromRgb(250, 254, 255));
                pair.Value.BorderBrush = selected
                    ? UiPalette.Brush(UiPalette.Blue)
                    : UiPalette.Brush(Color.FromArgb(150, UiPalette.Border.R, UiPalette.Border.G, UiPalette.Border.B));
                pair.Value.BorderThickness = new Thickness(selected ? 2 : 1);
            }
        }

        private void UpdateFrameRateSelection()
        {
            foreach (KeyValuePair<int, Button> pair in frameRateButtons)
            {
                bool selected = pair.Key == selectedAnimationFrameRate;
                pair.Value.Background = selected
                    ? UiPalette.Brush(Color.FromRgb(226, 245, 255))
                    : UiPalette.Brush(Color.FromRgb(250, 254, 255));
                pair.Value.BorderBrush = selected
                    ? UiPalette.Brush(UiPalette.Blue)
                    : UiPalette.Brush(Color.FromArgb(
                        150,
                        UiPalette.Border.R,
                        UiPalette.Border.G,
                        UiPalette.Border.B));
                pair.Value.BorderThickness = new Thickness(selected ? 2 : 1);
            }
        }

        private void UpdatePreview()
        {
            if (previewBall == null || previewStyleName == null)
            {
                return;
            }
            double configuredSize = sizeSlider == null
                ? SelectedSize
                : Math.Round(sizeSlider.Value);
            double previewSize = Math.Max(
                PreviewMinimumDiameter,
                Math.Min(PreviewMaximumDiameter, configuredSize));
            previewBall.SetAppearance(
                previewSize,
                selectedColor,
                selectedTextStyle,
                selectedAnimationFrameRate);
            previewStyleName.Text = QuotaTextStyleCatalog.GetDisplayName(selectedTextStyle);
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
            SelectedTextStyle = selectedTextStyle;
            SelectedAnimationFrameRate = selectedAnimationFrameRate;
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
    }

    internal sealed class QuotaTextStylePreview : FrameworkElement
    {
        private QuotaTextStyle style;

        public QuotaTextStyle TextStyle
        {
            get { return style; }
            set
            {
                style = QuotaTextStyleCatalog.Normalize(value);
                InvalidateVisual();
            }
        }

        public QuotaTextStylePreview()
        {
            MinWidth = 0;
            TextOptions.SetTextFormattingMode(this, TextFormattingMode.Display);
            TextOptions.SetTextRenderingMode(this, TextRenderingMode.ClearType);
        }

        protected override void OnRender(DrawingContext drawingContext)
        {
            base.OnRender(drawingContext);
            QuotaBallVisual.DrawQuotaText(
                drawingContext,
                "30%",
                72.0,
                UiPalette.Brush(Color.FromRgb(20, 72, 99)),
                new Point(ActualWidth / 2.0, ActualHeight / 2.0),
                VisualTreeHelper.GetDpi(this).PixelsPerDip,
                style);
        }
    }

    internal sealed class ThemedColorPickerWindow : Window
    {
        private readonly ColorSpectrum spectrum;
        private readonly HueStrip hueStrip;
        private readonly Border preview;
        private readonly TextBox hexText;
        private readonly TextBox redText;
        private readonly TextBox greenText;
        private readonly TextBox blueText;
        private Color selectedColor;
        private bool syncing;

        public ThemedColorPickerWindow(Color initialColor)
        {
            selectedColor = Color.FromRgb(initialColor.R, initialColor.G, initialColor.B);
            Title = "自定义取色";
            Width = 470;
            SizeToContent = SizeToContent.Height;
            WindowStyle = WindowStyle.None;
            ResizeMode = ResizeMode.NoResize;
            AllowsTransparency = true;
            Background = Brushes.Transparent;
            ShowInTaskbar = false;
            Topmost = false;
            WindowStartupLocation = WindowStartupLocation.CenterOwner;
            FontFamily = new FontFamily("Microsoft YaHei UI");
            UseLayoutRounding = true;
            AutomationProperties.SetName(this, "自定义取色器");

            spectrum = new ColorSpectrum { Height = 190 };
            hueStrip = new HueStrip { Height = 20, Margin = new Thickness(0, 10, 0, 0) };
            preview = new Border
            {
                Width = 44,
                Height = 44,
                CornerRadius = new CornerRadius(13),
                BorderBrush = UiPalette.Brush(Color.FromArgb(100, 24, 72, 99)),
                BorderThickness = new Thickness(1)
            };
            hexText = CreateValueTextBox(82, TextAlignment.Center);
            redText = CreateValueTextBox(48, TextAlignment.Center);
            greenText = CreateValueTextBox(48, TextAlignment.Center);
            blueText = CreateValueTextBox(48, TextAlignment.Center);

            Border shell = AppearanceUi.CreateWindowShell();
            StackPanel content = new StackPanel();
            shell.Child = content;

            Grid header = new Grid { Margin = new Thickness(0, 0, 0, 16) };
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            StackPanel heading = new StackPanel { Cursor = Cursors.SizeAll };
            heading.MouseLeftButtonDown += delegate
            {
                try { DragMove(); } catch { }
            };
            heading.Children.Add(new TextBlock
            {
                Text = "自定义取色",
                FontSize = 19,
                FontWeight = FontWeights.Bold,
                Foreground = UiPalette.Brush(UiPalette.Text)
            });
            heading.Children.Add(new TextBlock
            {
                Text = "拖动色面与色相条，或直接输入颜色值",
                FontSize = 10.5,
                Foreground = UiPalette.Brush(UiPalette.Muted),
                Margin = new Thickness(0, 4, 0, 0)
            });
            header.Children.Add(heading);
            Button close = AppearanceUi.CreateCloseButton();
            close.Click += delegate { DialogResult = false; };
            Grid.SetColumn(close, 1);
            header.Children.Add(close);
            content.Children.Add(header);

            Border pickerCard = new Border
            {
                Background = UiPalette.Brush(Colors.White),
                BorderBrush = UiPalette.Brush(Color.FromArgb(175, UiPalette.Border.R, UiPalette.Border.G, UiPalette.Border.B)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(14),
                Padding = new Thickness(12),
                Child = CreatePickerSurface()
            };
            content.Children.Add(pickerCard);
            content.Children.Add(CreateValueArea());

            Grid actions = new Grid { Margin = new Thickness(0, 16, 0, 0) };
            actions.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            actions.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            actions.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(10) });
            actions.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            TextBlock hint = new TextBlock
            {
                Text = "支持 HEX 与 RGB",
                FontSize = 10.5,
                Foreground = UiPalette.Brush(UiPalette.Muted),
                VerticalAlignment = VerticalAlignment.Center
            };
            actions.Children.Add(hint);
            Button cancel = AppearanceUi.CreateActionButton("取消", false, 88);
            cancel.Click += delegate { DialogResult = false; };
            Grid.SetColumn(cancel, 1);
            actions.Children.Add(cancel);
            Button confirm = AppearanceUi.CreateActionButton("确认", true, 126);
            confirm.Click += delegate
            {
                SelectedColor = selectedColor;
                DialogResult = true;
            };
            Grid.SetColumn(confirm, 3);
            actions.Children.Add(confirm);
            content.Children.Add(actions);

            Content = shell;
            SelectedColor = selectedColor;
            SetSelectedColor(selectedColor);
            spectrum.ColorChanged += OnSpectrumChanged;
            hueStrip.HueChanged += OnHueChanged;
            hexText.TextChanged += OnHexTextChanged;
            redText.TextChanged += OnRgbTextChanged;
            greenText.TextChanged += OnRgbTextChanged;
            blueText.TextChanged += OnRgbTextChanged;
            KeyDown += delegate(object sender, KeyEventArgs args)
            {
                if (args.Key == Key.Escape)
                {
                    DialogResult = false;
                    args.Handled = true;
                }
            };
        }

        public Color SelectedColor { get; private set; }

        private StackPanel CreatePickerSurface()
        {
            StackPanel panel = new StackPanel();
            panel.Children.Add(spectrum);
            panel.Children.Add(hueStrip);
            return panel;
        }

        private Border CreateValueArea()
        {
            Grid values = new Grid();
            values.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            values.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(14) });
            values.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            values.Children.Add(preview);

            StackPanel fields = new StackPanel();
            Grid hexRow = new Grid();
            hexRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            hexRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(8) });
            hexRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            TextBlock hexLabel = CreateValueLabel("HEX");
            hexRow.Children.Add(hexLabel);
            Border hexShell = AppearanceUi.CreateFieldShell(hexText);
            Grid.SetColumn(hexShell, 2);
            hexRow.Children.Add(hexShell);
            fields.Children.Add(hexRow);

            StackPanel rgb = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Margin = new Thickness(0, 8, 0, 0)
            };
            rgb.Children.Add(CreateChannelField("R", redText));
            rgb.Children.Add(CreateChannelField("G", greenText));
            rgb.Children.Add(CreateChannelField("B", blueText));
            fields.Children.Add(rgb);
            Grid.SetColumn(fields, 2);
            values.Children.Add(fields);

            return new Border
            {
                Background = UiPalette.Brush(Color.FromRgb(238, 249, 255)),
                BorderBrush = UiPalette.Brush(Color.FromArgb(145, UiPalette.Border.R, UiPalette.Border.G, UiPalette.Border.B)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(13),
                Padding = new Thickness(12),
                Margin = new Thickness(0, 12, 0, 0),
                Child = values
            };
        }

        private static Border CreateChannelField(string label, TextBox field)
        {
            StackPanel row = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Margin = new Thickness(0, 0, 12, 0)
            };
            row.Children.Add(CreateValueLabel(label));
            Border shell = AppearanceUi.CreateFieldShell(field);
            shell.Margin = new Thickness(6, 0, 0, 0);
            row.Children.Add(shell);
            return new Border { Child = row };
        }

        private static TextBlock CreateValueLabel(string text)
        {
            return new TextBlock
            {
                Text = text,
                FontSize = 10.5,
                FontWeight = FontWeights.SemiBold,
                Foreground = UiPalette.Brush(UiPalette.Muted),
                VerticalAlignment = VerticalAlignment.Center
            };
        }

        private static TextBox CreateValueTextBox(double width, TextAlignment alignment)
        {
            return new TextBox
            {
                Width = width,
                Height = 27,
                Padding = new Thickness(5, 3, 5, 3),
                TextAlignment = alignment,
                VerticalContentAlignment = VerticalAlignment.Center,
                Background = Brushes.Transparent,
                BorderThickness = new Thickness(0),
                Foreground = UiPalette.Brush(UiPalette.Text),
                CaretBrush = UiPalette.Brush(UiPalette.Blue),
                FontFamily = new FontFamily("Consolas"),
                FontSize = 11
            };
        }

        private void OnSpectrumChanged(object sender, EventArgs args)
        {
            if (syncing)
            {
                return;
            }
            selectedColor = spectrum.SelectedColor;
            SyncValueFields();
        }

        private void OnHueChanged(object sender, EventArgs args)
        {
            if (syncing)
            {
                return;
            }
            spectrum.Hue = hueStrip.Hue;
            selectedColor = spectrum.SelectedColor;
            SyncValueFields();
        }

        private void OnHexTextChanged(object sender, TextChangedEventArgs args)
        {
            if (syncing)
            {
                return;
            }
            Color color;
            if (ColorMath.TryParseHex(hexText.Text, out color))
            {
                SetSelectedColor(color);
            }
        }

        private void OnRgbTextChanged(object sender, TextChangedEventArgs args)
        {
            if (syncing)
            {
                return;
            }
            byte red;
            byte green;
            byte blue;
            if (Byte.TryParse(redText.Text, NumberStyles.Integer, CultureInfo.InvariantCulture, out red)
                && Byte.TryParse(greenText.Text, NumberStyles.Integer, CultureInfo.InvariantCulture, out green)
                && Byte.TryParse(blueText.Text, NumberStyles.Integer, CultureInfo.InvariantCulture, out blue))
            {
                SetSelectedColor(Color.FromRgb(red, green, blue));
            }
        }

        private void SetSelectedColor(Color color)
        {
            selectedColor = Color.FromRgb(color.R, color.G, color.B);
            double hue;
            double saturation;
            double value;
            ColorMath.ToHsv(selectedColor, out hue, out saturation, out value);
            syncing = true;
            hueStrip.Hue = hue;
            spectrum.SetHsv(hue, saturation, value);
            syncing = false;
            SyncValueFields();
        }

        private void SyncValueFields()
        {
            syncing = true;
            preview.Background = UiPalette.Brush(selectedColor);
            hexText.Text = AppearanceUi.FormatColor(selectedColor);
            redText.Text = selectedColor.R.ToString(CultureInfo.InvariantCulture);
            greenText.Text = selectedColor.G.ToString(CultureInfo.InvariantCulture);
            blueText.Text = selectedColor.B.ToString(CultureInfo.InvariantCulture);
            syncing = false;
        }
    }

    internal sealed class ColorSpectrum : FrameworkElement
    {
        private double hue;
        private double saturation = 1.0;
        private double value = 1.0;

        public ColorSpectrum()
        {
            Cursor = Cursors.Cross;
            Focusable = true;
            AutomationProperties.SetName(this, "饱和度和亮度色面");
        }

        public event EventHandler ColorChanged;

        public double Hue
        {
            get { return hue; }
            set
            {
                hue = ColorMath.NormalizeHue(value);
                InvalidateVisual();
            }
        }

        public Color SelectedColor
        {
            get { return ColorMath.FromHsv(hue, saturation, value); }
        }

        public void SetHsv(double newHue, double newSaturation, double newValue)
        {
            hue = ColorMath.NormalizeHue(newHue);
            saturation = Math.Max(0.0, Math.Min(1.0, newSaturation));
            value = Math.Max(0.0, Math.Min(1.0, newValue));
            InvalidateVisual();
        }

        protected override void OnRender(DrawingContext drawingContext)
        {
            base.OnRender(drawingContext);
            Rect bounds = new Rect(0, 0, Math.Max(0.0, ActualWidth), Math.Max(0.0, ActualHeight));
            if (bounds.Width <= 0.0 || bounds.Height <= 0.0)
            {
                return;
            }

            RectangleGeometry clip = new RectangleGeometry(bounds, 10, 10);
            drawingContext.PushClip(clip);
            drawingContext.DrawRectangle(UiPalette.Brush(ColorMath.FromHsv(hue, 1.0, 1.0)), null, bounds);

            LinearGradientBrush whiteFade = new LinearGradientBrush
            {
                StartPoint = new Point(0, 0.5),
                EndPoint = new Point(1, 0.5)
            };
            whiteFade.GradientStops.Add(new GradientStop(Colors.White, 0.0));
            whiteFade.GradientStops.Add(new GradientStop(Color.FromArgb(0, 255, 255, 255), 1.0));
            drawingContext.DrawRectangle(whiteFade, null, bounds);

            LinearGradientBrush blackFade = new LinearGradientBrush
            {
                StartPoint = new Point(0.5, 0),
                EndPoint = new Point(0.5, 1)
            };
            blackFade.GradientStops.Add(new GradientStop(Color.FromArgb(0, 0, 0, 0), 0.0));
            blackFade.GradientStops.Add(new GradientStop(Colors.Black, 1.0));
            drawingContext.DrawRectangle(blackFade, null, bounds);
            drawingContext.Pop();

            Pen border = new Pen(UiPalette.Brush(Color.FromArgb(125, 24, 72, 99)), 1.0);
            drawingContext.DrawRoundedRectangle(null, border, bounds, 10, 10);
            Point marker = new Point(saturation * bounds.Width, (1.0 - value) * bounds.Height);
            drawingContext.DrawEllipse(
                UiPalette.Brush(Color.FromArgb(28, 0, 0, 0)),
                new Pen(Brushes.White, 2.0),
                marker,
                7.0,
                7.0);
            drawingContext.DrawEllipse(
                null,
                new Pen(UiPalette.Brush(Color.FromArgb(150, 24, 72, 99)), 1.0),
                marker,
                8.0,
                8.0);
        }

        protected override void OnMouseLeftButtonDown(MouseButtonEventArgs args)
        {
            base.OnMouseLeftButtonDown(args);
            Focus();
            CaptureMouse();
            UpdateFromPoint(args.GetPosition(this));
            args.Handled = true;
        }

        protected override void OnMouseMove(MouseEventArgs args)
        {
            base.OnMouseMove(args);
            if (IsMouseCaptured && args.LeftButton == MouseButtonState.Pressed)
            {
                UpdateFromPoint(args.GetPosition(this));
                args.Handled = true;
            }
        }

        protected override void OnMouseLeftButtonUp(MouseButtonEventArgs args)
        {
            base.OnMouseLeftButtonUp(args);
            if (IsMouseCaptured)
            {
                UpdateFromPoint(args.GetPosition(this));
                ReleaseMouseCapture();
                args.Handled = true;
            }
        }

        protected override void OnKeyDown(KeyEventArgs args)
        {
            base.OnKeyDown(args);
            double step = Keyboard.Modifiers == ModifierKeys.Shift ? 0.05 : 0.01;
            switch (args.Key)
            {
                case Key.Left: saturation -= step; break;
                case Key.Right: saturation += step; break;
                case Key.Up: value += step; break;
                case Key.Down: value -= step; break;
                default: return;
            }
            saturation = Math.Max(0.0, Math.Min(1.0, saturation));
            value = Math.Max(0.0, Math.Min(1.0, value));
            InvalidateVisual();
            RaiseColorChanged();
            args.Handled = true;
        }

        private void UpdateFromPoint(Point point)
        {
            saturation = Math.Max(0.0, Math.Min(1.0, point.X / Math.Max(1.0, ActualWidth)));
            value = 1.0 - Math.Max(0.0, Math.Min(1.0, point.Y / Math.Max(1.0, ActualHeight)));
            InvalidateVisual();
            RaiseColorChanged();
        }

        private void RaiseColorChanged()
        {
            EventHandler handler = ColorChanged;
            if (handler != null)
            {
                handler(this, EventArgs.Empty);
            }
        }
    }

    internal sealed class HueStrip : FrameworkElement
    {
        private double hue;

        public HueStrip()
        {
            Cursor = Cursors.Hand;
            Focusable = true;
            AutomationProperties.SetName(this, "色相选择条");
        }

        public event EventHandler HueChanged;

        public double Hue
        {
            get { return hue; }
            set
            {
                hue = ColorMath.NormalizeHue(value);
                InvalidateVisual();
            }
        }

        protected override void OnRender(DrawingContext drawingContext)
        {
            base.OnRender(drawingContext);
            Rect bounds = new Rect(0, 0, Math.Max(0.0, ActualWidth), Math.Max(0.0, ActualHeight));
            if (bounds.Width <= 0.0 || bounds.Height <= 0.0)
            {
                return;
            }

            LinearGradientBrush rainbow = new LinearGradientBrush
            {
                StartPoint = new Point(0, 0.5),
                EndPoint = new Point(1, 0.5)
            };
            rainbow.GradientStops.Add(new GradientStop(Colors.Red, 0.0));
            rainbow.GradientStops.Add(new GradientStop(Colors.Yellow, 1.0 / 6.0));
            rainbow.GradientStops.Add(new GradientStop(Colors.Lime, 2.0 / 6.0));
            rainbow.GradientStops.Add(new GradientStop(Colors.Cyan, 3.0 / 6.0));
            rainbow.GradientStops.Add(new GradientStop(Colors.Blue, 4.0 / 6.0));
            rainbow.GradientStops.Add(new GradientStop(Colors.Magenta, 5.0 / 6.0));
            rainbow.GradientStops.Add(new GradientStop(Colors.Red, 1.0));
            drawingContext.DrawRoundedRectangle(rainbow, null, bounds, bounds.Height / 2.0, bounds.Height / 2.0);
            drawingContext.DrawRoundedRectangle(
                null,
                new Pen(UiPalette.Brush(Color.FromArgb(115, 24, 72, 99)), 1.0),
                bounds,
                bounds.Height / 2.0,
                bounds.Height / 2.0);

            double x = hue / 360.0 * bounds.Width;
            Point center = new Point(x, bounds.Height / 2.0);
            drawingContext.DrawEllipse(
                UiPalette.Brush(ColorMath.FromHsv(hue, 1.0, 1.0)),
                new Pen(Brushes.White, 2.0),
                center,
                7.0,
                7.0);
            drawingContext.DrawEllipse(
                null,
                new Pen(UiPalette.Brush(Color.FromArgb(145, 24, 72, 99)), 1.0),
                center,
                8.0,
                8.0);
        }

        protected override void OnMouseLeftButtonDown(MouseButtonEventArgs args)
        {
            base.OnMouseLeftButtonDown(args);
            Focus();
            CaptureMouse();
            UpdateFromPoint(args.GetPosition(this));
            args.Handled = true;
        }

        protected override void OnMouseMove(MouseEventArgs args)
        {
            base.OnMouseMove(args);
            if (IsMouseCaptured && args.LeftButton == MouseButtonState.Pressed)
            {
                UpdateFromPoint(args.GetPosition(this));
                args.Handled = true;
            }
        }

        protected override void OnMouseLeftButtonUp(MouseButtonEventArgs args)
        {
            base.OnMouseLeftButtonUp(args);
            if (IsMouseCaptured)
            {
                UpdateFromPoint(args.GetPosition(this));
                ReleaseMouseCapture();
                args.Handled = true;
            }
        }

        protected override void OnKeyDown(KeyEventArgs args)
        {
            base.OnKeyDown(args);
            double step = Keyboard.Modifiers == ModifierKeys.Shift ? 10.0 : 1.0;
            if (args.Key == Key.Left || args.Key == Key.Down)
            {
                hue = ColorMath.NormalizeHue(hue - step);
            }
            else if (args.Key == Key.Right || args.Key == Key.Up)
            {
                hue = ColorMath.NormalizeHue(hue + step);
            }
            else
            {
                return;
            }
            InvalidateVisual();
            RaiseHueChanged();
            args.Handled = true;
        }

        private void UpdateFromPoint(Point point)
        {
            hue = ColorMath.NormalizeHue(
                Math.Max(0.0, Math.Min(1.0, point.X / Math.Max(1.0, ActualWidth))) * 359.999);
            InvalidateVisual();
            RaiseHueChanged();
        }

        private void RaiseHueChanged()
        {
            EventHandler handler = HueChanged;
            if (handler != null)
            {
                handler(this, EventArgs.Empty);
            }
        }
    }

    internal static class ColorMath
    {
        public static double NormalizeHue(double hue)
        {
            if (Double.IsNaN(hue) || Double.IsInfinity(hue))
            {
                return 0.0;
            }
            double normalized = hue % 360.0;
            return normalized < 0.0 ? normalized + 360.0 : normalized;
        }

        public static Color FromHsv(double hue, double saturation, double value)
        {
            double safeHue = NormalizeHue(hue);
            double safeSaturation = Math.Max(0.0, Math.Min(1.0, saturation));
            double safeValue = Math.Max(0.0, Math.Min(1.0, value));
            double chroma = safeValue * safeSaturation;
            double segment = safeHue / 60.0;
            double x = chroma * (1.0 - Math.Abs(segment % 2.0 - 1.0));
            double red = 0.0;
            double green = 0.0;
            double blue = 0.0;

            if (segment < 1.0)
            {
                red = chroma;
                green = x;
            }
            else if (segment < 2.0)
            {
                red = x;
                green = chroma;
            }
            else if (segment < 3.0)
            {
                green = chroma;
                blue = x;
            }
            else if (segment < 4.0)
            {
                green = x;
                blue = chroma;
            }
            else if (segment < 5.0)
            {
                red = x;
                blue = chroma;
            }
            else
            {
                red = chroma;
                blue = x;
            }

            double offset = safeValue - chroma;
            return Color.FromRgb(
                (byte)Math.Round((red + offset) * 255.0),
                (byte)Math.Round((green + offset) * 255.0),
                (byte)Math.Round((blue + offset) * 255.0));
        }

        public static void ToHsv(
            Color color,
            out double hue,
            out double saturation,
            out double value)
        {
            double red = color.R / 255.0;
            double green = color.G / 255.0;
            double blue = color.B / 255.0;
            double maximum = Math.Max(red, Math.Max(green, blue));
            double minimum = Math.Min(red, Math.Min(green, blue));
            double delta = maximum - minimum;

            if (delta <= 0.000001)
            {
                hue = 0.0;
            }
            else if (maximum == red)
            {
                hue = 60.0 * (((green - blue) / delta) % 6.0);
            }
            else if (maximum == green)
            {
                hue = 60.0 * ((blue - red) / delta + 2.0);
            }
            else
            {
                hue = 60.0 * ((red - green) / delta + 4.0);
            }
            hue = NormalizeHue(hue);
            saturation = maximum <= 0.000001 ? 0.0 : delta / maximum;
            value = maximum;
        }

        public static bool TryParseHex(string text, out Color color)
        {
            color = UiPalette.Blue;
            if (String.IsNullOrWhiteSpace(text))
            {
                return false;
            }
            string value = text.Trim().TrimStart('#');
            if (value.Length != 6)
            {
                return false;
            }
            byte red;
            byte green;
            byte blue;
            if (!Byte.TryParse(value.Substring(0, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out red)
                || !Byte.TryParse(value.Substring(2, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out green)
                || !Byte.TryParse(value.Substring(4, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out blue))
            {
                return false;
            }
            color = Color.FromRgb(red, green, blue);
            return true;
        }
    }

    internal static class AppearanceUi
    {
        public static Border CreateWindowShell()
        {
            return new Border
            {
                Background = UiPalette.Brush(Color.FromRgb(247, 252, 255)),
                BorderBrush = UiPalette.Brush(UiPalette.Border),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(21),
                Padding = new Thickness(22, 20, 22, 18),
                Margin = new Thickness(12),
                Effect = new DropShadowEffect
                {
                    Color = Color.FromRgb(64, 117, 148),
                    BlurRadius = 26,
                    ShadowDepth = 6,
                    Opacity = 0.24
                }
            };
        }

        public static Border CreateSectionCard(string title, UIElement body)
        {
            StackPanel content = new StackPanel();
            content.Children.Add(new TextBlock
            {
                Text = title,
                FontSize = 13,
                FontWeight = FontWeights.SemiBold,
                Foreground = UiPalette.Brush(UiPalette.Text),
                VerticalAlignment = VerticalAlignment.Center
            });
            content.Children.Add(body);

            return new Border
            {
                Background = UiPalette.Brush(Color.FromRgb(253, 255, 255)),
                BorderBrush = UiPalette.Brush(Color.FromArgb(150, UiPalette.Border.R, UiPalette.Border.G, UiPalette.Border.B)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(15),
                Padding = new Thickness(15, 13, 15, 13),
                Margin = new Thickness(0, 0, 0, 12),
                Child = content
            };
        }

        public static Border CreateFieldShell(UIElement child)
        {
            return new Border
            {
                Height = 32,
                Background = UiPalette.Brush(Colors.White),
                BorderBrush = UiPalette.Brush(Color.FromArgb(185, UiPalette.Border.R, UiPalette.Border.G, UiPalette.Border.B)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(7, 1, 7, 1),
                Child = child
            };
        }

        public static Button CreateCloseButton()
        {
            Button button = new Button
            {
                Width = 30,
                Height = 30,
                Content = "×",
                FontSize = 17,
                FontWeight = FontWeights.Normal,
                Foreground = UiPalette.Brush(UiPalette.Muted),
                Background = UiPalette.Brush(Color.FromRgb(229, 245, 253)),
                BorderBrush = Brushes.Transparent,
                BorderThickness = new Thickness(0),
                Cursor = Cursors.Hand,
                Template = CreateRoundedButtonTemplate(15),
                VerticalContentAlignment = VerticalAlignment.Center,
                HorizontalContentAlignment = HorizontalAlignment.Center
            };
            AutomationProperties.SetName(button, "关闭");
            return button;
        }

        public static Button CreateActionButton(string text, bool primary, double width)
        {
            Button button = new Button
            {
                Content = text,
                Width = width,
                Height = 40,
                Padding = new Thickness(14, 5, 14, 5),
                Cursor = Cursors.Hand,
                FontSize = 11.5,
                FontWeight = primary ? FontWeights.SemiBold : FontWeights.Normal,
                Foreground = primary ? Brushes.White : UiPalette.Brush(UiPalette.Text),
                Background = primary
                    ? UiPalette.Brush(UiPalette.Blue)
                    : UiPalette.Brush(Color.FromRgb(235, 248, 255)),
                BorderBrush = UiPalette.Brush(primary ? UiPalette.Blue : UiPalette.Border),
                BorderThickness = new Thickness(1),
                Template = CreateRoundedButtonTemplate(9)
            };
            AutomationProperties.SetName(button, text);
            return button;
        }

        public static ControlTemplate CreateRoundedButtonTemplate(double radius)
        {
            ControlTemplate template = new ControlTemplate(typeof(Button));
            FrameworkElementFactory border = new FrameworkElementFactory(typeof(Border));
            border.SetValue(Border.CornerRadiusProperty, new CornerRadius(radius));
            border.SetValue(Border.BackgroundProperty, new TemplateBindingExtension(Control.BackgroundProperty));
            border.SetValue(Border.BorderBrushProperty, new TemplateBindingExtension(Control.BorderBrushProperty));
            border.SetValue(Border.BorderThicknessProperty, new TemplateBindingExtension(Control.BorderThicknessProperty));
            border.SetValue(Border.PaddingProperty, new TemplateBindingExtension(Control.PaddingProperty));

            FrameworkElementFactory presenter = new FrameworkElementFactory(typeof(ContentPresenter));
            presenter.SetValue(ContentPresenter.ContentProperty, new TemplateBindingExtension(ContentControl.ContentProperty));
            presenter.SetValue(ContentPresenter.ContentTemplateProperty, new TemplateBindingExtension(ContentControl.ContentTemplateProperty));
            presenter.SetValue(ContentPresenter.HorizontalAlignmentProperty, HorizontalAlignment.Center);
            presenter.SetValue(ContentPresenter.VerticalAlignmentProperty, VerticalAlignment.Center);
            border.AppendChild(presenter);
            template.VisualTree = border;
            return template;
        }

        public static string FormatColor(Color color)
        {
            return "#"
                + color.R.ToString("X2", CultureInfo.InvariantCulture)
                + color.G.ToString("X2", CultureInfo.InvariantCulture)
                + color.B.ToString("X2", CultureInfo.InvariantCulture);
        }
    }
}
