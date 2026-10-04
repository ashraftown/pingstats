using Xunit;

namespace PingStats.Tests;

public class PingManagerTests
{
    [Fact]
    public void Callback_does_not_hold_the_lock()
    {
        using var mgr = new PingManager();
        var failed = false;
        void Handler()
        {
            var worker = new Thread(() => mgr.PingResultsSnapshot());
            worker.Start();
            if (!worker.Join(TimeSpan.FromSeconds(2)))
                failed = true;
        }

        mgr.StateChanged += Handler;
        try
        {
            mgr.StartPinging("127.0.0.1");
            Assert.False(failed);
        }
        finally
        {
            mgr.StateChanged -= Handler;
            mgr.StopPinging();
        }
    }

    [Fact]
    public void Invalid_host_does_not_start()
    {
        using var mgr = new PingManager();
        mgr.StartPinging("-c");
        Assert.False(mgr.IsRunning);
        Assert.Equal("Invalid host", mgr.StatusMessage);
    }

    [Theory]
    [InlineData(7, 5)]
    [InlineData(0, 1)]
    [InlineData(100, 60)]
    [InlineData(45, 30)]
    public void Interval_snaps_to_nearest_supported_value(double input, double expected)
    {
        using var mgr = new PingManager();
        mgr.SetInterval(input);
        Assert.Equal(expected, mgr.IntervalSeconds);
    }

    [Theory]
    [InlineData("8.8.8.8", true)]
    [InlineData("example.com", true)]
    [InlineData("fe80::1", true)]
    [InlineData("-c", false)]
    [InlineData("bad host", false)]
    [InlineData("", false)]
    public void Host_rejects_flags_and_spaces(string host, bool valid)
    {
        Assert.Equal(valid, PingManager.IsValidHost(host));
    }

    [Fact]
    public void Probe_address_strips_brackets()
    {
        Assert.Equal("::1", PingManager.NormalizeProbeAddress("[::1]"));
        Assert.Equal("8.8.8.8", PingManager.NormalizeProbeAddress("8.8.8.8"));
    }

    [Theory]
    [InlineData(59, LatencyTier.Green)]
    [InlineData(60, LatencyTier.Yellow)]
    [InlineData(120, LatencyTier.Yellow)]
    [InlineData(121, LatencyTier.Red)]
    public void Tier_matches_the_documented_scale(double ms, LatencyTier tier)
    {
        Assert.Equal(tier, LatencyScale.FromMilliseconds(ms));
    }
}
