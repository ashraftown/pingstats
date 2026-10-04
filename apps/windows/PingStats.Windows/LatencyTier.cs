namespace PingStats;

public enum LatencyTier
{
    Green,
    Yellow,
    Red
}

public static class LatencyScale
{
    public static LatencyTier FromMilliseconds(double ms) =>
        ms < 60 ? LatencyTier.Green : ms <= 120 ? LatencyTier.Yellow : LatencyTier.Red;
}
