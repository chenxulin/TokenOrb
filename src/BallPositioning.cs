using System;
using System.Windows;

namespace CodexQuotaBall
{
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
