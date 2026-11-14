using System.Diagnostics;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using Hanasu.Core.Ai;
using Hanasu.Core.Settings;
using Hanasu.Core.Text;
using Hanasu.Windows.Services;

namespace Hanasu.Windows.Views;

// 要件: REQ-DIC-075
// 設計判断: DEC-DIC-231, DEC-DIC-232
/// <summary>
/// 画面から辞書の候補を探すウインドウ（Mac 版の ScreenDictionaryWindow・ScreenDictionaryView にあたる）。
/// メニューから開くので親を持たず、タスクバーに出す（裏に回っても戻せるように）。同時に 1 つだけ（AppHost.ShowScreenDictionary）。
/// 状態: 読んでいる → 読んだ（送る材料と「候補を探す」）→ 探している → 候補 / 0 件 / エラー → 追加した（2 秒ほどで閉じる）。
/// 「候補を探す」を押すまで何も AI に送らない。閉じると OCR と AI の呼び出しを止め、辞書を変えない。
/// 読んだ文字はこのウインドウを閉じるまでメモリの上だけに置き、ログには数と時間だけを出す。
/// </summary>
internal sealed class ScreenDictionaryWindow : Window
{
    private readonly AppHost host;
    private readonly CancellationTokenSource cancellation = new();
    private readonly ContentControl body = new() { Margin = new Thickness(0, 10, 0, 10) };
    private readonly StackPanel buttons = new() { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 12, 0, 0) };
    private readonly List<CandidateRow> rows = new();
    private Button? addButton;
    private bool closed;
    /// <summary>撮った画面の数</summary>
    private int displays;
    /// <summary>読んだ結果（OCR の言語に落ちたかを見せるため）</summary>
    private ScreenTextResult? ocr;
    /// <summary>見せて、送る材料（見せたものと送るものは同じ。DEC-DIC-231）</summary>
    private DictionarySuggester.ScreenMaterial? material;

    /// <summary>候補 1 つの行。候補のチェックと、読みごとのチェック</summary>
    private sealed record CandidateRow(DictionaryCandidate Candidate, CheckBox Box, IReadOnlyList<(CheckBox Box, string Reading)> Readings);

    public ScreenDictionaryWindow(AppHost host)
    {
        this.host = host;
        Title = Strings.ScreenDictionary_WindowTitle;
        Width = 600;
        Height = 640;
        MinWidth = 460;
        MinHeight = 420;
        // 設計判断: DEC-DIC-232（親がないので、タスクバーに出す）
        ShowInTaskbar = true;
        WindowFit.FitToMouseScreen(this);

        var root = new DockPanel { Margin = new Thickness(16) };
        var heading = new TextBlock { Text = Strings.ScreenDictionary_Title, FontSize = 16, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap };
        DockPanel.SetDock(heading, Dock.Top);
        root.Children.Add(heading);
        var footer = new StackPanel();
        footer.Children.Add(new Separator());
        // 写さないもの・写るもの・送り先（REQ-DIC-075 の受け入れ条件 8・11）
        footer.Children.Add(new TextBlock
        {
            Text = Strings.ScreenDictionary_Note,
            TextWrapping = TextWrapping.Wrap,
            Foreground = SystemColors.GrayTextBrush,
            FontSize = 11,
            Margin = new Thickness(0, 6, 0, 0),
        });
        footer.Children.Add(buttons);
        DockPanel.SetDock(footer, Dock.Bottom);
        root.Children.Add(footer);
        root.Children.Add(body);
        Content = root;

        ShowReading();
        // 閉じたら OCR と AI の呼び出しを止める（辞書は変えない）
        Closed += (_, _) =>
        {
            closed = true;
            cancellation.Cancel();
        };
    }

    // MARK: - 読む

    // 要件: REQ-DIC-075
    // 設計判断: DEC-DIC-231, DEC-DIC-234
    /// <summary>撮った画面を読み、送る材料を作って見せる。capture は読み終えたら（止めたときも）捨てる</summary>
    public async void Read(ScreenCapture capture)
    {
        ShowReading();
        var settings = host.Settings.Current;
        var token = cancellation.Token;
        var started = Stopwatch.StartNew();
        ScreenTextResult result;
        try
        {
            using (capture)
            {
                displays = capture.Screens.Count;
                // OCR を読み終えてから（止めたときも、走っている 1 枚を読み終えてから）画像を捨てる
                result = await Task.Run(() => ScreenTextReader.RecognizeAsync(capture, settings.LocaleIdentifier, token), token);
            }
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested)
        {
            return;
        }
        catch (ScreenTextException e)
        {
            ShowFailure(e.Message);
            return;
        }
        catch (Exception e)
        {
            AppLog.Write($"screen dictionary: read failed ({e.GetType().Name})");
            ShowFailure(string.Format(Strings.ScreenDictionary_ReadFailed, e.Message));
            return;
        }
        if (token.IsCancellationRequested) return;
        ocr = result;

        var existing = settings.UserDictionary;
        // 上限は送り先の AI で決める。AI が使えなければ（鍵がないなど）Gemini・Claude の上限で作り、探すときに理由を出す
        var client = TryCreateClient(settings, out _);
        var budget = client is null
            ? new DictionarySuggester.Budget(false, DictionarySuggester.CharacterLimit)
            : DictionarySuggester.BudgetFor(client, existing, DictionarySuggester.ScreenInstruction);
        var made = DictionarySuggester.ScreenMaterialFor(result.Lines, budget);
        // 要件: REQ-DIC-075（ログには数だけ。読んだ文字は出さない）
        AppLog.Write($"screen dictionary: {result.Displays} displays, {result.Lines.Count} lines -> terms={made.Terms.Count} lines={made.Lines.Count} chars={made.Text.Length} truncated={made.Truncated}, {started.Elapsed.TotalSeconds:F2}s");
        if (made.IsEmpty)
        {
            ShowFailure(Strings.ScreenDictionary_NoText);
            return;
        }
        material = made;
        ShowReady(made);
    }

    /// <summary>撮れなかったときなど、読む前に理由を出す</summary>
    public void ShowFailure(string message)
    {
        body.Content = Warning(message);
        SetButtons(CloseButton());
    }

    // MARK: - 探す

    // 要件: REQ-DIC-075
    // 設計判断: DEC-DIC-232
    /// <summary>「候補を探す」を押したときだけ、見せた材料を会議（議事録）の AI に送る。ローカルのモデルがなくても、ダウンロードは尋ねない</summary>
    private async void Search()
    {
        if (material is not { } sending) return;
        var settings = host.Settings.Current;
        var client = TryCreateClient(settings, out var reason);
        if (client is null)
        {
            ShowFailure(reason);
            return;
        }
        ShowSearching(sending);
        var token = cancellation.Token;
        var started = Stopwatch.StartNew();
        try
        {
            var found = await DictionarySuggester.SuggestFromScreenAsync(sending, settings.UserDictionary, client, settings.MinutesModel, token);
            if (token.IsCancellationRequested) return;
            AppLog.Write($"screen dictionary: sent, {found.Count} candidates, {started.Elapsed.TotalSeconds:F2}s");
            ShowResults(found, settings.MinutesModel);
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested)
        {
            // 閉じたので何もしない
        }
        catch (Exception e)
        {
            // どんな失敗でも「探しています…」のまま止めず、理由を出す（辞書は変えない）
            AppLog.Write($"screen dictionary: search failed ({e.GetType().Name}), {started.Elapsed.TotalSeconds:F2}s");
            ShowFailure(e.Message);
        }
    }

    /// <summary>会議（議事録）の AI のクライアント（DEC-COM-040）。使えなければ null と理由</summary>
    private ITextAiClient? TryCreateClient(AppSettings settings, out string reason)
    {
        reason = TextAiFactory.MissingCredentialsMessage(settings.MeetingAi);
        try
        {
            return host.CreateTextAi(settings, TextAiUse.Meeting);
        }
        catch (Exception e)
        {
            // サービスアカウントの鍵が読めないときなど
            reason = e.Message;
            return null;
        }
    }

    // MARK: - 追加する

    // 設計判断: DEC-DIC-087, DEC-DIC-231
    /// <summary>チェックした候補を、チェックした読みだけを付けて辞書の末尾に足し、知らせを出してから閉じる</summary>
    private async void Add()
    {
        var chosen = rows.Where(r => r.Box.IsChecked == true)
            .Select(r => r.Candidate with { Readings = r.Readings.Where(x => x.Box.IsChecked == true).Select(x => x.Reading).ToList() })
            .ToList();
        if (chosen.Count == 0) return;
        chosen = DictionarySuggester.DroppingRegistered(chosen, host.Settings.Current.UserDictionary);
        cancellation.Cancel();
        var error = host.Settings.Update(s => s.DictionaryText = DictionarySuggester.Appending(chosen, s.DictionaryText));
        if (error is not null)
        {
            ShowFailure(string.Format(Strings.Meeting_SaveFailed, error.Message));
            return;
        }
        body.Content = new TextBlock { Text = "✓ " + string.Format(Strings.Meeting_Dictionary_Added, chosen.Count), TextWrapping = TextWrapping.Wrap };
        SetButtons(CloseButton());
        await Task.Delay(TimeSpan.FromSeconds(2));
        if (!closed) Close();
    }

    // MARK: - 状態ごとの画面

    private void ShowReading()
    {
        body.Content = new TextBlock { Text = Strings.ScreenDictionary_Reading, TextWrapping = TextWrapping.Wrap };
        SetButtons(CancelButton());
    }

    private void ShowReady(DictionarySuggester.ScreenMaterial sending)
    {
        body.Content = MaterialView(sending, searching: false);
        var search = new Button { Content = Strings.ScreenDictionary_Search, Padding = new Thickness(12, 4, 12, 4), Margin = new Thickness(8, 0, 0, 0), IsDefault = true };
        search.Click += (_, _) => Search();
        SetButtons(CancelButton(), search);
        search.Focus();
    }

    private void ShowSearching(DictionarySuggester.ScreenMaterial sending)
    {
        var panel = new DockPanel();
        var searching = new TextBlock { Text = Strings.Meeting_Dictionary_Searching, Margin = new Thickness(0, 0, 0, 8) };
        DockPanel.SetDock(searching, Dock.Top);
        panel.Children.Add(searching);
        panel.Children.Add(MaterialView(sending, searching: true));
        body.Content = panel;
        SetButtons(CancelButton());
    }

    // 設計判断: DEC-DIC-231
    /// <summary>送る材料（「語」と「画面の行」の 2 つの欄）と、画面・語・行の数、送り先、知らせ</summary>
    private FrameworkElement MaterialView(DictionarySuggester.ScreenMaterial sending, bool searching)
    {
        var settings = host.Settings.Current;
        var info = new StackPanel();
        info.Children.Add(new TextBlock
        {
            Text = string.Format(Strings.ScreenDictionary_Summary, displays, sending.Terms.Count, sending.Lines.Count),
            TextWrapping = TextWrapping.Wrap,
        });
        info.Children.Add(Caption(string.Format(Strings.ScreenDictionary_Destination, Destination(settings))));
        if (settings.MeetingAi == TextAiProvider.Local) info.Children.Add(Caption(Strings.ScreenDictionary_LocalNote));
        if (sending.Truncated) info.Children.Add(Caption("✂ " + Strings.ScreenDictionary_Truncated, Brushes.DarkOrange));
        // 文字起こしの言語の OCR がなく、ほかの言語で読んだ（REQ-DIC-075 の受け入れ条件 10）
        if (ocr is { Fallback: true } read)
        {
            info.Children.Add(Caption("⚠️ " + string.Format(Strings.ScreenDictionary_OcrFallback, read.WantedLanguageName, read.LanguageName), Brushes.DarkOrange));
        }

        var boxes = new Grid { Margin = new Thickness(0, 8, 0, 0) };
        boxes.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        boxes.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        var terms = MaterialBox(Strings.ScreenDictionary_Terms, string.Join(", ", sending.Terms));
        var lines = MaterialBox(Strings.ScreenDictionary_Lines, string.Join("\n", sending.Lines));
        lines.Margin = new Thickness(0, 8, 0, 0);
        Grid.SetRow(terms, 0);
        Grid.SetRow(lines, 1);
        boxes.Children.Add(terms);
        boxes.Children.Add(lines);

        var panel = new DockPanel { Opacity = searching ? 0.6 : 1 };
        DockPanel.SetDock(info, Dock.Top);
        panel.Children.Add(info);
        panel.Children.Add(boxes);
        return panel;
    }

    /// <summary>読むだけの、スクロールできる欄</summary>
    private FrameworkElement MaterialBox(string title, string text)
    {
        var panel = new DockPanel();
        var label = new TextBlock { Text = title, FontWeight = FontWeights.SemiBold, FontSize = 11, Margin = new Thickness(0, 0, 0, 2) };
        DockPanel.SetDock(label, Dock.Top);
        panel.Children.Add(label);
        var box = new TextBox
        {
            Text = text.Length == 0 ? Strings.ScreenDictionary_None : text,
            IsReadOnly = true,
            TextWrapping = TextWrapping.Wrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            MinHeight = 80,
            Padding = new Thickness(4),
        };
        if (TryFindResource("ReadOnlyOutput") is Style style) box.Style = style;
        AutomationProperties.SetName(box, title);
        panel.Children.Add(box);
        return panel;
    }

    /// <summary>送り先の名前（設定の「AI」の「議事録」の AI とモデル）</summary>
    private static string Destination(AppSettings settings)
    {
        var model = settings.MeetingAi == TextAiProvider.Local
            ? TextAiFactory.LocalModelFor(settings, TextAiUse.Meeting).Name
            : settings.MinutesModel;
        var name = TextAiFactory.NameOf(settings.MeetingAi);
        return string.IsNullOrEmpty(model) ? name : string.Format(Strings.ScreenDictionary_DestinationModel, name, model);
    }

    // 設計判断: DEC-DIC-231
    /// <summary>
    /// 候補を、表記と理由と、読みごとのチェックで並べる。既定はどれもチェックしない。候補をチェックすると読みもすべてチェックされ、
    /// 読みは 1 つずつ外せる。候補をチェックしていなければ、読みは押せない
    /// </summary>
    private void ShowResults(IReadOnlyList<DictionaryCandidate> found, string model)
    {
        rows.Clear();
        if (found.Count == 0)
        {
            body.Content = new TextBlock { Text = Strings.Meeting_Dictionary_NoCandidates, Foreground = SystemColors.GrayTextBrush, TextWrapping = TextWrapping.Wrap };
            SetButtons(CloseButton());
            return;
        }
        var list = new StackPanel();
        foreach (var candidate in found)
        {
            var content = new StackPanel();
            content.Children.Add(new TextBlock { Text = candidate.Spelling, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
            if (candidate.Reason.Length > 0)
            {
                content.Children.Add(new TextBlock { Text = candidate.Reason, TextWrapping = TextWrapping.Wrap, Foreground = SystemColors.GrayTextBrush, FontSize = 11 });
            }
            var box = new CheckBox { Content = content, Margin = new Thickness(0, 6, 0, 2) };
            AutomationProperties.SetName(box, candidate.Spelling);
            var readings = new List<(CheckBox, string)>();
            var readingPanel = new WrapPanel { Margin = new Thickness(20, 0, 0, 4) };
            if (candidate.Readings.Count == 0)
            {
                readingPanel.Children.Add(new TextBlock { Text = Strings.ScreenDictionary_NoReading, Foreground = SystemColors.GrayTextBrush, FontSize = 11 });
            }
            else
            {
                readingPanel.Children.Add(new TextBlock
                {
                    Text = Strings.ScreenDictionary_ReadingLabel,
                    Foreground = SystemColors.GrayTextBrush,
                    FontSize = 11,
                    VerticalAlignment = VerticalAlignment.Center,
                    Margin = new Thickness(0, 0, 8, 0),
                });
                foreach (var reading in candidate.Readings)
                {
                    var readingBox = new CheckBox { Content = reading, FontSize = 11, IsEnabled = false, Margin = new Thickness(0, 2, 12, 2) };
                    AutomationProperties.SetName(readingBox, $"{candidate.Spelling} {Strings.ScreenDictionary_ReadingLabel} {reading}");
                    readings.Add((readingBox, reading));
                    readingPanel.Children.Add(readingBox);
                }
            }
            box.Checked += (_, _) => SetReadings(readings, true);
            box.Unchecked += (_, _) => SetReadings(readings, false);
            rows.Add(new CandidateRow(candidate, box, readings));
            list.Children.Add(box);
            list.Children.Add(readingPanel);
        }
        var scroll = new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Margin = new Thickness(0, 6, 0, 0) };
        AutomationProperties.SetName(scroll, Strings.Meeting_Dictionary_ListName);
        var panel = new DockPanel();
        var choose = Caption(string.IsNullOrEmpty(model) ? Strings.ScreenDictionary_Choose : string.Format(Strings.Meeting_Dictionary_Choose, model));
        DockPanel.SetDock(choose, Dock.Top);
        panel.Children.Add(choose);
        panel.Children.Add(scroll);
        body.Content = panel;

        addButton = new Button { Padding = new Thickness(12, 4, 12, 4), Margin = new Thickness(8, 0, 0, 0), IsDefault = true };
        addButton.Click += (_, _) => Add();
        SetButtons(CancelButton(), addButton);
        UpdateAddButton();
    }

    /// <summary>候補をチェックすると読みもすべてチェックし、外すと読みも外して押せなくする</summary>
    private void SetReadings(IReadOnlyList<(CheckBox Box, string Reading)> readings, bool on)
    {
        foreach (var (box, _) in readings)
        {
            box.IsChecked = on;
            box.IsEnabled = on;
        }
        UpdateAddButton();
    }

    private void UpdateAddButton()
    {
        if (addButton is null) return;
        var count = rows.Count(r => r.Box.IsChecked == true);
        addButton.Content = string.Format(Strings.Meeting_Dictionary_Add, count);
        addButton.IsEnabled = count > 0;
    }

    // MARK: - 部品

    private void SetButtons(params Button[] items)
    {
        buttons.Children.Clear();
        foreach (var item in items) buttons.Children.Add(item);
    }

    /// <summary>「キャンセル」。閉じると OCR と AI の呼び出しを止める（Esc でも押せる）</summary>
    private Button CancelButton()
    {
        var button = new Button { Content = Strings.Meeting_Dictionary_Cancel, Padding = new Thickness(12, 4, 12, 4), IsCancel = true };
        button.Click += (_, _) => Close();
        return button;
    }

    private Button CloseButton()
    {
        var button = new Button { Content = Strings.Close, Padding = new Thickness(12, 4, 12, 4), IsDefault = true, IsCancel = true };
        button.Click += (_, _) => Close();
        return button;
    }

    private static TextBlock Caption(string text, Brush? color = null) => new()
    {
        Text = text,
        TextWrapping = TextWrapping.Wrap,
        FontSize = 11,
        Foreground = color ?? SystemColors.GrayTextBrush,
        Margin = new Thickness(0, 4, 0, 0),
    };

    private static TextBlock Warning(string message) => new()
    {
        Text = "⚠️ " + message,
        TextWrapping = TextWrapping.Wrap,
        Foreground = Brushes.DarkOrange,
    };
}
