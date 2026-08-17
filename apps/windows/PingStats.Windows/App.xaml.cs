using System;
using System.Windows;

namespace PingStats;

public partial class App : System.Windows.Application
{
    private PingManager? _pingManager;
    private TrayManager? _trayManager;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        _pingManager = new PingManager();
        _trayManager = new TrayManager(_pingManager);
        var _ = new PopupWindow(_pingManager, _trayManager);

        _pingManager.StartPinging();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _pingManager?.StopPinging();
        _pingManager?.Dispose();
        _trayManager?.Dispose();
        base.OnExit(e);
    }
}
