using System;
using System.Drawing;
using System.Drawing.Drawing2D;
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

    private const int IconWidth = 64;
    private const int IconHeight = 64;
    private const int DotSize = 7;
    private const int DotY = 0;
    private static readonly StringFormat StringFormat = StringFormat.GenericTypographic;

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

            _notifyIcon.Text = _pingManager.IsRunning
                ? $"PingStats - {_pingManager.Host}\n{_pingManager.LatestLatency}"
                : "PingStats - Stopped";
        });
    }

    private void UpdateIcon()
    {
        if (_disposed) return;
        var color = GetColor();
        var displayText = GetDisplayText();

        using var bitmap = new Bitmap(IconWidth, IconHeight);
        using var g = Graphics.FromImage(bitmap);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAlias;
        g.Clear(Color.Transparent);

        var dotX = (IconWidth - DotSize) / 2;
        using (var brush = new SolidBrush(color))
        {
            g.FillEllipse(brush, dotX, DotY, DotSize, DotSize);
        }

        using var font = new Font("Consolas", 54, FontStyle.Bold, GraphicsUnit.Pixel);
        var textSize = g.MeasureString(displayText, font, int.MaxValue, StringFormat);
        var textX = (IconWidth - textSize.Width) / 2;
        var textY = DotY + DotSize;

        g.DrawString(displayText, font, _textBrush, textX, textY, StringFormat);

        var hIcon = bitmap.GetHicon();
        try
        {
            using var tmp = Icon.FromHandle(hIcon);
            var newIcon = (Icon)tmp.Clone();
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
            var ms = _pingManager.LatestLatencyMs.Value;
            if (ms < 60) return _isDarkTheme ? Hex(0x34D399) : Hex(0x1F9D66);
            if (ms <= 120) return _isDarkTheme ? Hex(0xF5A623) : Hex(0xC77F0A);
            return _isDarkTheme ? Hex(0xF0625F) : Hex(0xE0524D);
        }

        return Color.Gray;
    }

    private static Color Hex(uint value) =>
        Color.FromArgb((int)(value >> 16), (int)((value >> 8) & 0xFF), (int)(value & 0xFF));

    private string GetDisplayText()
    {
        if (!_pingManager.IsRunning)
            return "--";

        if (_pingManager.LatestLatencyMs.HasValue)
            return ((int)Math.Round(_pingManager.LatestLatencyMs.Value)).ToString();

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
