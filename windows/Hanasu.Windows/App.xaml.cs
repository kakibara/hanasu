using System.IO;
using System.Text;
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
    static App() => DllSearch.Harden();

    protected override void OnStartup(StartupEventArgs e)
    {
        // 要件: REQ-COM-060
        // 表示の言語を、ウインドウ・メニュー・知らせを作る前に決める（Windows の表示の言語が 17 言語のどれでもなければ英語）
        var culture = UiLanguage.Apply();
        // 文字の言語（xml:lang）も表示の言語にする（中国語などで、その言語の字形とフォントの代替が選ばれるように）
        FrameworkElement.LanguageProperty.OverrideMetadata(typeof(FrameworkElement),
            new FrameworkPropertyMetadata(System.Windows.Markup.XmlLanguage.GetLanguage(culture.IetfLanguageTag)));
        if (culture.TextInfo.IsRightToLeft)
        {
            // アラビア語などは、ウインドウを右から左に並べる。ウインドウを作る前に既定値を変え、表示してから並びが変わらないようにする
            FrameworkElement.FlowDirectionProperty.OverrideMetadata(typeof(Window),
                new FrameworkPropertyMetadata(FlowDirection.RightToLeft, FrameworkPropertyMetadataOptions.AffectsArrange | FrameworkPropertyMetadataOptions.Inherits));
        }
        base.OnStartup(e);
        // 確かめ方: REQ-DIC-075
        // 設計判断: DEC-DIC-237（--dump-screen-text は UI を出さず、ほかの Hanasu が動いていても読んで終わる）
        if (e.Args.Length >= 1 && e.Args[0] == "--dump-screen-text")
        {
            DumpScreenText(e.Args.Length >= 2 ? e.Args[1] : null);
            return;
        }
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

    // 確かめ方: REQ-DIC-075
    // 設計判断: DEC-DIC-237
    /// <summary>
    /// --dump-screen-text &lt;出力ファイル&gt;: アプリと同じ撮り方・除外・OCR で画面を読み、1 行目に
    /// <c># displays=N language=&lt;使った OCR の言語&gt; fallback=&lt;true|false&gt;</c>、そのあとに読んだ行を 1 行ずつ UTF-8 で書いて終わる。
    /// 終了コードは、書けたら 0、撮れない・読めないときは 1（理由を <c># error=…</c> の行に書く）、引数がないときは 2
    /// </summary>
    private async void DumpScreenText(string? output)
    {
        if (string.IsNullOrWhiteSpace(output))
        {
            Shutdown(2);
            return;
        }
        var utf8 = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false);
        try
        {
            var settings = new SettingsStore().Load();
            ScreenTextResult result;
            using (var capture = ScreenTextReader.CaptureAll())
            {
                result = await Task.Run(() => ScreenTextReader.RecognizeAsync(capture, settings.LocaleIdentifier, CancellationToken.None));
            }
            var text = new StringBuilder();
            text.Append($"# displays={result.Displays} language={result.LanguageTag} fallback={(result.Fallback ? "true" : "false")}\n");
            foreach (var line in result.Lines) text.Append(line.Text).Append('\n');
            File.WriteAllText(output, text.ToString(), utf8);
            Shutdown(0);
        }
        catch (Exception ex)
        {
            AppLog.Write($"dump screen text failed: {ex.GetType().Name}: {ex.Message}");
            try { File.WriteAllText(output, $"# error={ex.GetType().Name}: {ex.Message}\n", utf8); } catch (Exception) { }
            Shutdown(1);
        }
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
