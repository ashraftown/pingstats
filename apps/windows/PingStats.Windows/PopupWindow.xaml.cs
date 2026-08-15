using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using Microsoft.Win32;

namespace PingStats;

public partial class PopupWindow : Window
{
    private readonly PingManager _pingManager;
    private readonly TrayManager _trayManager;
    private bool _isPinned;
    private bool _suppressClose;
    private bool _isDarkTheme;

    public PopupWindow(PingManager pingManager, TrayManager trayManager)
    {
        InitializeComponent();

        _pingManager = pingManager;
        _trayManager = trayManager;

        _pingManager.StateChanged += OnPingStateChanged;
        _trayManager.TrayIconClicked += OnTrayIconClicked;

        Loaded += (_, _) =>
        {
            HostTextBox.Text = _pingManager.Host;
            HostTextBox.TextChanged += (_, _) => UpdateUI();
            SetIntervalSelection(_pingManager.IntervalSeconds);
            ApplyTheme();
            UpdateUI();
        };

        IntervalCombo.SelectionChanged += (_, _) =>
        {
            if (IntervalCombo.SelectedItem is ComboBoxItem item &&
                double.TryParse(item.Tag?.ToString(), out var seconds))
            {
                _pingManager.SetInterval(seconds);
            }
        };

        SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
    }

    private void OnUserPreferenceChanged(object sender, UserPreferenceChangedEventArgs e)
    {
        if (e.Category == UserPreferenceCategory.General)
        {
            Dispatcher.Invoke(ApplyTheme);
        }
    }

    private bool IsSystemDarkTheme()
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

    private void ApplyTheme()
    {
        _isDarkTheme = IsSystemDarkTheme();

        var bg = _isDarkTheme ? Color.FromRgb(0x1E, 0x1E, 0x1E) : Color.FromRgb(0xFF, 0xFF, 0xFF);
        var fg = _isDarkTheme ? Color.FromRgb(0xE0, 0xE0, 0xE0) : Color.FromRgb(0x1A, 0x1A, 0x1A);
        var subduedFg = _isDarkTheme ? Color.FromRgb(0x99, 0x99, 0x99) : Color.FromRgb(0x66, 0x66, 0x66);
        var border = _isDarkTheme ? Color.FromRgb(0x44, 0x44, 0x44) : Color.FromRgb(0xCC, 0xCC, 0xCC);
        var separator = _isDarkTheme ? Color.FromRgb(0x33, 0x33, 0x33) : Color.FromRgb(0xE0, 0xE0, 0xE0);
        var graphBg = _isDarkTheme ? Color.FromRgb(0x1A, 0x1A, 0x1A) : Color.FromRgb(0xF0, 0xF0, 0xF0);
        var inputBg = _isDarkTheme ? Color.FromRgb(0x2D, 0x2D, 0x2D) : Color.FromRgb(0xFF, 0xFF, 0xFF);
        var inputBorder = _isDarkTheme ? Color.FromRgb(0x55, 0x55, 0x55) : Color.FromRgb(0xCC, 0xCC, 0xCC);

        PopupBorder.Background = new SolidColorBrush(bg);
        PopupBorder.BorderBrush = new SolidColorBrush(border);

        TitleText.Foreground = new SolidColorBrush(fg);
        HostLabel.Foreground = new SolidColorBrush(fg);
        IntervalLabel.Foreground = new SolidColorBrush(fg);
        LatestLabel.Foreground = new SolidColorBrush(subduedFg);
        StatsLabel.Foreground = new SolidColorBrush(subduedFg);
        IPLabel.Foreground = new SolidColorBrush(subduedFg);
        StatusLabel2.Foreground = new SolidColorBrush(subduedFg);
        StatusLabel.Foreground = new SolidColorBrush(subduedFg);
        StatsValue.Foreground = new SolidColorBrush(subduedFg);
        IPValue.Foreground = new SolidColorBrush(subduedFg);

        Separator1.Fill = new SolidColorBrush(separator);
        Separator2.Fill = new SolidColorBrush(separator);
        Separator3.Fill = new SolidColorBrush(separator);

        GraphBorder.Background = new SolidColorBrush(graphBg);

        HostTextBox.Background = new SolidColorBrush(inputBg);
        HostTextBox.Foreground = new SolidColorBrush(fg);
        HostTextBox.BorderBrush = new SolidColorBrush(inputBorder);
        HostTextBox.CaretBrush = new SolidColorBrush(fg);

        // ComboBox — uses custom ThemedComboBoxStyle ControlTemplate with
        // TemplateBinding, so setting these properties works directly.
        IntervalCombo.Background = new SolidColorBrush(inputBg);
        IntervalCombo.Foreground = new SolidColorBrush(fg);
        IntervalCombo.BorderBrush = new SolidColorBrush(inputBorder);

        // Dropdown items: ItemContainerStyle for hover/selected states.
        var comboItemStyle = new Style(typeof(ComboBoxItem));
        comboItemStyle.Setters.Add(new Setter(ComboBoxItem.BackgroundProperty, new SolidColorBrush(inputBg)));
        comboItemStyle.Setters.Add(new Setter(ComboBoxItem.ForegroundProperty, new SolidColorBrush(fg)));
        comboItemStyle.Setters.Add(new Setter(ComboBoxItem.BorderThicknessProperty, new Thickness(0)));

        var hoverTrigger = new Trigger { Property = ComboBoxItem.IsMouseOverProperty, Value = true };
        hoverTrigger.Setters.Add(new Setter(ComboBoxItem.BackgroundProperty, new SolidColorBrush(
            _isDarkTheme ? Color.FromRgb(0x3A, 0x3A, 0x3A) : Color.FromRgb(0xE5, 0xE5, 0xE5))));
        comboItemStyle.Triggers.Add(hoverTrigger);

        var selectedTrigger = new Trigger { Property = ComboBoxItem.IsSelectedProperty, Value = true };
        selectedTrigger.Setters.Add(new Setter(ComboBoxItem.BackgroundProperty,
            new SolidColorBrush(_isDarkTheme ? Color.FromRgb(0x3A, 0x3A, 0x3A) : Color.FromRgb(0xE5, 0xE5, 0xE5))));
        selectedTrigger.Setters.Add(new Setter(ComboBoxItem.ForegroundProperty, new SolidColorBrush(fg)));
        comboItemStyle.Triggers.Add(selectedTrigger);

        IntervalCombo.ItemContainerStyle = comboItemStyle;

        LoginCheckBox.Foreground = new SolidColorBrush(fg);
        QuitButton.Foreground = new SolidColorBrush(fg);

        PinButton.BorderBrush = new SolidColorBrush(border);
        UpdatePinIcon(fg);
    }

    private void OnPingStateChanged()
    {
        Dispatcher.Invoke(UpdateUI);
    }

    private void OnTrayIconClicked()
    {
        Dispatcher.Invoke(() =>
        {
            _suppressClose = true;

            if (IsVisible)
            {
                Hide();
            }
            else
            {
                Show();
                Activate();
                Dispatcher.BeginInvoke(new Action(PositionNearTray));
            }

            var timer = new System.Timers.Timer(200) { AutoReset = false };
            timer.Elapsed += (_, _) =>
            {
                Dispatcher.Invoke(() => _suppressClose = false);
                timer.Dispose();
            };
            timer.Start();
        });
    }

    private void UpdateUI()
    {
        var running = _pingManager.IsRunning;

        HostTextBox.IsEnabled = !running;
        StatusLabel.Text = running ? "pinging\u2026" : "paused";

        if (running)
        {
            StartStopButton.Background = new SolidColorBrush(Color.FromRgb(200, 50, 50));
            StartStopText.Text = "Stop";
        }
        else
        {
            StartStopButton.Background = SystemColors.HighlightBrush;
            StartStopText.Text = "Start";
        }

        StartStopButton.IsEnabled = running || !string.IsNullOrWhiteSpace(HostTextBox.Text);

        var color = running && _pingManager.LatestLatencyMs.HasValue
            ? _pingManager.LatestLatencyMs.Value < 50 ? Colors.LimeGreen :
              _pingManager.LatestLatencyMs.Value < 100 ? Colors.Gold :
              _pingManager.LatestLatencyMs.Value < 200 ? Colors.Orange :
              Colors.Red
            : Colors.Gray;

        LatestValue.Text = _pingManager.LatestLatency;
        LatestValue.Foreground = new SolidColorBrush(color);

        StatsValue.Text = _pingManager.StatsString;

        if (!string.IsNullOrEmpty(_pingManager.ResolvedIP))
        {
            IPRow.Visibility = Visibility.Visible;
            IPValue.Text = _pingManager.ResolvedIP;
        }
        else
        {
            IPRow.Visibility = Visibility.Collapsed;
        }

        StatusValue.Text = _pingManager.StatusMessage;
        StatusValue.Foreground = _pingManager.IsConnected
            ? new SolidColorBrush(Colors.LimeGreen)
            : new SolidColorBrush(Colors.Red);

        UpdateGraph();
    }

    private void UpdateGraph()
    {
        GraphCanvas.Children.Clear();

        var results = _pingManager.PingResults;
        if (results.Count == 0) return;

        var maxLatency = Math.Max(results.Max(), 1.0);
        var width = GraphCanvas.ActualWidth;
        var height = GraphCanvas.ActualHeight;

        if (width <= 0 || height <= 0) return;

        var barCount = results.Count;
        var spacing = 2.0;
        var barWidth = Math.Max(1, (width - (barCount - 1) * spacing) / barCount);

        for (int i = 0; i < barCount; i++)
        {
            var latency = results[i];
            var barHeight = Math.Max(2, (latency / maxLatency) * height);

            var barColor = latency < 50 ? Colors.LimeGreen :
                           latency < 100 ? Colors.Gold :
                           latency < 200 ? Colors.Orange :
                           Colors.Red;

            var rect = new Rectangle
            {
                Width = barWidth,
                Height = barHeight,
                Fill = new SolidColorBrush(barColor),
            };

            Canvas.SetLeft(rect, i * (barWidth + spacing));
            Canvas.SetBottom(rect, 0);
            GraphCanvas.Children.Add(rect);
        }
    }

    private void OnGraphSizeChanged(object sender, SizeChangedEventArgs e)
    {
        UpdateGraph();
    }

    private void PositionNearTray()
    {
        var workArea = SystemParameters.WorkArea;
        Left = workArea.Right - ActualWidth - 10;
        Top = workArea.Bottom - ActualHeight - 10;
    }

    private void SetIntervalSelection(double seconds)
    {
        foreach (ComboBoxItem item in IntervalCombo.Items)
        {
            if (double.TryParse(item.Tag?.ToString(), out var val) && Math.Abs(val - seconds) < 0.1)
            {
                IntervalCombo.SelectedItem = item;
                return;
            }
        }
    }

    private void UpdatePinIcon(Color fg)
    {
        if (_isPinned)
        {
            PinIcon.Fill = SystemColors.HighlightBrush;
            PinIcon.Stroke = Brushes.Transparent;
            PinIcon.StrokeThickness = 0;
        }
        else
        {
            PinIcon.Fill = Brushes.Transparent;
            PinIcon.Stroke = new SolidColorBrush(fg);
            PinIcon.StrokeThickness = 1.5;
        }
    }

    private void OnPinToggle(object sender, RoutedEventArgs e)
    {
        _isPinned = !_isPinned;
        var fg = _isDarkTheme ? Color.FromRgb(0xE0, 0xE0, 0xE0) : Color.FromRgb(0x1A, 0x1A, 0x1A);
        UpdatePinIcon(fg);
        PinButton.ToolTip = _isPinned
            ? "Unpin \u2014 close when clicking outside"
            : "Pin \u2014 keep open when clicking outside";
    }

    private void OnStartStopToggle(object sender, RoutedEventArgs e)
    {
        if (_pingManager.IsRunning)
            _pingManager.StopPinging();
        else
            StartPinging();
    }

    private void OnHostKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter && !_pingManager.IsRunning)
            StartPinging();
    }

    private void StartPinging()
    {
        var host = HostTextBox.Text.Trim();
        if (string.IsNullOrEmpty(host)) return;
        _pingManager.StartPinging(host);
    }

    private void OnDeactivated(object sender, EventArgs e)
    {
        if (!_isPinned && !_suppressClose && IsVisible)
        {
            Hide();
        }
    }

    private void OnWindowMouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton == MouseButton.Left)
            DragMove();
    }

    private void OnLoginCheckChanged(object sender, RoutedEventArgs e)
    {
        SetStartupWithWindows(LoginCheckBox.IsChecked == true);
    }

    private static void SetStartupWithWindows(bool enable)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Run", true);
            if (key == null) return;

            if (enable)
            {
                var exePath = Environment.ProcessPath;
                if (exePath != null)
                    key.SetValue("PingStats", $"\"{exePath}\"");
            }
            else
            {
                key.DeleteValue("PingStats", false);
            }
        }
        catch { }
    }

    private static bool IsStartupWithWindowsEnabled()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Run", false);
            return key?.GetValue("PingStats") != null;
        }
        catch { }
        return false;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        LoginCheckBox.IsChecked = IsStartupWithWindowsEnabled();
    }

    private void OnQuit(object sender, RoutedEventArgs e)
    {
        System.Windows.Application.Current.Shutdown();
    }

    protected override void OnClosed(EventArgs e)
    {
        SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
        _pingManager.StateChanged -= OnPingStateChanged;
        _trayManager.TrayIconClicked -= OnTrayIconClicked;
        base.OnClosed(e);
    }
}
