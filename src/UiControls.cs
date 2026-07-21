using System;
using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Effects;

namespace CodexQuotaBall
{
    public static class UiPalette
    {
        public static Color Background = Color.FromRgb(235, 248, 255);
        public static Color Panel = Color.FromRgb(248, 253, 255);
        public static Color PanelAlt = Color.FromRgb(232, 247, 255);
        public static Color Border = Color.FromRgb(164, 213, 240);
        public static Color Text = Color.FromRgb(24, 72, 99);
        public static Color Muted = Color.FromRgb(91, 130, 153);
        public static Color Green = Color.FromRgb(45, 194, 145);
        public static Color Amber = Color.FromRgb(239, 169, 66);
        public static Color Red = Color.FromRgb(232, 100, 119);
        public static Color Blue = Color.FromRgb(47, 164, 235);

        public static SolidColorBrush Brush(Color color)
        {
            SolidColorBrush brush = new SolidColorBrush(color);
            if (brush.CanFreeze)
            {
                brush.Freeze();
            }
            return brush;
        }

        public static Color QuotaColor(double remaining)
        {
            if (remaining >= 20.0)
            {
                return Blue;
            }
            if (remaining >= 10.0)
            {
                return Amber;
            }
            return Red;
        }
    }

    public sealed class QuotaBar : FrameworkElement
    {
        private double remainingPercent;
        private Color accentColor = UiPalette.Green;

        public QuotaBar()
        {
            Height = 7;
            MinWidth = 80;
            SnapsToDevicePixels = true;
        }

        public double RemainingPercent
        {
            get { return remainingPercent; }
            set
            {
                remainingPercent = Math.Max(0.0, Math.Min(100.0, value));
                InvalidateVisual();
            }
        }

        public Color AccentColor
        {
            get { return accentColor; }
            set
            {
                accentColor = value;
                InvalidateVisual();
            }
        }

        protected override void OnRender(DrawingContext drawingContext)
        {
            base.OnRender(drawingContext);
            double width = Math.Max(0.0, ActualWidth);
            double height = Math.Max(0.0, ActualHeight);
            if (width <= 0.0 || height <= 0.0)
            {
                return;
            }

            Rect trackRect = new Rect(0, 0, width, height);
            drawingContext.DrawRoundedRectangle(
                UiPalette.Brush(Color.FromRgb(205, 233, 247)),
                null,
                trackRect,
                height / 2.0,
                height / 2.0);

            double fillWidth = width * remainingPercent / 100.0;
            if (fillWidth > 0.5)
            {
                Rect fillRect = new Rect(0, 0, Math.Max(height, fillWidth), height);
                drawingContext.PushClip(new RectangleGeometry(trackRect, height / 2.0, height / 2.0));
                drawingContext.DrawRoundedRectangle(
                    UiPalette.Brush(accentColor),
                    null,
                    fillRect,
                    height / 2.0,
                    height / 2.0);
                drawingContext.Pop();
            }
        }
    }

    public sealed class QuotaBallVisual : FrameworkElement
    {
        public const double DefaultDiameter = 38.0;
        public const double MinimumDiameter = 24.0;
        public const double MaximumDiameter = 160.0;
        private QuotaSnapshot snapshot;
        private bool connected;
        private string statusText = "正在连接";
        private Color accentColor = UiPalette.Blue;

        public QuotaBallVisual()
        {
            Width = DefaultDiameter;
            Height = DefaultDiameter;
            Cursor = System.Windows.Input.Cursors.Hand;
            UpdateShadow(DefaultDiameter);
            TextOptions.SetTextFormattingMode(this, TextFormattingMode.Display);
            TextOptions.SetTextRenderingMode(this, TextRenderingMode.ClearType);
        }

        public void SetAppearance(double diameter, Color color)
        {
            double safeDiameter = Math.Max(MinimumDiameter, Math.Min(diameter, MaximumDiameter));
            Width = safeDiameter;
            Height = safeDiameter;
            accentColor = color;
            UpdateShadow(safeDiameter);
            InvalidateMeasure();
            InvalidateVisual();
        }

        private void UpdateShadow(double diameter)
        {
            Effect = new DropShadowEffect
            {
                Color = Mix(accentColor, Colors.Black, 0.20),
                BlurRadius = Math.Max(5.0, diameter * 0.18),
                ShadowDepth = Math.Max(0.8, diameter * 0.032),
                Opacity = 0.30
            };
        }

        public void SetState(QuotaSnapshot value, bool isConnected, string status)
        {
            snapshot = value;
            connected = isConnected;
            if (!String.IsNullOrWhiteSpace(status))
            {
                statusText = status;
            }
            InvalidateVisual();
        }

        protected override void OnRender(DrawingContext drawingContext)
        {
            base.OnRender(drawingContext);

            double size = Math.Min(ActualWidth, ActualHeight);
            if (size <= 0.0)
            {
                return;
            }

            Point center = new Point(ActualWidth / 2.0, ActualHeight / 2.0);
            double outerRadius = Math.Max(6.0, size / 2.0 - Math.Max(2.2, size * 0.092));
            RadialGradientBrush background = new RadialGradientBrush();
            background.Center = new Point(0.38, 0.32);
            background.GradientOrigin = new Point(0.30, 0.24);
            background.RadiusX = 0.80;
            background.RadiusY = 0.80;
            background.GradientStops.Add(new GradientStop(Mix(accentColor, Colors.White, 0.97), 0.0));
            background.GradientStops.Add(new GradientStop(Mix(accentColor, Colors.White, 0.78), 0.58));
            background.GradientStops.Add(new GradientStop(Mix(accentColor, Colors.White, 0.45), 1.0));

            drawingContext.DrawEllipse(
                background,
                new Pen(UiPalette.Brush(Mix(accentColor, Colors.Black, 0.08)), Math.Max(0.7, size * 0.021)),
                center,
                outerRadius,
                outerRadius);

            QuotaWindowInfo limitingWindow = snapshot == null ? null : snapshot.MostRestrictiveWindow;
            double remaining = limitingWindow == null ? 0.0 : limitingWindow.RemainingPercent;
            Color accent = limitingWindow == null ? UiPalette.Blue : UiPalette.QuotaColor(remaining);

            double ringWidth = Math.Max(1.8, Math.Min(8.0, size * 0.066));
            double ringRadius = Math.Max(4.0, outerRadius - ringWidth * 1.04);
            Pen trackPen = new Pen(UiPalette.Brush(Color.FromArgb(190, 255, 255, 255)), ringWidth);
            trackPen.StartLineCap = PenLineCap.Round;
            trackPen.EndLineCap = PenLineCap.Round;
            drawingContext.DrawEllipse(null, trackPen, center, ringRadius, ringRadius);

            if (limitingWindow != null && remaining > 0.0)
            {
                Pen accentPen = new Pen(UiPalette.Brush(accent), ringWidth);
                accentPen.StartLineCap = PenLineCap.Round;
                accentPen.EndLineCap = PenLineCap.Round;
                if (remaining >= 99.8)
                {
                    drawingContext.DrawEllipse(null, accentPen, center, ringRadius, ringRadius);
                }
                else
                {
                    Geometry arc = CreateArc(center, ringRadius, remaining * 3.6);
                    drawingContext.DrawGeometry(null, accentPen, arc);
                }
            }

            string numberText = limitingWindow == null
                ? "--"
                : Math.Round(remaining).ToString("0", CultureInfo.InvariantCulture) + "%";
            double pixelsPerDip = VisualTreeHelper.GetDpi(this).PixelsPerDip;
            double fontSize = numberText.Length >= 4 ? size * 0.242 : size * 0.274;
            fontSize = Math.Max(6.8, Math.Min(37.0, fontSize));

            DrawCenteredText(
                drawingContext,
                numberText,
                fontSize,
                FontWeights.Bold,
                UiPalette.Brush(Mix(accentColor, Colors.Black, 0.58)),
                center,
                pixelsPerDip);

            Color statusColor = connected ? UiPalette.Green : UiPalette.Amber;
            Point statusCenter = new Point(center.X + outerRadius * 0.70, center.Y - outerRadius * 0.70);
            double statusOuter = Math.Max(2.0, size * 0.071);
            double statusInner = Math.Max(1.2, size * 0.043);
            drawingContext.DrawEllipse(
                UiPalette.Brush(Mix(accentColor, Colors.White, 0.94)),
                null,
                statusCenter,
                statusOuter,
                statusOuter);
            drawingContext.DrawEllipse(
                UiPalette.Brush(statusColor),
                null,
                statusCenter,
                statusInner,
                statusInner);
        }

        private static Color Mix(Color source, Color target, double amount)
        {
            double safe = Math.Max(0.0, Math.Min(1.0, amount));
            return Color.FromRgb(
                (byte)Math.Round(source.R + (target.R - source.R) * safe),
                (byte)Math.Round(source.G + (target.G - source.G) * safe),
                (byte)Math.Round(source.B + (target.B - source.B) * safe));
        }

        private static Geometry CreateArc(Point center, double radius, double sweepDegrees)
        {
            double startDegrees = -90.0;
            double endDegrees = startDegrees + sweepDegrees;
            Point start = PointOnCircle(center, radius, startDegrees);
            Point end = PointOnCircle(center, radius, endDegrees);

            StreamGeometry geometry = new StreamGeometry();
            using (StreamGeometryContext context = geometry.Open())
            {
                context.BeginFigure(start, false, false);
                context.ArcTo(
                    end,
                    new Size(radius, radius),
                    0.0,
                    sweepDegrees > 180.0,
                    SweepDirection.Clockwise,
                    true,
                    false);
            }
            if (geometry.CanFreeze)
            {
                geometry.Freeze();
            }
            return geometry;
        }

        private static Point PointOnCircle(Point center, double radius, double degrees)
        {
            double radians = degrees * Math.PI / 180.0;
            return new Point(
                center.X + radius * Math.Cos(radians),
                center.Y + radius * Math.Sin(radians));
        }

        private static void DrawCenteredText(
            DrawingContext drawingContext,
            string text,
            double fontSize,
            FontWeight weight,
            Brush brush,
            Point center,
            double pixelsPerDip)
        {
            FormattedText formatted = new FormattedText(
                text,
                CultureInfo.GetCultureInfo("zh-CN"),
                FlowDirection.LeftToRight,
                new Typeface(new FontFamily("Microsoft YaHei UI"), FontStyles.Normal, weight, FontStretches.Normal),
                fontSize,
                brush,
                pixelsPerDip);
            drawingContext.DrawText(
                formatted,
                new Point(center.X - formatted.Width / 2.0, center.Y - formatted.Height / 2.0 - 0.3));
        }
    }
}
