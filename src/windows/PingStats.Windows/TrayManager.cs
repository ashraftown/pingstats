using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace PingStats;

public class TrayManager : IDisposable
{
    private readonly NotifyIcon _notifyIcon;
    private readonly PingManager _pingManager;

    private const int IconWidth = 64;
    private const int IconHeight = 64;
    private const int DotSize = 7;
    private const int DotY = 0;
    private static readonly StringFormat StringFormat = StringFormat.GenericTypographic;

    public event Action? TrayIconClicked;

    public TrayManager(PingManager pingManager)
    {
        _pingManager = pingManager;

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

    private void OnStateChanged()
    {
        UpdateIcon();

        if (_notifyIcon.ContextMenuStrip?.Items["StartStop"] is ToolStripMenuItem item)
        {
            item.Text = _pingManager.IsRunning ? "Stop" : "Start";
        }

        _notifyIcon.Text = _pingManager.IsRunning
            ? $"PingStats - {_pingManager.Host}\n{_pingManager.LatestLatency}"
            : "PingStats - Stopped";
    }

    private void UpdateIcon()
    {
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

        g.DrawString(displayText, font, Brushes.White, textX, textY, StringFormat);

        var hIcon = bitmap.GetHicon();
        var oldIcon = _notifyIcon.Icon;
        _notifyIcon.Icon = Icon.FromHandle(hIcon);
        oldIcon?.Dispose();
    }

    private Color GetColor()
    {
        if (!_pingManager.IsRunning)
            return Color.Gray;

        if (_pingManager.LatestLatencyMs.HasValue)
        {
            var ms = _pingManager.LatestLatencyMs.Value;
            if (ms < 50) return Color.LimeGreen;
            if (ms < 100) return Color.Yellow;
            if (ms < 200) return Color.Orange;
            return Color.Red;
        }

        if (_pingManager.LatestLatency == "\u2717")
            return Color.Gray;

        return Color.Gray;
    }

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
        _pingManager.StateChanged -= OnStateChanged;
        _notifyIcon.Visible = false;
        _notifyIcon.Icon = null;
        _notifyIcon.Dispose();
    }
}
