using System;

namespace CodexQuotaBall
{
    public sealed class RealtimeRetryDecision
    {
        public int ConsecutiveFailures { get; set; }
        public TimeSpan Delay { get; set; }
        public bool UseLocalFallback { get; set; }
    }

    public sealed class RealtimeRetryPolicy
    {
        public const int LocalFallbackThreshold = 3;
        public const int InitialDelaySeconds = 2;
        public const int MaximumDelaySeconds = 30;

        private int consecutiveFailures;

        public int ConsecutiveFailures
        {
            get { return consecutiveFailures; }
        }

        public RealtimeRetryDecision RegisterFailure()
        {
            consecutiveFailures++;
            return new RealtimeRetryDecision
            {
                ConsecutiveFailures = consecutiveFailures,
                Delay = CalculateDelay(consecutiveFailures),
                UseLocalFallback = consecutiveFailures >= LocalFallbackThreshold
            };
        }

        public void Reset()
        {
            consecutiveFailures = 0;
        }

        public static TimeSpan CalculateDelay(int failureCount)
        {
            int normalized = Math.Max(1, failureCount);
            int seconds = InitialDelaySeconds;
            for (int index = 1; index < normalized && seconds < MaximumDelaySeconds; index++)
            {
                seconds = Math.Min(seconds * 2, MaximumDelaySeconds);
            }
            return TimeSpan.FromSeconds(seconds);
        }
    }
}
