using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.RegularExpressions;
using Timer = System.Timers.Timer;

namespace PingStats;

public class PingManager : IDisposable
{
    public string LatestLatency { get; private set; } = "--";
    public double? LatestLatencyMs { get; private set; }
    public string StatsString { get; private set; } = "--/--/--";
    public string StatusMessage { get; private set; } = "Ready";
    public bool IsConnected { get; private set; }
    public bool IsRunning { get; private set; }
    public double AverageLatency30S { get; private set; }
    public List<double> PingResults { get; } = new();
    public string ResolvedIP { get; private set; } = "";
    public string Host { get; private set; }
    public double IntervalSeconds { get; private set; }

    public event Action? StateChanged;

    private readonly object _lock = new();
    private Timer? _pingTimer;
    private bool _isPingInFlight;
    private int _generation;

    private const string DefaultHost = "8.8.8.8";
    private const double DefaultInterval = 1.0;

    private static readonly string SettingsDir =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "PingStats");
    private static readonly string SettingsFile = Path.Combine(SettingsDir, "settings.json");

    private record Settings(string Host, double IntervalSeconds);

    public PingManager()
    {
        var (savedHost, savedInterval) = LoadSettings();
        Host = string.IsNullOrEmpty(savedHost) ? DefaultHost : savedHost;
        IntervalSeconds = ClampedInterval(savedInterval > 0 ? savedInterval : DefaultInterval);
    }

    private static (string? host, double interval) LoadSettings()
    {
        try
        {
            if (File.Exists(SettingsFile))
            {
                var json = File.ReadAllText(SettingsFile);
                var s = JsonSerializer.Deserialize<Settings>(json);
                if (s != null) return (s.Host, s.IntervalSeconds);
            }
        }
        catch { }
        return (null, 0);
    }

    private void SaveSettings()
    {
        try
        {
            Directory.CreateDirectory(SettingsDir);
            var s = new Settings(Host, IntervalSeconds);
            File.WriteAllText(SettingsFile, JsonSerializer.Serialize(s));
        }
        catch { }
    }

    private static double ClampedInterval(double value) =>
        Math.Min(60, Math.Max(1, Math.Round(value)));

    public void StartPinging(string? newHost = null)
    {
        lock (_lock)
        {
            if (!string.IsNullOrWhiteSpace(newHost))
            {
                Host = newHost.Trim();
                SaveSettings();
            }

            var target = Host;
            var gen = ++_generation;
            PingResults.Clear();
            StatusMessage = "Resolving...";
            LatestLatency = "--";
            LatestLatencyMs = null;
            AverageLatency30S = 0;
            ResolvedIP = "";
            IsRunning = true;
            IsConnected = false;
            NotifyStateChanged();

            _pingTimer?.Dispose();
            _pingTimer = null;

            ResolveHost(target, resolvedHost =>
            {
                lock (_lock)
                {
                    if (!IsRunning || Host != target) return;

                    ResolvedIP = resolvedHost;
                    StatusMessage = "Connecting...";
                    NotifyStateChanged();

                    _isPingInFlight = true;
                    PerformPing(target, gen);
                    ScheduleTimer(target, gen);
                }
            });
        }
    }

    public void SetInterval(double seconds)
    {
        lock (_lock)
        {
            var clamped = ClampedInterval(seconds);
            IntervalSeconds = clamped;
            SaveSettings();

            if (IsRunning)
                ScheduleTimer(Host, _generation);
        }
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
                if (IsRunning && Host == target && !_isPingInFlight && _generation == generation)
                {
                    _isPingInFlight = true;
                    PerformPing(target, generation);
                }
            }
        };
        _pingTimer.AutoReset = false;
        _pingTimer.Start();
    }

    private void RescheduleTimer()
    {
        _pingTimer?.Stop();
        if (_pingTimer == null || !IsRunning) return;
        _pingTimer.Interval = TimeSpan.FromSeconds(IntervalSeconds).TotalMilliseconds;
        _pingTimer.Start();
    }

    private void ResolveHost(string host, Action<string> completion)
    {
        System.Threading.ThreadPool.QueueUserWorkItem(_ =>
        {
            try
            {
                var addresses = System.Net.Dns.GetHostAddresses(host);
                var ipv4 = addresses.FirstOrDefault(a =>
                    a.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork);
                completion(ipv4?.ToString() ?? host);
            }
            catch
            {
                completion(host);
            }
        });
    }

    public void StopPinging()
    {
        lock (_lock)
        {
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
            NotifyStateChanged();
        }
    }

    private void PerformPing(string host, int generation)
    {
        System.Threading.ThreadPool.QueueUserWorkItem(_ =>
        {
            try
            {
                var process = new Process
                {
                    StartInfo = new ProcessStartInfo
                    {
                        FileName = "ping",
                        Arguments = $"-n 1 -w 2000 {host}",
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        UseShellExecute = false,
                        CreateNoWindow = true,
                    }
                };

                process.Start();

                var exited = process.WaitForExit(5000);
                if (!exited)
                {
                    try { process.Kill(); } catch { }
                }

                var output = process.StandardOutput.ReadToEnd();
                var latency = ParsePingOutput(output);

                lock (_lock)
                {
                    if (!IsRunning || Host != host || _generation != generation)
                    {
                        _isPingInFlight = false;
                        return;
                    }

                    _isPingInFlight = false;

                    if (latency.HasValue)
                    {
                        LatestLatencyMs = latency.Value;
                        LatestLatency = $"{latency.Value:F2} ms";
                        PingResults.Add(latency.Value);

                        if (PingResults.Count > 30)
                            PingResults.RemoveAt(0);

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
                    }

                    NotifyStateChanged();
                    RescheduleTimer();
                }
            }
            catch (Exception ex)
            {
                lock (_lock)
                {
                    _isPingInFlight = false;
                    if (!IsRunning || _generation != generation) return;
                    StatusMessage = $"Error: {ex.Message}";
                    IsConnected = false;
                    LatestLatency = "\u2717";
                    LatestLatencyMs = null;
                    NotifyStateChanged();
                    RescheduleTimer();
                }
            }
        });
    }

    private static double? ParsePingOutput(string output)
    {
        var match = Regex.Match(output, @"time[=<](\d+(?:\.\d+)?)\s*ms");
        if (match.Success && double.TryParse(match.Groups[1].Value, out var ms))
            return ms;

        if (Regex.IsMatch(output, @"time<1ms"))
            return 0.5;

        return null;
    }

    private void UpdateStats()
    {
        if (PingResults.Count == 0)
        {
            StatsString = "---";
            AverageLatency30S = 0;
            return;
        }

        var min = PingResults.Min();
        var max = PingResults.Max();
        var avg = PingResults.Average();

        StatsString = $"{min:F1}/{avg:F1}/{max:F1}";
        AverageLatency30S = avg;
    }

    private void NotifyStateChanged()
    {
        StateChanged?.Invoke();
    }

    public void Dispose()
    {
        _pingTimer?.Dispose();
    }
}
