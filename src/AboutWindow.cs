using System;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace CodexQuotaBall
{
    public sealed class AboutWindow : Window
    {
        public AboutWindow()
        {
            Title = "关于 " + AppIdentity.ProductName;
            Width = 480;
            Height = 452;
            WindowStyle = WindowStyle.SingleBorderWindow;
            ResizeMode = ResizeMode.NoResize;
            Background = Brushes.White;
            ShowInTaskbar = false;
            Topmost = true;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            FontFamily = new FontFamily("Microsoft YaHei UI");
            Icon = TokenOrbLogoVisual.CreateIcon();
            AutomationProperties.SetName(this, "关于 " + AppIdentity.ProductName);

            Grid layout = new Grid();
            layout.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            layout.RowDefinitions.Add(new RowDefinition { Height = new GridLength(73) });

            StackPanel identity = new StackPanel
            {
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            };

            TokenOrbLogoVisual logo = new TokenOrbLogoVisual
            {
                Width = 84,
                Height = 84,
                HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(0, 0, 0, 22)
            };
            AutomationProperties.SetName(logo, "Token Orb 图标");
            identity.Children.Add(logo);

            identity.Children.Add(CreateCenteredText(
                AppIdentity.ProductName,
                22,
                FontWeights.SemiBold,
                Color.FromRgb(28, 28, 28),
                new Thickness(0)));
            identity.Children.Add(CreateCenteredText(
                "Powered by Codex",
                14,
                FontWeights.Normal,
                Color.FromRgb(92, 92, 92),
                new Thickness(0, 22, 0, 0)));
            identity.Children.Add(CreateCenteredText(
                "版本 " + AppIdentity.DisplayVersion,
                14,
                FontWeights.Normal,
                Color.FromRgb(92, 92, 92),
                new Thickness(0, 1, 0, 0)));
            identity.Children.Add(CreateCenteredText(
                AppIdentity.ReleaseDateText,
                14,
                FontWeights.Normal,
                Color.FromRgb(92, 92, 92),
                new Thickness(0, 22, 0, 0)));
            identity.Children.Add(CreateCenteredText(
                "© " + AppIdentity.Publisher,
                14,
                FontWeights.Normal,
                Color.FromRgb(92, 92, 92),
                new Thickness(0, 17, 0, 0)));

            Grid.SetRow(identity, 0);
            layout.Children.Add(identity);

            Border footer = new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(248, 248, 248)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(218, 218, 218)),
                BorderThickness = new Thickness(0, 1, 0, 0)
            };
            Grid footerLayout = new Grid();
            Button confirm = new Button
            {
                Content = "确定",
                Width = 100,
                Height = 40,
                Margin = new Thickness(0, 0, 14, 0),
                HorizontalAlignment = HorizontalAlignment.Right,
                VerticalAlignment = VerticalAlignment.Center,
                FontFamily = new FontFamily("Microsoft YaHei UI"),
                FontSize = 12,
                Foreground = new SolidColorBrush(Color.FromRgb(25, 25, 25)),
                Background = new SolidColorBrush(Color.FromRgb(250, 250, 250)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(0, 103, 192)),
                BorderThickness = new Thickness(2),
                IsDefault = true,
                Cursor = Cursors.Hand
            };
            AutomationProperties.SetName(confirm, "确定");
            confirm.Click += delegate
            {
                DialogResult = true;
            };
            footerLayout.Children.Add(confirm);
            footer.Child = footerLayout;
            Grid.SetRow(footer, 1);
            layout.Children.Add(footer);

            Content = layout;
            KeyDown += delegate(object sender, KeyEventArgs args)
            {
                if (args.Key == Key.Escape)
                {
                    DialogResult = false;
                    args.Handled = true;
                }
            };
        }

        private static TextBlock CreateCenteredText(
            string text,
            double size,
            FontWeight weight,
            Color color,
            Thickness margin)
        {
            return new TextBlock
            {
                Text = text,
                FontSize = size,
                FontWeight = weight,
                Foreground = new SolidColorBrush(color),
                TextAlignment = TextAlignment.Center,
                HorizontalAlignment = HorizontalAlignment.Center,
                Margin = margin
            };
        }
    }

    public sealed class TokenOrbLogoVisual : FrameworkElement
    {
        protected override void OnRender(DrawingContext drawingContext)
        {
            base.OnRender(drawingContext);
            double width = Math.Max(1.0, ActualWidth);
            double height = Math.Max(1.0, ActualHeight);
            double size = Math.Min(width, height);
            Point center = new Point(width / 2.0, height / 2.0);
            double scale = size / 84.0;

            drawingContext.DrawEllipse(
                new SolidColorBrush(Color.FromRgb(239, 248, 255)),
                null,
                center,
                38.0 * scale,
                38.0 * scale);

            Pen softRing = new Pen(
                new SolidColorBrush(Color.FromRgb(87, 135, 165)),
                Math.Max(1.6, 2.7 * scale));
            softRing.StartLineCap = PenLineCap.Round;
            softRing.EndLineCap = PenLineCap.Round;

            DrawOrbit(drawingContext, center, scale, 0.0, softRing);
            DrawOrbit(drawingContext, center, scale, 60.0, softRing);
            DrawOrbit(drawingContext, center, scale, 120.0, softRing);

            RadialGradientBrush core = new RadialGradientBrush
            {
                GradientOrigin = new Point(0.34, 0.30),
                Center = new Point(0.5, 0.5),
                RadiusX = 0.7,
                RadiusY = 0.7
            };
            core.GradientStops.Add(new GradientStop(Colors.White, 0.0));
            core.GradientStops.Add(new GradientStop(Color.FromRgb(116, 203, 247), 0.50));
            core.GradientStops.Add(new GradientStop(Color.FromRgb(41, 145, 218), 1.0));
            drawingContext.DrawEllipse(
                core,
                new Pen(new SolidColorBrush(Color.FromRgb(53, 128, 174)), Math.Max(1.2, 1.8 * scale)),
                center,
                12.0 * scale,
                12.0 * scale);

            drawingContext.DrawEllipse(
                new SolidColorBrush(Color.FromRgb(68, 177, 235)),
                new Pen(Brushes.White, Math.Max(1.0, 1.5 * scale)),
                new Point(center.X + 28.0 * scale, center.Y - 7.0 * scale),
                4.2 * scale,
                4.2 * scale);
            drawingContext.DrawEllipse(
                new SolidColorBrush(Color.FromRgb(119, 213, 244)),
                new Pen(Brushes.White, Math.Max(1.0, 1.5 * scale)),
                new Point(center.X - 24.0 * scale, center.Y + 18.0 * scale),
                3.6 * scale,
                3.6 * scale);
        }

        private static void DrawOrbit(
            DrawingContext drawingContext,
            Point center,
            double scale,
            double angle,
            Pen pen)
        {
            drawingContext.PushTransform(new RotateTransform(angle, center.X, center.Y));
            drawingContext.DrawEllipse(
                null,
                pen,
                center,
                31.0 * scale,
                13.0 * scale);
            drawingContext.Pop();
        }

        public static ImageSource CreateIcon()
        {
            DrawingGroup drawing = new DrawingGroup();
            drawing.Children.Add(new GeometryDrawing(
                new SolidColorBrush(Color.FromRgb(232, 247, 255)),
                null,
                new EllipseGeometry(new Point(16, 16), 15, 15)));

            Pen ring = new Pen(new SolidColorBrush(Color.FromRgb(76, 128, 161)), 1.7);
            double[] angles = new double[] { 0.0, 60.0, 120.0 };
            foreach (double angle in angles)
            {
                EllipseGeometry geometry = new EllipseGeometry(new Point(16, 16), 12, 5.2);
                geometry.Transform = new RotateTransform(angle, 16, 16);
                drawing.Children.Add(new GeometryDrawing(null, ring, geometry));
            }
            drawing.Children.Add(new GeometryDrawing(
                new SolidColorBrush(Color.FromRgb(55, 164, 228)),
                new Pen(new SolidColorBrush(Color.FromRgb(55, 118, 158)), 1.2),
                new EllipseGeometry(new Point(16, 16), 4.5, 4.5)));
            if (drawing.CanFreeze)
            {
                drawing.Freeze();
            }
            return new DrawingImage(drawing);
        }
    }
}
