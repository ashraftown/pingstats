using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
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
    private Palette _pal = DarkPalette();

    private static readonly double[] IntervalOptions = { 1, 5, 10, 30, 60 };
    private static readonly string[] IntervalLabels = { "1 second", "5 seconds", "10 seconds", "30 seconds", "1 minute" };

    private static readonly Geometry PlayGlyph = Geometry.Parse(
        "M8,5.14v13.72c0,0.93 1.04,1.5 1.81,1l10.4,-6.86c0.73,-0.48 0.73,-1.55 0,-2.03L9.81,4.14C9.04,3.64 8,4.21 8,5.14Z");
    private static readonly Geometry StopGlyph = Geometry.Parse(
        "M4,2h10a2,2 0 0,1 2,2v10a2,2 0 0,1 -2,2H4a2,2 0 0,1 -2,-2V4a2,2 0 0,1 2,-2Z");

    private List<double> _settledChart = new();
    private bool _chartAnimating;
    private Color _chartColor;
    private bool _headerDotPulsing;

    private sealed class Palette
    {
        public Color Background;
        public Color Border;
        public Color Text;
        public Color Muted;
        public Color Muted2;
        public Color Footer;
        public Color InputBg;
        public Color InputBorder;
        public Color Axis;
        public Color GridDashed;
        public Color GridBaseline;
        public Color Accent;
        public Color Green;
        public Color Yellow;
        public Color Red;
        public Color RedLabel;
        public Color PillNeutralBg;
        public Color StatsBorder;
        public Color StatDivider;
        public Color ComboHover;
        public Color ToggleTrackOff;
        public Color ToggleTrackOn;
    }

    private static Palette DarkPalette() => new()
    {
        Background = Hex(0x0B0C0F),
        Border = Color.FromArgb(20, 255, 255, 255),
        Text = Hex(0xF5F6F7),
        Muted = Hex(0x71757D),
        Muted2 = Hex(0x9AA0A8),
        Footer = Hex(0xB8BABF),
        InputBg = Color.FromArgb(10, 255, 255, 255),
        InputBorder = Color.FromArgb(20, 255, 255, 255),
        Axis = Hex(0x5B5F66),
        GridDashed = Color.FromArgb(13, 255, 255, 255),
        GridBaseline = Color.FromArgb(20, 255, 255, 255),
        Accent = Hex(0x4C8DFF),
        Green = Hex(0x34D399),
        Yellow = Hex(0xF5A623),
        Red = Hex(0xF0625F),
        RedLabel = Hex(0xF0958F),
        PillNeutralBg = Color.FromArgb(15, 255, 255, 255),
        StatsBorder = Color.FromArgb(15, 255, 255, 255),
        StatDivider = Color.FromArgb(20, 255, 255, 255),
        ComboHover = Hex(0x2A2B2F),
        ToggleTrackOff = Hex(0x4A4E55),
        ToggleTrackOn = Hex(0x4C8DFF),
    };

    private static Palette LightPalette() => new()
    {
        Background = Hex(0xFFFFFF),
        Border = Hex(0xE0E0E0),
        Text = Hex(0x1A1A1A),
        Muted = Hex(0x6E6E6E),
        Muted2 = Hex(0x4A4A4A),
        Footer = Hex(0x555555),
        InputBg = Hex(0xF5F5F5),
        InputBorder = Hex(0xD0D0D0),
        Axis = Hex(0x8A8A8A),
        GridDashed = Hex(0xE6E6E6),
        GridBaseline = Hex(0xD6D6D6),
        Accent = Hex(0x3B7BDB),
        Green = Hex(0x1F9D66),
        Yellow = Hex(0xC77F0A),
        Red = Hex(0xE0524D),
        RedLabel = Hex(0xC44740),
        PillNeutralBg = Hex(0xF0F0F0),
        StatsBorder = Hex(0xEFEFEF),
        StatDivider = Hex(0xE8E8E8),
        ComboHover = Hex(0xE9E9E9),
        ToggleTrackOff = Hex(0xE0E0E0),
        ToggleTrackOn = Hex(0x3B7BDB),
    };

    private static Color Hex(uint value) =>
        Color.FromRgb((byte)(value >> 16), (byte)(value >> 8), (byte)value);

    private static SolidColorBrush Brush(Color color) => new(color);

    private static Color Tint(Color color, byte alpha)
    {
        return Color.FromArgb(alpha, color.R, color.G, color.B);
    }

    public PopupWindow(PingManager pingManager, TrayManager trayManager)
    {
        InitializeComponent();

        _pingManager = pingManager;
        _trayManager = trayManager;

        _pingManager.StateChanged += OnPingStateChanged;
        _trayManager.TrayIconClicked += OnTrayIconClicked;

        Loaded += (_, _) =>
        {
            _isDarkTheme = IsSystemDarkTheme();
            _pal = _isDarkTheme ? DarkPalette() : LightPalette();
            HostTextBox.Text = _pingManager.Host;
            HostTextBox.TextChanged += (_, _) => UpdateUI();
            SetIntervalSelection(_pingManager.IntervalSeconds);
            ApplyTheme();
            UpdateUI();
            if (LoginCheckBox.Template?.FindName("KnobTranslate", LoginCheckBox) is TranslateTransform knob)
            {
                knob.BeginAnimation(TranslateTransform.XProperty, null);
                knob.X = LoginCheckBox.IsChecked == true ? 12 : 0;
            }
        };

        IntervalCombo.ItemsSource = IntervalLabels;

        IntervalCombo.SelectionChanged += (_, _) =>
        {
            if (IntervalCombo.SelectedIndex >= 0 && IntervalCombo.SelectedIndex < IntervalOptions.Length)
            {
                _pingManager.SetInterval(IntervalOptions[IntervalCombo.SelectedIndex]);
            }
        };

        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.Escape && QuitConfirmRow.Visibility == Visibility.Visible)
            {
                HideQuitConfirm();
            }
        };

        SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
    }

    private void OnUserPreferenceChanged(object sender, UserPreferenceChangedEventArgs e)
    {
        if (e.Category == UserPreferenceCategory.General)
        {
            Dispatcher.Invoke(() =>
            {
                _isDarkTheme = IsSystemDarkTheme();
                _pal = _isDarkTheme ? DarkPalette() : LightPalette();
                ApplyTheme();
                UpdateUI();
            });
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
        PopupBorder.Background = Brush(_pal.Background);
        PopupBorder.BorderBrush = Brush(_pal.Border);

        TitleText.Foreground = Brush(_pal.Text);
        HostLabel.Foreground = Brush(_pal.Muted);
        IntervalLabel.Foreground = Brush(_pal.Muted);
        StatusLabel.Foreground = Brush(_pal.Muted);
        StatMinLabel.Foreground = Brush(_pal.Muted);
        StatAvgLabel.Foreground = Brush(_pal.Muted);
        StatMaxLabel.Foreground = Brush(_pal.Muted);

        HeroUnit.Foreground = Brush(_pal.Muted);
        HeroCaption.Foreground = Brush(_pal.Muted);

        AxisTopLabel.Foreground = Brush(_pal.Axis);
        AxisMidLabel.Foreground = Brush(_pal.Axis);
        AxisBottomLabel.Foreground = Brush(_pal.Axis);
        GridTop.Stroke = Brush(_pal.GridDashed);
        GridMid.Stroke = Brush(_pal.GridDashed);
        GridBottom.Stroke = Brush(_pal.GridBaseline);

        StatsTopBorder.Fill = Brush(_pal.StatsBorder);
        StatsBottomBorder.Fill = Brush(_pal.StatsBorder);
        StatDivider1.Fill = Brush(_pal.StatDivider);
        StatDivider2.Fill = Brush(_pal.StatDivider);

        HostTextBox.Background = Brush(_pal.InputBg);
        HostTextBox.Foreground = Brush(_pal.Text);
        HostTextBox.BorderBrush = Brush(_pal.InputBorder);
        HostTextBox.CaretBrush = Brush(_pal.Text);

        IntervalCombo.Background = Brush(_pal.InputBg);
        IntervalCombo.Foreground = Brush(_pal.Text);
        IntervalCombo.BorderBrush = Brush(_pal.InputBorder);
        Resources["DropdownBg"] = Brush(_pal.Background);

        var comboItemStyle = new Style(typeof(ComboBoxItem));
        comboItemStyle.Setters.Add(new Setter(ComboBoxItem.BackgroundProperty, Brush(_pal.Background)));
        comboItemStyle.Setters.Add(new Setter(ComboBoxItem.ForegroundProperty, Brush(_pal.Text)));
        comboItemStyle.Setters.Add(new Setter(ComboBoxItem.BorderThicknessProperty, new Thickness(0)));

        var hoverTrigger = new Trigger { Property = ComboBoxItem.IsMouseOverProperty, Value = true };
        hoverTrigger.Setters.Add(new Setter(ComboBoxItem.BackgroundProperty,
            Brush(_pal.ComboHover)));
        comboItemStyle.Triggers.Add(hoverTrigger);

        var selectedTrigger = new Trigger { Property = ComboBoxItem.IsSelectedProperty, Value = true };
        selectedTrigger.Setters.Add(new Setter(ComboBoxItem.BackgroundProperty,
            Brush(_pal.ComboHover)));
        selectedTrigger.Setters.Add(new Setter(ComboBoxItem.ForegroundProperty, Brush(_pal.Text)));
        comboItemStyle.Triggers.Add(selectedTrigger);

        IntervalCombo.ItemContainerStyle = comboItemStyle;

        LoginCheckBox.Foreground = Brush(_pal.Footer);
        Resources["ToggleTrackOff"] = Brush(_pal.ToggleTrackOff);
        Resources["ToggleTrackOn"] = Brush(_pal.ToggleTrackOn);
        Resources["ToggleKnob"] = Brushes.White;
        QuitButton.Background = Brushes.Transparent;
        QuitButton.BorderBrush = Brush(_pal.Border);
        QuitButton.Foreground = Brush(_pal.Footer);
        QuitCancelBtn.Background = Brushes.Transparent;
        QuitCancelBtn.BorderBrush = Brush(_pal.Border);
        QuitCancelBtn.Foreground = Brush(_pal.Footer);
        QuitConfirmBtn.Background = Brush(Tint(_pal.Red, 31));
        QuitConfirmBtn.BorderBrush = Brush(Tint(_pal.Red, 71));
        QuitConfirmBtn.Foreground = Brush(_pal.RedLabel);

        UpdatePinIcon();
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
        var connected = running && _pingManager.IsConnected;
        var timedOut = running && !connected && _pingManager.LatestLatency == "\u2717";
        var resolving = running && !connected && !timedOut;

        HostTextBox.IsEnabled = !running;

        // Header + status pill + hero
        Color headerDot;
        Color pillBg;
        Color pillFg;
        Color pillDot;
        Color pillBorder;
        string pillText;
        string heroCaption;
        string heroNumber;
        Color heroColor;
        bool heroHasUnit;

        if (connected)
        {
            headerDot = _pal.Green;
            pillBg = Tint(_pal.Green, 31);
            pillFg = _pal.Green;
            pillDot = _pal.Green;
            pillBorder = Tint(_pal.Green, 71);
            pillText = "connected";
            heroCaption = "latest ping";
            heroHasUnit = true;
            if (_pingManager.LatestLatencyMs is double ms)
            {
                heroNumber = ((int)Math.Round(ms)).ToString();
                heroColor = TierColor(ms);
            }
            else
            {
                heroNumber = "--";
                heroColor = _pal.Muted;
            }
        }
        else if (timedOut)
        {
            headerDot = _pal.Red;
            pillBg = Tint(_pal.Red, 31);
            pillFg = _pal.RedLabel;
            pillDot = _pal.Red;
            pillBorder = Tint(_pal.Red, 71);
            pillText = "timeout";
            heroCaption = "timeout";
            heroNumber = "\u2717";
            heroColor = _pal.Red;
            heroHasUnit = false;
        }
        else if (resolving)
        {
            headerDot = _pal.Muted;
            pillBg = _pal.PillNeutralBg;
            pillFg = _pal.Footer;
            pillDot = _pal.Muted;
            pillBorder = Tint(_pal.Text, 31);
            pillText = "resolving";
            heroCaption = "resolving\u2026";
            heroNumber = "--";
            heroColor = _pal.Muted;
            heroHasUnit = false;
        }
        else
        {
            headerDot = _pal.Muted;
            pillBg = _pal.PillNeutralBg;
            pillFg = _pal.Footer;
            pillDot = _pal.Muted;
            pillBorder = Tint(_pal.Text, 31);
            pillText = "stopped";
            heroCaption = "not monitoring";
            heroNumber = "--";
            heroColor = _pal.Muted;
            heroHasUnit = false;
        }

        HeaderDot.Fill = Brush(headerDot);
        StatusPill.Background = Brush(pillBg);
        StatusPill.BorderBrush = Brush(pillBorder);
        StatusText.Foreground = Brush(pillFg);
        StatusDot.Fill = Brush(pillDot);
        StatusText.Text = pillText;
        HeroNumber.Text = heroNumber;
        HeroNumber.Foreground = Brush(heroColor);
        HeroCaption.Text = heroCaption;
        HeroUnit.Visibility = heroHasUnit ? Visibility.Visible : Visibility.Collapsed;

        UpdateHeaderDotPulse(connected);

        // Toggle
        if (running)
        {
            ToggleButton.Background = Brush(Tint(_pal.Red, 31));
            ToggleButton.BorderBrush = Brush(Tint(_pal.Red, 71));
            ToggleButton.Foreground = Brush(_pal.RedLabel);
            ToggleGlyph.Data = StopGlyph;
            ToggleLabel.Text = "stop monitoring";
        }
        else
        {
            ToggleButton.Background = Brush(Tint(_pal.Green, 31));
            ToggleButton.BorderBrush = Brush(Tint(_pal.Green, 71));
            ToggleButton.Foreground = Brush(_pal.Green);
            ToggleGlyph.Data = PlayGlyph;
            ToggleLabel.Text = "start monitoring";
        }
        ToggleButton.IsEnabled = running || !string.IsNullOrWhiteSpace(HostTextBox.Text);

        // Resolve note (always kept in layout so the popup doesn't jump)
        if (!string.IsNullOrEmpty(_pingManager.ResolvedIP))
        {
            ResolveNote.Text = "resolves to " + _pingManager.ResolvedIP;
            ResolveNote.Foreground = Brush(_pal.Muted2);
        }
        else if (resolving)
        {
            ResolveNote.Text = "resolving\u2026";
            ResolveNote.Foreground = Brush(_pal.Muted);
        }
        else
        {
            ResolveNote.Text = " ";
            ResolveNote.Foreground = Brush(_pal.Muted2);
        }

        // Stats
        var results = _pingManager.PingResults;
        if (results.Count == 0)
        {
            StatMinText.Text = "--";
            StatAvgText.Text = "--";
            StatMaxText.Text = "--";
        }
        else
        {
            StatMinText.Text = ((int)Math.Round(results.Min())).ToString();
            StatAvgText.Text = ((int)Math.Round(results.Average())).ToString();
            StatMaxText.Text = ((int)Math.Round(results.Max())).ToString();
        }
        StatMinText.Foreground = Brush(_pal.Text);
        StatAvgText.Foreground = Brush(_pal.Text);
        StatMaxText.Foreground = Brush(_pal.Text);

        UpdateChartColor(connected);
        UpdateGraph();
    }

    private Color TierColor(double ms)
    {
        if (ms < 60) return _pal.Green;
        if (ms <= 120) return _pal.Yellow;
        return _pal.Red;
    }

    private void UpdateHeaderDotPulse(bool pulse)
    {
        if (_headerDotPulsing == pulse) return;
        _headerDotPulsing = pulse;

        if (!pulse)
        {
            HeaderDot.BeginAnimation(OpacityProperty, null);
            HeaderDot.Opacity = 1;
            return;
        }

        var anim = new DoubleAnimation(1, 0.35, new Duration(TimeSpan.FromSeconds(1)))
        {
            AutoReverse = true,
            RepeatBehavior = RepeatBehavior.Forever,
        };
        HeaderDot.BeginAnimation(OpacityProperty, anim);
    }

    private void UpdateChartColor(bool connected)
    {
        _chartColor = connected && _pingManager.LatestLatencyMs is double ms
            ? TierColor(ms)
            : _pal.Muted;
    }

    private void UpdateGraph()
    {
        var results = _pingManager.PingResults;
        if (_chartAnimating) return;

        if (results.Count == 0)
        {
            _settledChart.Clear();
            ChartSlide.BeginAnimation(TranslateTransform.XProperty, null);
            DrawChart(_settledChart);
            return;
        }

        var arr = results.ToArray();
        if (arr.SequenceEqual(_settledChart)
            && _chartColor == _lastDrawnColor
            && ChartCanvas.ActualWidth == _lastDrawnWidth
            && ChartCanvas.ActualHeight == _lastDrawnHeight) return;

        var shiftedIn =
            _settledChart.Count == 30
            && arr.Length == 30
            && arr.Take(29).SequenceEqual(_settledChart.Skip(1));

        if (shiftedIn)
        {
            double stepX = ChartCanvas.ActualWidth / 29.0;
            if (stepX <= 0)
            {
                _settledChart = arr.ToList();
                DrawChart(_settledChart);
                return;
            }

            var extended = _settledChart.Concat(new[] { arr[^1] }).ToList();
            DrawChart(extended, stepX);
            _chartAnimating = true;

            var anim = new DoubleAnimation(0, -stepX, new Duration(TimeSpan.FromMilliseconds(550)))
            {
                EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut },
            };
            anim.Completed += (_, _) =>
            {
                _settledChart = arr.ToList();
                ChartSlide.BeginAnimation(TranslateTransform.XProperty, null);
                ChartSlide.X = 0;
                DrawChart(_settledChart);
                _chartAnimating = false;
            };
            ChartSlide.BeginAnimation(TranslateTransform.XProperty, anim);
        }
        else
        {
            _settledChart = arr.ToList();
            DrawChart(_settledChart);
        }
    }

    private Color _lastDrawnColor;
    private double _lastDrawnWidth;
    private double _lastDrawnHeight;

    private void DrawChart(IList<double> values, double? stepOverride = null)
    {
        ChartCanvas.Children.Clear();

        double width = ChartCanvas.ActualWidth;
        double height = ChartCanvas.ActualHeight;
        if (width <= 0 || height <= 0) return;

        _lastDrawnColor = _chartColor;
        _lastDrawnWidth = width;
        _lastDrawnHeight = height;
        var color = _chartColor;

        var axisMax = Math.Max(50, Math.Ceiling(values.DefaultIfEmpty(0).Max() / 50) * 50);
        AxisTopLabel.Text = ((int)axisMax).ToString();
        AxisMidLabel.Text = ((int)(axisMax / 2)).ToString();

        double topY = height * 2 / 54.0;
        double baselineY = height * 49 / 54.0;

        double YFor(double v)
        {
            double f = Math.Min(1, Math.Max(0, v / axisMax));
            return baselineY - f * (baselineY - topY);
        }

        var linePoints = new PointCollection();
        double step = stepOverride ?? (width / Math.Max(values.Count - 1, 1));
        for (int i = 0; i < values.Count; i++)
            linePoints.Add(new Point(i * step, YFor(values[i])));

        double lastX = linePoints.Count > 0 ? linePoints[^1].X : width;

        var areaPoints = new PointCollection(linePoints)
        {
            new Point(lastX, height),
            new Point(0, height),
        };

        var area = new Polygon
        {
            Points = areaPoints,
            Fill = Brush(Tint(color, 31)),
        };
        ChartCanvas.Children.Add(area);

        for (int i = 1; i < values.Count; i++)
        {
            var segment = new Line
            {
                X1 = (i - 1) * step,
                Y1 = YFor(values[i - 1]),
                X2 = i * step,
                Y2 = YFor(values[i]),
                Stroke = Brush(TierColor(Math.Max(values[i - 1], values[i]))),
                StrokeThickness = 2,
                StrokeStartLineCap = PenLineCap.Round,
                StrokeEndLineCap = PenLineCap.Round,
            };
            ChartCanvas.Children.Add(segment);
        }

        for (int i = 0; i < values.Count; i++)
        {
            var tierColor = TierColor(values[i]);
            if (tierColor != _pal.Green)
            {
                var marker = new Ellipse
                {
                    Width = 6,
                    Height = 6,
                    Fill = Brush(tierColor),
                    Stroke = Brush(_pal.Background),
                    StrokeThickness = 2,
                };
                double mx = i * step;
                Canvas.SetLeft(marker, mx - 3);
                Canvas.SetTop(marker, YFor(values[i]) - 3);
                ChartCanvas.Children.Add(marker);
            }
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
        for (int i = 0; i < IntervalOptions.Length; i++)
        {
            if (Math.Abs(IntervalOptions[i] - seconds) < 0.1)
            {
                IntervalCombo.SelectedIndex = i;
                return;
            }
        }
    }

    private void UpdatePinIcon()
    {
        var accent = _pal.Accent;
        PinIcon.Stroke = Brushes.Transparent;
        PinIcon.StrokeThickness = 0;
        if (_isPinned)
        {
            PinButton.Background = Brush(accent);
            PinButton.BorderBrush = Brush(accent);
            PinIcon.Fill = Brush(_pal.Background);
            PinIconRotate.Angle = 0;
        }
        else
        {
            PinButton.Background = Brush(Tint(accent, 31));
            PinButton.BorderBrush = Brush(Tint(accent, 71));
            PinIcon.Fill = Brush(accent);
            PinIconRotate.Angle = 35;
        }
        PinButton.ToolTip = _isPinned
            ? "Unpin \u2014 close when clicking outside"
            : "Pin \u2014 keep open when clicking outside";
    }

    private void OnPinToggle(object sender, RoutedEventArgs e)
    {
        _isPinned = !_isPinned;
        UpdatePinIcon();
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

    private void OnQuit(object sender, RoutedEventArgs e)
    {
        FooterRow.Visibility = Visibility.Collapsed;
        QuitConfirmRow.Visibility = Visibility.Visible;
        QuitCancelBtn.Focus();
    }

    private void OnQuitCancel(object sender, RoutedEventArgs e)
    {
        HideQuitConfirm();
    }

    private void HideQuitConfirm()
    {
        QuitConfirmRow.Visibility = Visibility.Collapsed;
        FooterRow.Visibility = Visibility.Visible;
    }

    private void OnQuitConfirm(object sender, RoutedEventArgs e)
    {
        System.Windows.Application.Current.Shutdown();
    }

    private void OnDeactivated(object sender, EventArgs e)
    {
        if (!_isPinned && !_suppressClose && IsVisible)
        {
            HideQuitConfirm();
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
        AnimateLoginToggle();
    }

    private void AnimateLoginToggle()
    {
        if (LoginCheckBox.Template?.FindName("KnobTranslate", LoginCheckBox) is not TranslateTransform knob)
            return;
        knob.BeginAnimation(TranslateTransform.XProperty, null);
        var anim = new DoubleAnimation(LoginCheckBox.IsChecked == true ? 12 : 0,
            new Duration(TimeSpan.FromMilliseconds(150)))
        {
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut },
        };
        knob.BeginAnimation(TranslateTransform.XProperty, anim);
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

    protected override void OnClosed(EventArgs e)
    {
        SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
        _pingManager.StateChanged -= OnPingStateChanged;
        _trayManager.TrayIconClicked -= OnTrayIconClicked;
        base.OnClosed(e);
    }
}