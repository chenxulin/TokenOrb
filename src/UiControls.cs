using System;
using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Threading;

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
        public static Color OuterRingBlue = Color.FromRgb(125, 211, 252);

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
            return WaveColor(remaining);
        }

        public static Color WaveColor(double remaining)
        {
            if (remaining > 20.0)
            {
                return Green;
            }
            if (remaining > 10.0)
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
        public const double DefaultDiameter = 60.0;
        public const double MinimumDiameter = 24.0;
        public const double MaximumDiameter = 160.0;
        internal const double OuterRingBreathingCycleSeconds = 3.0;
        internal const double BodyLightCycleSeconds = 5.6;
        private QuotaSnapshot snapshot;
        private bool connected;
        private string statusText = "正在连接";
        private Color accentColor = UiPalette.Blue;
        private readonly DispatcherTimer waveTimer;
        private double wavePhase;
        private double breathPhase;
        private double bodyLightPhase;

        public QuotaBallVisual()
        {
            Width = DefaultDiameter;
            Height = DefaultDiameter;
            Cursor = System.Windows.Input.Cursors.Hand;
            UpdateShadow(DefaultDiameter);
            TextOptions.SetTextFormattingMode(this, TextFormattingMode.Display);
            TextOptions.SetTextRenderingMode(this, TextRenderingMode.ClearType);

            waveTimer = new DispatcherTimer(DispatcherPriority.Render, Dispatcher);
            waveTimer.Interval = TimeSpan.FromMilliseconds(40.0);
            waveTimer.Tick += OnWaveTimerTick;
            Loaded += OnLoaded;
            Unloaded += OnUnloaded;
            IsVisibleChanged += OnIsVisibleChanged;
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
            double diameter = Double.IsNaN(Width) || Width <= 0.0 ? DefaultDiameter : Width;
            UpdateShadow(diameter);
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
            QuotaWindowInfo limitingWindow = snapshot == null ? null : snapshot.MostRestrictiveWindow;
            double remaining = limitingWindow == null ? 0.0 : limitingWindow.RemainingPercent;
            bool depleted = limitingWindow != null && remaining <= 0.0;
            Point bodyLightOffset = CalculateBodyLightOffset(bodyLightPhase);
            double bodyLightStrength = CalculateBodyLightStrength(bodyLightPhase);
            double bodyPulseScale = CalculateBodyPulseScale(bodyLightPhase);
            drawingContext.PushTransform(new ScaleTransform(
                bodyPulseScale,
                bodyPulseScale,
                center.X,
                center.Y));
            RadialGradientBrush background = new RadialGradientBrush();
            background.Center = new Point(
                0.38 + bodyLightOffset.X,
                0.32 + bodyLightOffset.Y);
            background.GradientOrigin = new Point(
                0.30 + bodyLightOffset.X * 1.15,
                0.24 + bodyLightOffset.Y * 1.15);
            background.RadiusX = 0.77 + 0.055 * bodyLightStrength;
            background.RadiusY = 0.78 + 0.045 * bodyLightStrength;
            background.GradientStops.Add(new GradientStop(Mix(accentColor, Colors.White, 0.97), 0.0));
            background.GradientStops.Add(new GradientStop(
                Mix(accentColor, Colors.White, 0.650 + 0.150 * bodyLightStrength),
                0.58));
            background.GradientStops.Add(new GradientStop(
                Mix(accentColor, Colors.White, 0.320 + 0.160 * bodyLightStrength),
                1.0));

            Color outerBorderColor = ResolveOuterBorderColor(
                accentColor,
                limitingWindow == null ? (double?)null : remaining);
            double outerBorderWidth = CalculateOuterBorderWidth(size, depleted);

            double breathStrength = CalculateBreathStrength(breathPhase);
            byte outerBorderAlpha = CalculateOuterRingAlpha(breathStrength, depleted);
            byte outerGlowAlpha = (byte)Math.Round(
                (depleted ? 14.0 : 18.0) + (depleted ? 30.0 : 36.0) * breathStrength);
            double outerGlowWidth = outerBorderWidth + Math.Max(
                1.6,
                Math.Min(6.0, size * (0.034 + 0.018 * breathStrength)));
            Color renderedOuterBorderColor = Color.FromArgb(
                outerBorderAlpha,
                outerBorderColor.R,
                outerBorderColor.G,
                outerBorderColor.B);
            Color outerGlowColor = Color.FromArgb(
                outerGlowAlpha,
                outerBorderColor.R,
                outerBorderColor.G,
                outerBorderColor.B);

            drawingContext.DrawEllipse(
                null,
                new Pen(UiPalette.Brush(outerGlowColor), outerGlowWidth),
                center,
                outerRadius,
                outerRadius);

            drawingContext.DrawEllipse(
                background,
                new Pen(UiPalette.Brush(renderedOuterBorderColor), outerBorderWidth),
                center,
                outerRadius,
                outerRadius);

            RadialGradientBrush bodyHighlight = new RadialGradientBrush();
            Point highlightCenter = new Point(
                0.30 + bodyLightOffset.X * 1.40,
                0.26 + bodyLightOffset.Y * 1.30);
            bodyHighlight.Center = highlightCenter;
            bodyHighlight.GradientOrigin = highlightCenter;
            bodyHighlight.RadiusX = 0.42;
            bodyHighlight.RadiusY = 0.36;
            byte highlightAlpha = CalculateBodyHighlightAlpha(bodyLightStrength);
            bodyHighlight.GradientStops.Add(new GradientStop(
                Color.FromArgb(highlightAlpha, 255, 255, 255),
                0.0));
            bodyHighlight.GradientStops.Add(new GradientStop(
                Color.FromArgb(0, 255, 255, 255),
                0.84));
            double bodyHighlightRadius = Math.Max(
                2.0,
                outerRadius - outerBorderWidth * 0.56);
            drawingContext.DrawEllipse(
                bodyHighlight,
                null,
                center,
                bodyHighlightRadius,
                bodyHighlightRadius);

            Point sheenOffset = CalculateBodySheenOffset(bodyLightPhase);
            Point sheenCenter = new Point(
                center.X + outerRadius * sheenOffset.X,
                center.Y + outerRadius * sheenOffset.Y);
            byte sheenAlpha = CalculateBodySheenAlpha(bodyLightStrength);
            Color sheenTint = Mix(accentColor, Colors.White, 0.35);
            RadialGradientBrush bodySheen = new RadialGradientBrush();
            bodySheen.Center = new Point(0.42, 0.40);
            bodySheen.GradientOrigin = bodySheen.Center;
            bodySheen.RadiusX = 0.58;
            bodySheen.RadiusY = 0.58;
            bodySheen.GradientStops.Add(new GradientStop(
                Color.FromArgb(sheenAlpha, sheenTint.R, sheenTint.G, sheenTint.B),
                0.0));
            bodySheen.GradientStops.Add(new GradientStop(
                Color.FromArgb(
                    (byte)(sheenAlpha / 3),
                    sheenTint.R,
                    sheenTint.G,
                    sheenTint.B),
                0.48));
            bodySheen.GradientStops.Add(new GradientStop(
                Color.FromArgb(0, sheenTint.R, sheenTint.G, sheenTint.B),
                1.0));
            drawingContext.PushClip(new EllipseGeometry(
                center,
                bodyHighlightRadius,
                bodyHighlightRadius));
            drawingContext.DrawEllipse(
                bodySheen,
                null,
                sheenCenter,
                Math.Max(2.2, outerRadius * 0.30),
                Math.Max(1.3, outerRadius * 0.13));

            byte sheenCoreAlpha = CalculateBodySheenCoreAlpha(bodyLightStrength);
            RadialGradientBrush sheenCore = new RadialGradientBrush();
            sheenCore.Center = new Point(0.42, 0.38);
            sheenCore.GradientOrigin = sheenCore.Center;
            sheenCore.RadiusX = 0.62;
            sheenCore.RadiusY = 0.62;
            sheenCore.GradientStops.Add(new GradientStop(
                Color.FromArgb(sheenCoreAlpha, 255, 255, 255),
                0.0));
            sheenCore.GradientStops.Add(new GradientStop(
                Color.FromArgb(0, 255, 255, 255),
                1.0));
            drawingContext.DrawEllipse(
                sheenCore,
                null,
                new Point(
                    sheenCenter.X - outerRadius * 0.04,
                    sheenCenter.Y - outerRadius * 0.035),
                Math.Max(1.3, outerRadius * 0.115),
                Math.Max(0.8, outerRadius * 0.050));

            drawingContext.Pop();

            Color accent = limitingWindow == null ? UiPalette.Blue : UiPalette.QuotaColor(remaining);
            double ringWidth = Math.Max(1.8, Math.Min(8.0, size * 0.066));
            double ringRadius = Math.Max(4.0, outerRadius - ringWidth * 1.04);

            if (limitingWindow != null && remaining > 0.0)
            {
                double waveInset = Math.Max(0.65, size * 0.012);
                double waveRadius = Math.Max(2.2, ringRadius - ringWidth / 2.0 - waveInset);
                DrawWaterWave(
                    drawingContext,
                    center,
                    waveRadius,
                    remaining,
                    UiPalette.WaveColor(remaining),
                    size);
            }

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

            drawingContext.Pop();

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
                UiPalette.Brush(ResolveQuotaTextColor(
                    accentColor,
                    limitingWindow == null ? (double?)null : remaining)),
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

        internal static Color ResolveOuterBorderColor(Color appearanceAccent, double? remaining)
        {
            if (remaining.HasValue && remaining.Value <= 0.0)
            {
                return UiPalette.Red;
            }
            return UiPalette.OuterRingBlue;
        }

        internal static double CalculateBreathStrength(double phase)
        {
            if (Double.IsNaN(phase) || Double.IsInfinity(phase))
            {
                return 0.5;
            }
            return 0.5 + 0.5 * Math.Sin(phase);
        }

        internal static Point CalculateBodyLightOffset(double phase)
        {
            if (Double.IsNaN(phase) || Double.IsInfinity(phase))
            {
                return new Point(0.0, 0.0);
            }
            return new Point(
                Math.Sin(phase) * 0.075,
                Math.Cos(phase) * 0.040);
        }

        internal static double CalculateBodyLightStrength(double phase)
        {
            if (Double.IsNaN(phase) || Double.IsInfinity(phase))
            {
                return 0.5;
            }
            return 0.5 + 0.5 * Math.Sin(phase);
        }

        internal static double CalculateBodyPulseScale(double phase)
        {
            if (Double.IsNaN(phase) || Double.IsInfinity(phase))
            {
                return 1.0;
            }
            return 1.0 + Math.Sin(phase) * 0.040;
        }

        internal static Point CalculateBodySheenOffset(double phase)
        {
            if (Double.IsNaN(phase) || Double.IsInfinity(phase))
            {
                return new Point(0.0, -0.26);
            }
            return new Point(
                Math.Sin(phase) * 0.36,
                -0.34 + Math.Cos(phase) * 0.040);
        }

        internal static byte CalculateBodyHighlightAlpha(double bodyLightStrength)
        {
            double safeStrength = Math.Max(0.0, Math.Min(1.0, bodyLightStrength));
            return (byte)Math.Round(28.0 + 44.0 * safeStrength);
        }

        internal static byte CalculateBodySheenAlpha(double bodyLightStrength)
        {
            double safeStrength = Math.Max(0.0, Math.Min(1.0, bodyLightStrength));
            return (byte)Math.Round(125.0 + 70.0 * safeStrength);
        }

        internal static byte CalculateBodySheenCoreAlpha(double bodyLightStrength)
        {
            double safeStrength = Math.Max(0.0, Math.Min(1.0, bodyLightStrength));
            return (byte)Math.Round(180.0 + 55.0 * safeStrength);
        }

        internal static double CalculateOuterBorderWidth(double size, bool depleted)
        {
            double safeSize = Math.Max(0.0, size);
            return depleted
                ? Math.Max(2.0, Math.Min(6.0, safeSize * 0.040))
                : Math.Max(1.1, Math.Min(4.5, safeSize * 0.030));
        }

        internal static byte CalculateOuterRingAlpha(double breathStrength, bool depleted)
        {
            double safeStrength = Math.Max(0.0, Math.Min(1.0, breathStrength));
            double minimumAlpha = depleted ? 210.0 : 170.0;
            return (byte)Math.Round(minimumAlpha + (255.0 - minimumAlpha) * safeStrength);
        }

        internal static Color ResolveQuotaTextColor(Color appearanceAccent, double? remaining)
        {
            if (remaining.HasValue && remaining.Value <= 0.0)
            {
                return UiPalette.Red;
            }
            return Mix(appearanceAccent, Colors.Black, 0.58);
        }

        private void OnWaveTimerTick(object sender, EventArgs e)
        {
            wavePhase += 0.15;
            if (wavePhase >= Math.PI * 2.0)
            {
                wavePhase -= Math.PI * 2.0;
            }
            breathPhase += Math.PI * 2.0 * waveTimer.Interval.TotalSeconds
                / OuterRingBreathingCycleSeconds;
            if (breathPhase >= Math.PI * 2.0)
            {
                breathPhase -= Math.PI * 2.0;
            }
            bodyLightPhase += Math.PI * 2.0 * waveTimer.Interval.TotalSeconds
                / BodyLightCycleSeconds;
            if (bodyLightPhase >= Math.PI * 2.0)
            {
                bodyLightPhase -= Math.PI * 2.0;
            }
            InvalidateVisual();
        }

        private void OnLoaded(object sender, RoutedEventArgs e)
        {
            UpdateWaveTimer();
        }

        private void OnUnloaded(object sender, RoutedEventArgs e)
        {
            waveTimer.Stop();
        }

        private void OnIsVisibleChanged(object sender, DependencyPropertyChangedEventArgs e)
        {
            UpdateWaveTimer();
        }

        private void UpdateWaveTimer()
        {
            if (IsLoaded && IsVisible)
            {
                waveTimer.Start();
            }
            else
            {
                waveTimer.Stop();
            }
        }

        private void DrawWaterWave(
            DrawingContext drawingContext,
            Point center,
            double radius,
            double remaining,
            Color waveColor,
            double size)
        {
            double visibleHeight = CalculateVisibleWaveHeight(size, radius, remaining);
            double ratio = visibleHeight / Math.Max(1.0, radius * 2.0);
            double waterLine = center.Y + radius - radius * 2.0 * ratio;
            double edgeDamping = Math.Max(0.38, Math.Min(1.0, Math.Min(ratio, 1.0 - ratio) * 4.2));
            double amplitude = Math.Max(0.75, Math.Min(5.5, size * 0.052)) * edgeDamping;

            drawingContext.PushClip(new EllipseGeometry(center, radius, radius));

            Geometry backWave = CreateWaveFill(
                center,
                radius,
                waterLine + amplitude * 0.42,
                amplitude * 0.72,
                -wavePhase * 0.74 + 1.35,
                1.20);
            drawingContext.DrawGeometry(
                UiPalette.Brush(Color.FromArgb(72, waveColor.R, waveColor.G, waveColor.B)),
                null,
                backWave);

            Geometry frontWave = CreateWaveFill(
                center,
                radius,
                waterLine,
                amplitude,
                wavePhase,
                1.42);
            drawingContext.DrawGeometry(
                UiPalette.Brush(Color.FromArgb(132, waveColor.R, waveColor.G, waveColor.B)),
                null,
                frontWave);

            drawingContext.Pop();
        }

        internal static double CalculateVisibleWaveHeight(
            double size,
            double radius,
            double remaining)
        {
            double safeRemaining = Math.Max(0.0, Math.Min(100.0, remaining));
            if (safeRemaining <= 0.0)
            {
                return 0.0;
            }
            double diameter = Math.Max(1.0, radius * 2.0);
            double actualHeight = diameter * safeRemaining / 100.0;
            double minimumVisibleHeight = Math.Max(2.6, Math.Min(5.0, size * 0.10));
            double maximumVisibleHeight = diameter * 0.965;
            return Math.Min(maximumVisibleHeight, Math.Max(actualHeight, minimumVisibleHeight));
        }

        private static Geometry CreateWaveFill(
            Point center,
            double radius,
            double waterLine,
            double amplitude,
            double phase,
            double cycles)
        {
            double left = center.X - radius;
            double right = center.X + radius;
            double bottom = center.Y + radius;
            int segments = Math.Max(28, Math.Min(120, (int)Math.Ceiling(radius * 1.8)));

            StreamGeometry geometry = new StreamGeometry();
            using (StreamGeometryContext context = geometry.Open())
            {
                context.BeginFigure(new Point(left, bottom), true, true);
                for (int index = 0; index <= segments; index++)
                {
                    double progress = (double)index / segments;
                    double x = left + (right - left) * progress;
                    double y = waterLine + amplitude * Math.Sin(progress * Math.PI * 2.0 * cycles + phase);
                    context.LineTo(new Point(x, y), true, false);
                }
                context.LineTo(new Point(right, bottom), true, false);
            }
            if (geometry.CanFreeze)
            {
                geometry.Freeze();
            }
            return geometry;
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
