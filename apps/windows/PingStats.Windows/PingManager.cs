using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Text.Json;
using Timer = System.Timers.Timer;

namespace PingStats;

public class PingManager : IDisposable
{
    public string LatestLatency { get; private set; } = "--";
    public double? LatestLatencyMs { get; private set; }
    public string StatsString { get; private set; } = "--/--/--";
    public string StatusMessage { get; private set; } = "Ready";
    public string SettingsWarning { get; private set; } = "";
    public bool IsConnected { get; private set; }
    public bool IsRunning { get; private set; }
    public double AverageLatency30S { get; private set; }
    private readonly List<double?> _pingResults = new();
    public string ResolvedIP { get; private set; } = "";
    public string Host { get; private set; }
    public double IntervalSeconds { get; private set; }

    public event Action? StateChanged;

    private readonly object _lock = new();
    private Timer? _pingTimer;
    private bool _isPingInFlight;
    private int _generation;
    private string _probeAddress = "";

    private const string DefaultHost = "8.8.8.8";
    private const double DefaultInterval = 1.0;
    private const int SampleWindow = 30;
    internal static readonly double[] SupportedIntervals = { 1, 5, 10, 30, 60 };

    private static readonly string SettingsDir =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "PingStats");
    private static readonly string SettingsFile = Path.Combine(SettingsDir, "settings.json");

    private record Settings(string Host, double IntervalSeconds);

    public PingManager()
    {
        var (savedHost, savedInterval) = LoadSettings();
        Host = string.IsNullOrEmpty(savedHost) ? DefaultHost : savedHost;
        var loadedInterval = savedInterval > 0 ? savedInterval : DefaultInterval;
        IntervalSeconds = NormalizedInterval(loadedInterval);
        if (Math.Abs(IntervalSeconds - loadedInterval) > 0.1 && !SaveSettings())
            SettingsWarning = "Could not save settings";
    }

    /// Returns a thread-safe copy of the last 30 attempts. Null is a timeout.
    public double?[] PingResultsSnapshot()
    {
        lock (_lock)
        {
            return _pingResults.ToArray();
        }
    }

    /// True when the string can be passed to ping without being read as a flag.
    internal static bool IsValidHost(string host)
    {
        if (string.IsNullOrWhiteSpace(host) || host.Length > 253 || host.StartsWith('-'))
            return false;
        foreach (var c in host)
        {
            if (char.IsAsciiLetterOrDigit(c) || c is '.' or '-' or ':' or '[' or ']' or '%')
                continue;
            return false;
        }
        var scopeSeparator = host.IndexOf('%');
        if (scopeSeparator >= 0
            && (scopeSeparator != host.LastIndexOf('%')
                || scopeSeparator == host.Length - 1
                || !host[(scopeSeparator + 1)..].All(char.IsAsciiDigit)
                || !IPAddress.TryParse(host[..scopeSeparator], out var scopedAddress)
                || scopedAddress.AddressFamily != AddressFamily.InterNetworkV6))
            return false;
        return true;
    }

    internal static string NormalizeProbeAddress(string address)
    {
        if (address.Length >= 2 && address[0] == '[' && address[^1] == ']')
            return address[1..^1];
        return address;
    }

    private static bool TryParseScopedIPv6(string address, out IPAddress parsedAddress)
    {
        parsedAddress = IPAddress.None;
        var scopeSeparator = address.IndexOf('%');
        if (scopeSeparator <= 0 || scopeSeparator != address.LastIndexOf('%')
            || !uint.TryParse(address[(scopeSeparator + 1)..], out var scopeId)
            || !IPAddress.TryParse(address[..scopeSeparator], out var baseAddress)
            || baseAddress.AddressFamily != AddressFamily.InterNetworkV6)
            return false;

        parsedAddress = new IPAddress(baseAddress.GetAddressBytes(), scopeId);
        return true;
    }

    private static (string? host, double interval) LoadSettings()
    {
        try
        {
            if (!File.Exists(SettingsFile))
                return (null, 0);
            var json = File.ReadAllText(SettingsFile);
            var s = JsonSerializer.Deserialize<Settings>(json);
            if (s != null)
                return (s.Host, s.IntervalSeconds);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException)
        {
        }
        return (null, 0);
    }

    private bool SaveSettings()
    {
        try
        {
            Directory.CreateDirectory(SettingsDir);
            File.WriteAllText(SettingsFile, JsonSerializer.Serialize(new Settings(Host, IntervalSeconds)));
            SettingsWarning = "";
            return true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException)
        {
            SettingsWarning = "Could not save settings";
            return false;
        }
    }

    private static double ClampedInterval(double value) =>
        Math.Min(60, Math.Max(1, Math.Round(value)));

    internal static double NormalizedInterval(double value)
    {
        var clamped = ClampedInterval(value);
        return SupportedIntervals.MinBy(option => Math.Abs(option - clamped));
    }

    public void StartPinging(string? newHost = null)
    {
        Action? notify = null;
        var target = "";
        var gen = 0;
        var rejected = false;
        lock (_lock)
        {
            if (!string.IsNullOrWhiteSpace(newHost))
            {
                var trimmed = newHost.Trim();
                if (!IsValidHost(trimmed))
                {
                    StatusMessage = "Invalid host";
                    rejected = true;
                }
                else
                {
                    Host = trimmed;
                    SaveSettings();
                }
            }

            if (!rejected && !IsValidHost(Host))
            {
                StatusMessage = "Invalid host";
                rejected = true;
            }

            if (rejected)
            {
                notify = StateChanged;
            }
            else
            {
                target = Host;
                gen = ++_generation;
                _isPingInFlight = false;
                _probeAddress = "";
                _pingResults.Clear();
                StatusMessage = "Resolving...";
                LatestLatency = "--";
                LatestLatencyMs = null;
                AverageLatency30S = 0;
                ResolvedIP = "";
                IsRunning = true;
                IsConnected = false;
                StatsString = "--/--/--";
                notify = StateChanged;
                _pingTimer?.Dispose();
                _pingTimer = null;
            }
        }

        notify?.Invoke();
        if (rejected)
            return;

        ResolveHost(target, resolvedHost =>
        {
            Action? inner = null;
            lock (_lock)
            {
                if (!IsRunning || Host != target || _generation != gen)
                    return;

                ResolvedIP = resolvedHost;
                _probeAddress = resolvedHost;
                StatusMessage = "Connecting...";
                inner = StateChanged;
                _isPingInFlight = true;
                PerformPing(target, gen, resolvedHost);
                ScheduleTimer(target, gen);
            }

            inner?.Invoke();
        });
    }

    public void SetInterval(double seconds)
    {
        Action? notify = null;
        lock (_lock)
        {
            IntervalSeconds = NormalizedInterval(seconds);
            SaveSettings();
            if (!string.IsNullOrEmpty(SettingsWarning))
            {
                StatusMessage = SettingsWarning;
                notify = StateChanged;
            }

            if (IsRunning && !_isPingInFlight)
                ScheduleTimer(Host, _generation);
        }

        notify?.Invoke();
    }

    private void ScheduleTimer(string target, int generation)
    {
        _pingTimer?.Dispose();
        var interval = TimeSpan.FromSeconds(IntervalSeconds);
        _pingTimer = new Timer(interval.TotalMilliseconds);
        _pingTimer.Elapsed += (_, _) =>
        {
            lock (_lock)
            {
                if (!IsRunning || Host != target || _isPingInFlight || _generation != generation)
                    return;
                _isPingInFlight = true;
                var probe = string.IsNullOrEmpty(_probeAddress) ? target : _probeAddress;
                PerformPing(target, generation, probe);
            }
        };
        _pingTimer.AutoReset = false;
        _pingTimer.Start();
    }

    private void RescheduleTimer()
    {
        _pingTimer?.Stop();
        if (_pingTimer == null || !IsRunning)
            return;
        _pingTimer.Interval = TimeSpan.FromSeconds(IntervalSeconds).TotalMilliseconds;
        _pingTimer.Start();
    }

    private static void ResolveHost(string host, Action<string> completion)
    {
        System.Threading.ThreadPool.QueueUserWorkItem(_ =>
        {
            try
            {
                var addresses = Dns.GetHostAddresses(host);
                var ipv4 = addresses.FirstOrDefault(a => a.AddressFamily == AddressFamily.InterNetwork);
                var ipv6 = addresses.FirstOrDefault(a => a.AddressFamily == AddressFamily.InterNetworkV6);
                completion((ipv4 ?? ipv6)?.ToString() ?? host);
            }
            catch
            {
                completion(host);
            }
        });
    }

    public void StopPinging()
    {
        Action? notify = null;
        lock (_lock)
        {
            _generation++;
            _pingTimer?.Dispose();
            _pingTimer = null;
            IsRunning = false;
            _isPingInFlight = false;
            IsConnected = false;
            StatusMessage = "Stopped";
            LatestLatency = "--";
            LatestLatencyMs = null;
            AverageLatency30S = 0;
            ResolvedIP = "";
            _probeAddress = "";
            notify = StateChanged;
        }

        notify?.Invoke();
    }

    private void PerformPing(string host, int generation, string probeAddress)
    {
        var address = NormalizeProbeAddress(probeAddress);
        System.Threading.ThreadPool.QueueUserWorkItem(_ =>
        {
            try
            {
                using var ping = new System.Net.NetworkInformation.Ping();
                var reply = TryParseScopedIPv6(address, out var scopedIp)
                    ? ping.Send(scopedIp, 2000)
                    : IPAddress.TryParse(address, out var ip)
                        ? ping.Send(ip, 2000)
                        : ping.Send(address, 2000);
                double? latency = reply != null
                    && reply.Status == System.Net.NetworkInformation.IPStatus.Success
                    ? reply.RoundtripTime
                    : null;
                PublishProbe(host, generation, latency, null);
            }
            catch (Exception ex)
            {
                PublishProbe(host, generation, null, ex.Message);
            }
        });
    }

    private void PublishProbe(string host, int generation, double? latency, string? error)
    {
        Action? notify = null;
        lock (_lock)
        {
            if (!IsRunning || Host != host || _generation != generation)
            {
                if (_generation == generation)
                    _isPingInFlight = false;
                return;
            }

            _isPingInFlight = false;
            if (error != null)
            {
                StatusMessage = $"Error: {error}";
                IsConnected = false;
                LatestLatency = "\u2717";
                LatestLatencyMs = null;
                AppendSample(null);
            }
            else if (latency.HasValue)
            {
                LatestLatencyMs = latency.Value;
                LatestLatency = $"{latency.Value:F2} ms";
                AppendSample(latency);
                UpdateStats();
                IsConnected = true;
                StatusMessage = "Connected";
            }
            else
            {
                IsConnected = false;
                StatusMessage = "Timeout";
                LatestLatency = "\u2717";
                LatestLatencyMs = null;
                AppendSample(null);
            }

            notify = StateChanged;
            RescheduleTimer();
        }

        notify?.Invoke();
    }

    private void AppendSample(double? sample)
    {
        _pingResults.Add(sample);
        if (_pingResults.Count > SampleWindow)
            _pingResults.RemoveAt(0);
    }

    private void UpdateStats()
    {
        var samples = _pingResults.Where(v => v.HasValue).Select(v => v!.Value).ToArray();
        if (samples.Length == 0)
        {
            StatsString = "---";
            AverageLatency30S = 0;
            return;
        }

        StatsString = $"{samples.Min():F1}/{samples.Average():F1}/{samples.Max():F1}";
        AverageLatency30S = samples.Average();
    }

    public void Dispose()
    {
        StopPinging();
    }
}
