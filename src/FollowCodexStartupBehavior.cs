namespace CodexQuotaBall
{
    public static class FollowCodexStartupBehavior
    {
        public static bool ShouldCreateDefaultPreference(
            bool currentPreferenceExists,
            bool legacyPreferenceExists)
        {
            return !currentPreferenceExists && !legacyPreferenceExists;
        }
    }
}
