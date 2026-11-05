using System.Threading;
using System.Windows;
using System.Windows.Threading;
using Hanasu.Core.Settings;
using Hanasu.Windows.Services;

namespace Hanasu.Windows;

/// <summary>タスクトレイに常駐するアプリ。ウインドウは設定画面と HUD だけ。</summary>
public partial class App : Application
{
    private Mutex? singleInstance;
    private AppHost? host;

    // WPF のネイティブ DLL などを読み込む前に、DLL を探す場所を絞る（DEC-COM-148）
    static App() => WindowsSecurity.HardenDllSearch();

    protected override void OnStartup(StartupEventArgs e)
    {
        // 要件: REQ-COM-060
        // 表示の言語を、ウインドウ・メニュー・知らせを作る前に決める（Windows の表示の言語が 17 言語のどれでもなければ英語）
        var culture = UiLanguage.Apply();
        if (culture.TextInfo.IsRightToLeft)
        {
            // アラビア語などは、ウインドウを右から左に並べる
            EventManager.RegisterClassHandler(typeof(Window), FrameworkElement.LoadedEvent,
                new RoutedEventHandler((sender, _) => ((Window)sender).FlowDirection = FlowDirection.RightToLeft));
        }
        base.OnStartup(e);
        // 2 つ目を起動したら、知らせて終わる（ホットキーを取り合わないため）
        singleInstance = new Mutex(initiallyOwned: true, @"Local\Hanasu.Windows.SingleInstance", out var createdNew);
        if (!createdNew)
        {
            MessageBox.Show(Strings.App_AlreadyRunning, "Hanasu", MessageBoxButton.OK, MessageBoxImage.Information);
            Shutdown();
            return;
        }

        DispatcherUnhandledException += OnUnhandledException;
        AppDomain.CurrentDomain.UnhandledException += (_, args) => AppLog.Write($"unhandled: {args.ExceptionObject}");
        TaskScheduler.UnobservedTaskException += (_, args) =>
        {
            AppLog.Write($"unobserved: {args.Exception}");
            args.SetObserved();
        };

        host = new AppHost(this);
        host.Start();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        host?.Dispose();
        singleInstance?.Dispose();
        base.OnExit(e);
    }

    private void OnUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        // 常駐アプリなので、思わぬ例外でも落とさずに記録して続ける
        AppLog.Write($"dispatcher unhandled: {e.Exception}");
        e.Handled = true;
    }
}
