using System;
using System.Windows;

namespace CodexQuotaBall
{
    internal static class OrbWindowMetrics
    {
        public const double PreviewWidth = 320.0;
        public const double PreviewHeight = 180.0;
        public const double PreviewCornerRadius = 18.0;

        public static Rect GetOrbBounds(double diameter)
        {
            double safeDiameter = Math.Max(
                0.0,
                Math.Min(diameter, Math.Min(PreviewWidth, PreviewHeight)));
            return new Rect(
                (PreviewWidth - safeDiameter) / 2.0,
                (PreviewHeight - safeDiameter) / 2.0,
                safeDiameter,
                safeDiameter);
        }

        public static Point WindowOriginFromOrbOrigin(Point orbOrigin, double diameter)
        {
            Rect orbBounds = GetOrbBounds(diameter);
            return new Point(orbOrigin.X - orbBounds.X, orbOrigin.Y - orbBounds.Y);
        }

        public static Point OrbOriginFromWindowOrigin(Point windowOrigin, double diameter)
        {
            Rect orbBounds = GetOrbBounds(diameter);
            return new Point(windowOrigin.X + orbBounds.X, windowOrigin.Y + orbBounds.Y);
        }

        public static Point ClampWindowOriginByOrb(
            Point windowOrigin,
            double diameter,
            Rect workArea)
        {
            Point orbOrigin = OrbOriginFromWindowOrigin(windowOrigin, diameter);
            Point clampedOrbOrigin = BallPositioning.ClampToWorkArea(
                orbOrigin,
                new Size(diameter, diameter),
                workArea);
            return WindowOriginFromOrbOrigin(clampedOrbOrigin, diameter);
        }
    }

    internal static class BallPositioning
    {
        public static Point ClampToWorkArea(
            Point position,
            Size size,
            Rect workArea)
        {
            double safeWidth = Math.Max(0.0, size.Width);
            double safeHeight = Math.Max(0.0, size.Height);
            double maxLeft = Math.Max(workArea.Left, workArea.Right - safeWidth);
            double maxTop = Math.Max(workArea.Top, workArea.Bottom - safeHeight);
            return new Point(
                Math.Max(workArea.Left, Math.Min(position.X, maxLeft)),
                Math.Max(workArea.Top, Math.Min(position.Y, maxTop)));
        }

        public static Point PreserveCenterOnResize(
            Point currentPosition,
            Size currentSize,
            Size newSize,
            Rect workArea)
        {
            Point resizedPosition = new Point(
                currentPosition.X + currentSize.Width / 2.0 - newSize.Width / 2.0,
                currentPosition.Y + currentSize.Height / 2.0 - newSize.Height / 2.0);
            return ClampToWorkArea(resizedPosition, newSize, workArea);
        }
    }
}
