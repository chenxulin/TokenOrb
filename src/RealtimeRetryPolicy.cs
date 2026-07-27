using System;

namespace CodexQuotaBall
{
    public sealed class RealtimeRetryDecision
    {
        public int ConsecutiveFailures { get; set; }
        public int RetryAttempt { get; set; }
        public TimeSpan Delay { get; set; }
        public bool UseLocalFallback { get; set; }
    }

    public sealed class RealtimeRetryPolicy
    {
        public const int RestartRetryCount = 3;
        public const int LocalFallbackThreshold = RestartRetryCount + 1;
        public const int FallbackRetrySeconds = 30;

        private static readonly int[] RestartRetryDelaysSeconds = { 5, 10, 15 };

        private int consecutiveFailures;

        public int ConsecutiveFailures
        {
            get { return consecutiveFailures; }
        }

        public RealtimeRetryDecision RegisterFailure()
        {
            consecutiveFailures++;
            bool useLocalFallback = consecutiveFailures >= LocalFallbackThreshold;
            return new RealtimeRetryDecision
            {
                ConsecutiveFailures = consecutiveFailures,
                RetryAttempt = useLocalFallback ? 0 : consecutiveFailures,
                Delay = CalculateDelay(consecutiveFailures),
                UseLocalFallback = useLocalFallback
            };
        }

        public void Reset()
        {
            consecutiveFailures = 0;
        }

        public static TimeSpan CalculateDelay(int failureCount)
        {
            int normalized = Math.Max(1, failureCount);
            if (normalized <= RestartRetryDelaysSeconds.Length)
            {
                return TimeSpan.FromSeconds(RestartRetryDelaysSeconds[normalized - 1]);
            }
            return TimeSpan.FromSeconds(FallbackRetrySeconds);
        }
    }

    public static class LocalFallbackStatePolicy
    {
        public static bool Resolve(
            bool connected,
            bool currentlyActive,
            bool fallbackRequested)
        {
            return !connected && (currentlyActive || fallbackRequested);
        }
    }
}
