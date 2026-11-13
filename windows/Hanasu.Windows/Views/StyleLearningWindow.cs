using System.IO;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using Hanasu.Core.Ai;
using Hanasu.Core.Dictation;
using Hanasu.Core.Text;
using Microsoft.Win32;

namespace Hanasu.Windows.Views;

// 要件: REQ-DIC-022
// 設計判断: DEC-DIC-210, DEC-DIC-211, DEC-DIC-212, DEC-DIC-213, DEC-DIC-215
/// <summary>
/// 文章から文体を学ぶダイアログ（Mac 版の StyleLearningSheet にあたる）。上から、入力欄（貼り付け）と「ファイルを選ぶ…」・字数、
/// 「文体を学ぶ」（学んでいる間は進み具合と「やめる」）、名前・言語・ルールの欄（学んだあとに出す）、「保存」「キャンセル」。
/// editing を渡すと「編集…」として、名前・言語・ルールの欄だけを出す。入力した文章は保存しない（閉じると消える）。
/// 閉じたら AI の呼び出しを取り消す。失敗しても入力欄は残す。保存したら Saved に入れて閉じる
/// </summary>
internal sealed class StyleLearningWindow : Window
{
    private readonly AppHost host;
    private readonly CustomStyle? editing;
    private CancellationTokenSource? cancellation;
    private DictionarySuggester.Budget budget = new(false, StyleLearner.CharacterLimit);
    private readonly DispatcherTimer countTimer = new() { Interval = TimeSpan.FromMilliseconds(250) };
    private bool trimming;

    private readonly TextBox input = new()
    {
        AcceptsReturn = true,
        AcceptsTab = true,
        TextWrapping = TextWrapping.Wrap,
        VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
        Height = 180,
        Padding = new Thickness(4, 3, 4, 3),
    };
    private readonly TextBlock countText = new() { VerticalAlignment = VerticalAlignment.Center, Foreground = SystemColors.GrayTextBrush, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(8, 0, 0, 0) };
    private readonly TextBlock inputNote = Note(error: true);
    private readonly Button learnButton = new() { Content = Strings.StyleLearning_Learn, Padding = new Thickness(12, 4, 12, 4) };
    private readonly Button stopButton = new() { Content = Strings.StyleLearning_Stop, Padding = new Thickness(12, 4, 12, 4), Margin = new Thickness(8, 0, 0, 0), Visibility = Visibility.Collapsed };
    private readonly ProgressBar progress = new() { IsIndeterminate = true, Width = 120, Height = 6, Margin = new Thickness(10, 0, 0, 0), Visibility = Visibility.Collapsed, VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock learnStatus = Note(error: false);
    private readonly TextBlock needMore = Note(error: false);

    private readonly StackPanel resultPanel = new() { Margin = new Thickness(0, 12, 0, 0) };
    private readonly TextBox nameBox = new() { Padding = new Thickness(4, 3, 4, 3) };
    private readonly ComboBox languageCombo = new() { MinWidth = 200, HorizontalAlignment = HorizontalAlignment.Left };
    private readonly TextBox rulesBox = new()
    {
        AcceptsReturn = true,
        TextWrapping = TextWrapping.Wrap,
        VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
        Height = 200,
        Padding = new Thickness(4, 3, 4, 3),
    };
    private readonly TextBlock rulesCount = Note(error: false);
    private readonly TextBlock saveError = Note(error: true);
    private readonly Button saveButton = new() { Content = Strings.StyleLearning_Save, Padding = new Thickness(12, 4, 12, 4), Margin = new Thickness(8, 0, 0, 0), IsDefault = true };

    /// <summary>保存したカスタム文体（保存せずに閉じたら null）</summary>
    public CustomStyle? Saved { get; private set; }

    public StyleLearningWindow(AppHost host, CustomStyle? editing = null)
    {
        this.host = host;
        this.editing = editing;
        Title = editing is null ? Strings.StyleLearning_Title : Strings.StyleLearning_EditTitle;
        SizeToContent = SizeToContent.Height;
        Width = 620;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ShowInTaskbar = false;
        FontFamily = new FontFamily("Yu Gothic UI, Meiryo UI, Segoe UI");
        FontSize = 13;

        var panel = new StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(new TextBlock { Text = Title, FontSize = 16, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
        if (editing is null) panel.Children.Add(BuildLearnPanel());
        BuildResultPanel();
        resultPanel.Visibility = editing is null ? Visibility.Collapsed : Visibility.Visible;
        panel.Children.Add(resultPanel);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0) };
        buttons.Children.Add(new Button { Content = Strings.StyleLearning_Cancel, Padding = new Thickness(12, 4, 12, 4), IsCancel = true });
        saveButton.Click += (_, _) => Save();
        buttons.Children.Add(saveButton);
        panel.Children.Add(buttons);
        Content = new ScrollViewer { Content = panel, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        MaxHeight = SystemParameters.WorkArea.Height - 40;

        if (editing is not null)
        {
            nameBox.Text = editing.Name;
            languageCombo.SelectedItem = editing.PromptLanguage;
            rulesBox.Text = CustomStyleRules.ToText(editing.Rules);
        }
        else
        {
            saveButton.IsEnabled = false;
            Loaded += (_, _) => input.Focus();
        }
        UpdateRulesCount();
        // 閉じたら AI への要求を取り消す（REQ-DIC-022）
        Closed += (_, _) =>
        {
            cancellation?.Cancel();
            countTimer.Stop();
        };
    }

    private static TextBlock Note(bool error) => new()
    {
        TextWrapping = TextWrapping.Wrap,
        FontSize = 12,
        Margin = new Thickness(0, 4, 0, 0),
        Foreground = error ? new SolidColorBrush(Color.FromRgb(0xC5, 0x22, 0x1F)) : SystemColors.GrayTextBrush,
        Visibility = Visibility.Collapsed,
    };

    private static void Show(TextBlock block, string? text)
    {
        block.Text = text ?? "";
        block.Visibility = string.IsNullOrEmpty(text) ? Visibility.Collapsed : Visibility.Visible;
    }

    private StackPanel BuildLearnPanel()
    {
        var learn = new StackPanel();
        learn.Children.Add(new TextBlock { Text = Strings.StyleLearning_Intro, TextWrapping = TextWrapping.Wrap, Foreground = SystemColors.GrayTextBrush, FontSize = 12, Margin = new Thickness(0, 6, 0, 8) });
        AutomationProperties.SetName(input, Strings.StyleLearning_Input_A11y);
        input.TextChanged += (_, _) => OnInputChanged();
        learn.Children.Add(input);

        var fileRow = new DockPanel { Margin = new Thickness(0, 6, 0, 0) };
        var choose = new Button { Content = Strings.StyleLearning_ChooseFiles, Padding = new Thickness(12, 4, 12, 4) };
        choose.Click += (_, _) => ChooseFiles();
        DockPanel.SetDock(choose, Dock.Left);
        fileRow.Children.Add(choose);
        fileRow.Children.Add(countText);
        learn.Children.Add(fileRow);
        learn.Children.Add(inputNote);

        var learnRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 10, 0, 0) };
        learnButton.Click += async (_, _) => await LearnAsync();
        stopButton.Click += (_, _) => cancellation?.Cancel();
        learnRow.Children.Add(learnButton);
        learnRow.Children.Add(progress);
        learnRow.Children.Add(stopButton);
        learn.Children.Add(learnRow);
        learn.Children.Add(needMore);
        learn.Children.Add(learnStatus);

        // 送る上限は「議事録」の AI で決まる（ローカルは文脈の長さから。DEC-DIC-212）。AI がまだ使えなくても、字数は Gemini・Claude の上限で出す
        try
        {
            if (host.CreateTextAi(host.Settings.Current, TextAiUse.Meeting, StyleLearner.Timeout) is { } client) budget = StyleLearner.Budget(client);
        }
        catch (Exception)
        {
            // サービスアカウントが読めないなどは、「文体を学ぶ」を押したときに理由を出す
        }
        countTimer.Tick += (_, _) =>
        {
            countTimer.Stop();
            UpdateCount();
        };
        UpdateCount();
        return learn;
    }

    private void BuildResultPanel()
    {
        resultPanel.Children.Add(new TextBlock { Text = Strings.StyleLearning_Name, Margin = new Thickness(0, 0, 0, 2) });
        AutomationProperties.SetName(nameBox, Strings.StyleLearning_Name);
        resultPanel.Children.Add(nameBox);

        resultPanel.Children.Add(new TextBlock { Text = Strings.StyleLearning_Language, Margin = new Thickness(0, 10, 0, 2) });
        AutomationProperties.SetName(languageCombo, Strings.StyleLearning_Language);
        // 17 言語。名前はその言語で書いた言語名（HUD の切り替えと同じ）
        languageCombo.ItemsSource = PromptLanguage.All;
        languageCombo.ItemTemplate = LanguageTemplate();
        resultPanel.Children.Add(languageCombo);
        resultPanel.Children.Add(new TextBlock { Text = Strings.StyleLearning_LanguageNote, TextWrapping = TextWrapping.Wrap, Foreground = SystemColors.GrayTextBrush, FontSize = 12, Margin = new Thickness(0, 3, 0, 0) });

        resultPanel.Children.Add(new TextBlock { Text = Strings.StyleLearning_Rules, Margin = new Thickness(0, 10, 0, 2) });
        AutomationProperties.SetName(rulesBox, Strings.StyleLearning_Rules);
        rulesBox.TextChanged += (_, _) => UpdateRulesCount();
        resultPanel.Children.Add(rulesBox);
        rulesCount.Visibility = Visibility.Visible;
        resultPanel.Children.Add(rulesCount);
        resultPanel.Children.Add(saveError);
    }

    /// <summary>言語の欄の 1 行（"日本語"・"English" のように、その言語で書いた名前）</summary>
    private static DataTemplate LanguageTemplate()
    {
        var factory = new FrameworkElementFactory(typeof(TextBlock));
        factory.SetBinding(TextBlock.TextProperty, new System.Windows.Data.Binding { Converter = new LanguageLabelConverter() });
        return new DataTemplate { VisualTree = factory };
    }

    private sealed class LanguageLabelConverter : System.Windows.Data.IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, System.Globalization.CultureInfo culture) =>
            value is PromptLanguage language ? TranslationLanguage.Of(language).Label() : "";

        public object ConvertBack(object value, Type targetType, object parameter, System.Globalization.CultureInfo culture) =>
            throw new NotSupportedException();
    }

    // MARK: - 入力欄

    // 設計判断: DEC-DIC-212（入力欄に入れるのは 100,000 字まで。超えた分は入れずに知らせる）
    private void OnInputChanged()
    {
        if (trimming) return;
        if (StyleLearner.Count(input.Text) > StyleLearner.InputLimit)
        {
            trimming = true;
            var caret = input.CaretIndex;
            input.Text = StyleLearner.Prefix(input.Text, StyleLearner.InputLimit);
            input.CaretIndex = Math.Min(caret, input.Text.Length);
            trimming = false;
            Show(inputNote, string.Format(Strings.StyleLearning_InputTruncated, StyleLearner.InputLimit.ToString("N0")));
        }
        countTimer.Stop();
        countTimer.Start();
        UpdateLearnButton();
    }

    /// <summary>字数と、送る字数（上限を超えたら先頭から）を出す。100 字未満なら理由を出す</summary>
    private void UpdateCount()
    {
        var material = StyleLearner.Material(input.Text, budget);
        countText.Text = material.Truncated
            ? string.Format(Strings.StyleLearning_CountUsed, material.TotalCharacters.ToString("N0"), material.UsedCharacters.ToString("N0"))
            : string.Format(Strings.StyleLearning_Count, material.TotalCharacters.ToString("N0"));
        UpdateLearnButton();
    }

    private bool Busy => cancellation is not null;

    private void UpdateLearnButton()
    {
        var enough = StyleLearner.Count(input.Text.Trim()) >= StyleLearner.MinimumCharacters;
        learnButton.IsEnabled = enough && !Busy;
        // 100 字未満なら押せない理由を出す（REQ-DIC-022）
        Show(needMore, enough ? null : string.Format(Strings.StyleLearning_NeedMore, StyleLearner.MinimumCharacters));
    }

    // 設計判断: DEC-DIC-211
    /// <summary>ファイルを読み、空行をはさんで選んだ順に入力欄の末尾に足す。読めないファイルがあれば理由を出し、入力欄は変えない</summary>
    private void ChooseFiles()
    {
        var dialog = new OpenFileDialog
        {
            Multiselect = true,
            Filter = string.Format(Strings.StyleLearning_FileFilter, StyleSourceReader.FilePattern),
            Title = Strings.StyleLearning_ChooseFiles,
        };
        if (dialog.ShowDialog(this) != true) return;
        var texts = new List<string>();
        var failures = new List<string>();
        foreach (var path in dialog.FileNames)
        {
            try
            {
                texts.Add(StyleSourceReader.Read(path));
            }
            catch (StyleSourceException e)
            {
                failures.Add(string.Format(Strings.StyleLearning_FileFailed, Path.GetFileName(path), e.Message));
            }
        }
        if (failures.Count > 0)
        {
            Show(inputNote, string.Join("\n", failures));
            return;
        }
        var parts = new List<string>();
        if (input.Text.Trim().Length > 0) parts.Add(input.Text.TrimEnd());
        parts.AddRange(texts.Where(t => t.Trim().Length > 0));
        Show(inputNote, null);
        // 入力欄の上限を超えたら OnInputChanged が切って知らせる
        input.Text = string.Join("\n\n", parts);
        input.CaretIndex = input.Text.Length;
        input.ScrollToEnd();
    }

    // MARK: - 学ぶ

    // 要件: REQ-DIC-022
    // 設計判断: DEC-DIC-210
    private async Task LearnAsync()
    {
        if (Busy) return;
        var settings = host.Settings.Current;
        ITextAiClient? client;
        try
        {
            client = host.CreateTextAi(settings, TextAiUse.Meeting, StyleLearner.Timeout);
        }
        catch (Exception e)
        {
            ShowLearnStatus("⚠️ " + e.Message);
            return;
        }
        if (client is null)
        {
            ShowLearnStatus("⚠️ " + TextAiFactory.NotReadyBecause(settings.MeetingAi));
            return;
        }
        budget = StyleLearner.Budget(client);
        UpdateCount();
        var mine = new CancellationTokenSource();
        cancellation = mine;
        SetBusy(true);
        try
        {
            var learned = await StyleLearner.LearnAsync(input.Text, client, settings.MinutesModel, mine.Token);
            if (mine.IsCancellationRequested) return;
            nameBox.Text = learned.Name;
            languageCombo.SelectedItem = learned.Language;
            rulesBox.Text = CustomStyleRules.ToText(learned.Rules);
            resultPanel.Visibility = Visibility.Visible;
            saveButton.IsEnabled = true;
            ShowLearnStatus(string.Format(Strings.StyleLearning_Learned, TextAiFactory.NameOf(settings.MeetingAi), settings.MinutesModel), error: false);
            nameBox.Focus();
        }
        catch (OperationCanceledException) when (mine.IsCancellationRequested)
        {
            if (IsLoaded) ShowLearnStatus(Strings.StyleLearning_Stopped, error: false);
        }
        catch (Exception e)
        {
            // どんな失敗でも理由を出し、入力した文章は残す（もう一度押せる）
            ShowLearnStatus("⚠️ " + e.Message);
        }
        finally
        {
            if (ReferenceEquals(cancellation, mine)) cancellation = null;
            mine.Dispose();
            if (IsLoaded) SetBusy(false);
        }
    }

    private void ShowLearnStatus(string text, bool error = true)
    {
        learnStatus.Foreground = error ? new SolidColorBrush(Color.FromRgb(0xC5, 0x22, 0x1F)) : SystemColors.GrayTextBrush;
        Show(learnStatus, text);
    }

    private void SetBusy(bool busy)
    {
        progress.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
        stopButton.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
        input.IsReadOnly = busy;
        if (busy) ShowLearnStatus(string.Format(Strings.StyleLearning_Learning, (int)StyleLearner.Timeout.TotalSeconds), error: false);
        UpdateLearnButton();
    }

    // MARK: - 保存

    private void UpdateRulesCount()
    {
        var rules = CustomStyleRules.FromText(rulesBox.Text);
        rulesCount.Text = string.Format(Strings.StyleLearning_RulesCount, rules.Count, CustomStyleRules.MaxRuleLines,
            CustomStyleRules.CharacterCount(rules).ToString("N0"), CustomStyleRules.MaxRuleCharacters.ToString("N0"));
    }

    // 要件: REQ-DIC-022
    // 設計判断: DEC-DIC-213
    private void Save()
    {
        var rules = CustomStyleRules.FromText(rulesBox.Text);
        var language = (languageCombo.SelectedItem as PromptLanguage)?.Code ?? "";
        var id = editing?.Id ?? Guid.NewGuid();
        var others = host.Settings.Current.CustomStyles.Where(c => c.Id != id);
        if (CustomStyleRules.Validate(nameBox.Text, language, rules, others) is { } problem)
        {
            Show(saveError, problem.Message());
            return;
        }
        cancellation?.Cancel();
        var style = new CustomStyle { Id = id, Name = nameBox.Text.Trim(), Language = language, Rules = rules };
        if (host.Settings.Update(s => CustomStyleRules.Upsert(s, style)) is { } error)
        {
            Show(saveError, string.Format(Strings.Meeting_SaveFailed, error.Message));
            return;
        }
        Saved = style;
        DialogResult = true;
    }
}
