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
    private const int ThreeDigitDotSize = 6;
    private const int DotY = 0;
    private const int MaxTrayLatencyMs = 999;
    private const int TwoDigitFontSize = 48;
    private const int ThreeDigitFontSize = 40;
    private const float ThreeDigitHorizontalScale = 0.8f;
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
        var isThreeDigit = displayText.Length == 3;
        var dotSize = isThreeDigit ? ThreeDigitDotSize : DotSize;

        using var bitmap = new Bitmap(IconWidth, IconHeight);
        using var g = Graphics.FromImage(bitmap);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAlias;
        g.Clear(Color.Transparent);

        var dotX = (IconWidth - dotSize) / 2;
        using (var brush = new SolidBrush(color))
        {
            g.FillEllipse(brush, dotX, DotY, dotSize, dotSize);
        }

        var fontSize = isThreeDigit ? ThreeDigitFontSize : TwoDigitFontSize;
        using var font = new Font("Consolas", fontSize, FontStyle.Regular, GraphicsUnit.Pixel);
        var textSize = g.MeasureString(displayText, font, int.MaxValue, StringFormat);
        var textX = (IconWidth - textSize.Width) / 2;
        var textY = DotY + dotSize;

        var textState = g.Save();
        try
        {
            if (isThreeDigit)
            {
                var horizontalOffset = IconWidth * (1f - ThreeDigitHorizontalScale) / 2f;
                using var transform = new Matrix(
                    ThreeDigitHorizontalScale, 0,
                    0, 1,
                    horizontalOffset, 0);
                g.Transform = transform;
            }

            g.DrawString(displayText, font, _textBrush, textX, textY, StringFormat);
        }
        finally
        {
            g.Restore(textState);
        }

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
