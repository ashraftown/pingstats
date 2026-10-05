using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;

namespace PingStats;

public class TrayManager : IDisposable
{
    [DllImport("user32.dll")]
    private static extern bool DestroyIcon(IntPtr handle);
    private readonly NotifyIcon _notifyIcon;
    private readonly PingManager _pingManager;
    private bool _isDarkTheme;
    private SolidBrush _textBrush = new(Color.White);
    private bool _disposed;

    private const int MaxTrayLatencyMs = 999;

    public event Action? TrayIconClicked;

    public TrayManager(PingManager pingManager)
    {
        _pingManager = pingManager;
        _isDarkTheme = IsSystemDarkTheme();
        _textBrush.Dispose();
        _textBrush = _isDarkTheme ? new SolidBrush(Color.White) : new SolidBrush(Color.FromArgb(0xFF, 0x1A, 0x1A, 0x1A));
        SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;

        _notifyIcon = new NotifyIcon
        {
            Text = "PingStats",
            Visible = true,
        };

        UpdateIcon();

        _notifyIcon.MouseClick += (_, e) =>
        {
            if (e.Button == MouseButtons.Left)
                TrayIconClicked?.Invoke();
        };

        var contextMenu = new ContextMenuStrip();
        var startStopItem = new ToolStripMenuItem("Start") { Name = "StartStop" };
        var quitItem = new ToolStripMenuItem("Quit PingStats");

        startStopItem.Click += (_, _) =>
        {
            if (_pingManager.IsRunning)
                _pingManager.StopPinging();
            else
                _pingManager.StartPinging();
        };

        quitItem.Click += (_, _) => System.Windows.Application.Current.Shutdown();

        contextMenu.Items.Add(startStopItem);
        contextMenu.Items.Add(new ToolStripSeparator());
        contextMenu.Items.Add(quitItem);

        _notifyIcon.ContextMenuStrip = contextMenu;

        _pingManager.StateChanged += OnStateChanged;
    }

    private void OnUserPreferenceChanged(object sender, UserPreferenceChangedEventArgs e)
    {
        if (e.Category != UserPreferenceCategory.General
            && e.Category != UserPreferenceCategory.Window
            && e.Category != UserPreferenceCategory.VisualStyle
            && e.Category != UserPreferenceCategory.Color) return;
        System.Windows.Application.Current.Dispatcher.BeginInvoke(() =>
        {
            if (_disposed) return;
            _isDarkTheme = IsSystemDarkTheme();
            _textBrush.Dispose();
            _textBrush = _isDarkTheme
                ? new SolidBrush(Color.White)
                : new SolidBrush(Color.FromArgb(0xFF, 0x1A, 0x1A, 0x1A));
            UpdateIcon();
        });
    }

    private static bool IsSystemDarkTheme()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            if (key?.GetValue("AppsUseLightTheme") is int value)
                return value == 0;
        }
        catch { }
        return false;
    }

    private void OnStateChanged()
    {
        if (_disposed) return;
        System.Windows.Application.Current.Dispatcher.BeginInvoke(() =>
        {
            if (_disposed) return;
            UpdateIcon();

            if (_notifyIcon.ContextMenuStrip?.Items["StartStop"] is ToolStripMenuItem item)
            {
                item.Text = _pingManager.IsRunning ? "Stop" : "Start";
            }

            var latency = _pingManager.LatestLatencyMs is double milliseconds
                ? $"{(int)Math.Round(milliseconds)}ms"
                : _pingManager.LatestLatency;
            _notifyIcon.Text = TrayText(_pingManager.IsRunning
                ? $"PingStats - {_pingManager.Host} - {latency}"
                : "PingStats - Stopped");
        });
    }

    private void UpdateIcon()
    {
        if (_disposed) return;
        var color = GetColor();
        var displayText = GetDisplayText();
        using var bitmap = TrayIconRenderer.Render(displayText, color, _textBrush.Color);

        var hIcon = bitmap.GetHicon();
        try
        {
            using var tmp = Icon.FromHandle(hIcon);
            // Give the tray a small-size icon instead of making the shell shrink the 64px image.
            var newIcon = new Icon(tmp, SystemInformation.SmallIconSize);
            var oldIcon = _notifyIcon.Icon;
            _notifyIcon.Icon = newIcon;
            oldIcon?.Dispose();
        }
        finally
        {
            DestroyIcon(hIcon);
        }
    }

    private Color GetColor()
    {
        if (!_pingManager.IsRunning)
            return Color.Gray;

        if (_pingManager.LatestLatencyMs.HasValue)
        {
            return LatencyScale.FromMilliseconds(_pingManager.LatestLatencyMs.Value) switch
            {
                LatencyTier.Green => _isDarkTheme ? Hex(0x34D399) : Hex(0x1F9D66),
                LatencyTier.Yellow => _isDarkTheme ? Hex(0xF5A623) : Hex(0xC77F0A),
                _ => _isDarkTheme ? Hex(0xF0625F) : Hex(0xE0524D),
            };
        }

        return Color.Gray;
    }

    private static string TrayText(string text)
    {
        const int limit = 127;
        return text.Length <= limit ? text : text[..(limit - 1)] + "\u2026";
    }

    private static Color Hex(uint value) =>
        Color.FromArgb((int)(value >> 16), (int)((value >> 8) & 0xFF), (int)(value & 0xFF));

    private string GetDisplayText()
    {
        if (!_pingManager.IsRunning)
            return "--";

        if (_pingManager.LatestLatencyMs is double milliseconds)
            return Math.Min((int)Math.Round(milliseconds), MaxTrayLatencyMs).ToString();

        if (_pingManager.LatestLatency == "\u2717")
            return "\u2717";

        return "\u2026";
    }

    public void Dispose()
    {
        _disposed = true;
        SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
        _pingManager.StateChanged -= OnStateChanged;
        System.Windows.Application.Current.Dispatcher.Invoke(() =>
        {
            _textBrush.Dispose();
            _notifyIcon.Visible = false;
            _notifyIcon.Icon = null;
            _notifyIcon.Dispose();
        });
    }
}
