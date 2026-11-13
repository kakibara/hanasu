using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using Hanasu.Core.Ai;
using Hanasu.Core.Dictation;
using Hanasu.Core.Settings;
using Hanasu.Windows.Services;
using Microsoft.Win32;

namespace Hanasu.Windows.Views;

// 要件: REQ-DIC-020, REQ-DIC-022, REQ-DIC-023
// 設計判断: DEC-DIC-047, DEC-DIC-213, DEC-DIC-215, DEC-DIC-216
/// <summary>
/// 設定の「アプリ別」（Mac 版の AppStylesTab にあたる）。全体のスイッチ、プリセットの説明、カスタム文体（一覧・「文章から学ぶ…」・
/// 「編集…」・「削除…」）、アプリの一覧（行ごとにプリセット（組み込みのあとに区切りを入れてカスタム文体を名前の順に）・追加ルール・一覧から外す）、
/// 「実行中のアプリから足す」「exe を選ぶ…」「初期設定に戻す…」。変更はその場で保存する
/// </summary>
public partial class SettingsWindow
{
    /// <summary>行を作り直している間は、選択の変更を保存しない</summary>
    private bool renderingAppStyles;

    private void LoadAppStylesTab()
    {
        var s = settings.Current;
        AppStylesEnabledCheck.IsChecked = s.AppStylesEnabled;
        AppStylesPresetNote.Text = string.Join("\n", Enum.GetValues<AppStylePreset>()
            .Where(p => p != AppStylePreset.None)
            .Append(AppStylePreset.None)
            .Select(p => string.Format(Strings.AppStyles_PresetLine, p.Label(), PresetSummary(p))));
        RenderCustomStyles();
        RenderAppStyles();
    }

    private static string PresetSummary(AppStylePreset preset) => preset switch
    {
        AppStylePreset.Chat => Strings.AppStyles_PresetSummary_Chat,
        AppStylePreset.Email => Strings.AppStyles_PresetSummary_Email,
        AppStylePreset.DocumentPolite => Strings.AppStyles_PresetSummary_DocumentPolite,
        AppStylePreset.DocumentPlain => Strings.AppStyles_PresetSummary_DocumentPlain,
        _ => Strings.AppStyles_PresetSummary_None,
    };

    private void OnAppStylesEnabledChanged(object sender, RoutedEventArgs e) =>
        Save(s => s.AppStylesEnabled = AppStylesEnabledCheck.IsChecked == true);

    private void ShowAppStylesStatus(string? text)
    {
        AppStylesStatus.Text = text ?? "";
        AppStylesStatus.Visibility = string.IsNullOrEmpty(text) ? Visibility.Collapsed : Visibility.Visible;
    }

    // MARK: - カスタム文体

    private void RenderCustomStyles()
    {
        CustomStylesPanel.Children.Clear();
        var styles = CustomStyleRules.Sorted(settings.Current.CustomStyles);
        if (styles.Count == 0)
        {
            CustomStylesPanel.Children.Add(new TextBlock { Text = Strings.CustomStyles_Empty, Style = (Style)FindResource("Note") });
            return;
        }
        foreach (var style in styles)
        {
            var row = new DockPanel { Margin = new Thickness(0, 3, 0, 3) };
            var buttons = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            var edit = new Button { Content = Strings.CustomStyles_Edit };
            AutomationProperties.SetName(edit, string.Format(Strings.CustomStyles_Edit_A11y, style.Name));
            edit.Click += (_, _) => EditCustomStyle(style);
            var delete = new Button { Content = Strings.CustomStyles_Delete, Margin = new Thickness(0) };
            AutomationProperties.SetName(delete, string.Format(Strings.CustomStyles_Delete_A11y, style.Name));
            delete.Click += (_, _) => DeleteCustomStyle(style);
            buttons.Children.Add(edit);
            buttons.Children.Add(delete);
            DockPanel.SetDock(buttons, Dock.Right);
            row.Children.Add(buttons);
            var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            text.Children.Add(new TextBlock { Text = style.Name, FontWeight = FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis });
            var language = style.PromptLanguage is { } l ? TranslationLanguage.Of(l).Label() : style.Language;
            text.Children.Add(new TextBlock
            {
                Text = string.Format(Strings.CustomStyles_RowDetail, language, style.Rules.Count),
                Style = (Style)FindResource("Note"),
                Margin = new Thickness(0),
            });
            row.Children.Add(text);
            CustomStylesPanel.Children.Add(row);
        }
    }

    // 要件: REQ-DIC-022
    private void OnLearnCustomStyle(object sender, RoutedEventArgs e)
    {
        var dialog = new StyleLearningWindow(host) { Owner = this };
        if (dialog.ShowDialog() == true) AfterCustomStylesChanged();
    }

    private void EditCustomStyle(CustomStyle style)
    {
        var dialog = new StyleLearningWindow(host, style) { Owner = this };
        if (dialog.ShowDialog() == true) AfterCustomStylesChanged();
    }

    // 要件: REQ-DIC-022
    // 設計判断: DEC-DIC-213（消すと、使っていたアプリは「なし」になる。アプリの追加ルールは残す）
    private void DeleteCustomStyle(CustomStyle style)
    {
        var count = CustomStyleRules.UsageCount(settings.Current, style.Id);
        var message = count == 0
            ? string.Format(Strings.CustomStyles_ConfirmDeleteUnused, style.Name)
            : string.Format(Strings.CustomStyles_ConfirmDelete, style.Name, count);
        if (MessageBox.Show(this, message, "Hanasu", MessageBoxButton.OKCancel, MessageBoxImage.Warning, MessageBoxResult.Cancel) != MessageBoxResult.OK) return;
        Save(s => CustomStyleRules.Delete(s, style.Id));
        AfterCustomStylesChanged();
    }

    private void AfterCustomStylesChanged()
    {
        RenderCustomStyles();
        // プリセットの選択欄にカスタム文体が並ぶので、アプリの一覧も作り直す
        RenderAppStyles();
        SaveStatus.Text = Strings.Settings_Saved;
    }

    // MARK: - アプリ

    private void RenderAppStyles()
    {
        renderingAppStyles = true;
        try
        {
            AppStylesPanel.Children.Clear();
            var current = settings.Current;
            var apps = current.EffectiveAppStyles;
            if (apps.Count == 0)
            {
                AppStylesPanel.Children.Add(new TextBlock { Text = Strings.AppStyles_NoApps, Style = (Style)FindResource("Note") });
                return;
            }
            var customs = CustomStyleRules.Sorted(current.CustomStyles);
            foreach (var app in apps) AppStylesPanel.Children.Add(BuildAppRow(app, customs));
        }
        finally
        {
            renderingAppStyles = false;
        }
    }

    private FrameworkElement BuildAppRow(AppStyleSetting app, IReadOnlyList<CustomStyle> customs)
    {
        var exe = AppStyleLookup.NormalizeExe(app.Exe);
        var name = app.Name.Trim().Length > 0 ? app.Name : exe;
        var border = new Border
        {
            BorderBrush = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(0xE0, 0xE0, 0xE0)),
            BorderThickness = new Thickness(0, 0, 0, 1),
            Padding = new Thickness(0, 6, 0, 8),
        };
        var panel = new StackPanel();
        var header = new DockPanel();
        var remove = new Button { Content = Strings.AppStyles_Remove, Margin = new Thickness(0), Padding = new Thickness(8, 1, 8, 1) };
        AutomationProperties.SetName(remove, string.Format(Strings.AppStyles_Remove_A11y, name));
        remove.Click += (_, _) => RemoveApp(exe);
        DockPanel.SetDock(remove, Dock.Right);
        header.Children.Add(remove);
        var title = new TextBlock { VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis };
        title.Inlines.Add(new System.Windows.Documents.Run(name) { FontWeight = FontWeights.SemiBold });
        title.Inlines.Add(new System.Windows.Documents.Run("  " + exe) { Foreground = System.Windows.SystemColors.GrayTextBrush });
        header.Children.Add(title);
        panel.Children.Add(header);

        // 設計判断: DEC-DIC-215（組み込みのプリセットのあとに区切りを入れて、カスタム文体を名前の順に）
        var preset = new DockPanel { Margin = new Thickness(0, 4, 0, 0) };
        var presetLabel = new TextBlock { Text = Strings.AppStyles_PresetLabel, Width = 110, VerticalAlignment = VerticalAlignment.Center };
        DockPanel.SetDock(presetLabel, Dock.Left);
        preset.Children.Add(presetLabel);
        var combo = new ComboBox { MinWidth = 240, HorizontalAlignment = HorizontalAlignment.Left };
        AutomationProperties.SetName(combo, string.Format(Strings.AppStyles_Preset_A11y, name));
        foreach (var p in Enum.GetValues<AppStylePreset>()) combo.Items.Add(new ComboBoxItem { Content = p.Label(), Tag = p });
        if (customs.Count > 0) combo.Items.Add(new Separator());
        foreach (var custom in customs) combo.Items.Add(new ComboBoxItem { Content = custom.Name, Tag = custom.Id });
        // 割り当てたカスタム文体が見つからなければ「なし」を選んでおく（DEC-DIC-213）
        combo.SelectedItem = combo.Items.OfType<ComboBoxItem>().FirstOrDefault(i => app.CustomStyleId is { } id && i.Tag is Guid g && g == id)
            ?? combo.Items.OfType<ComboBoxItem>().First(i => i.Tag is AppStylePreset p && p == (app.CustomStyleId is null ? app.PresetValue : AppStylePreset.None));
        combo.SelectionChanged += (_, _) =>
        {
            if (renderingAppStyles || combo.SelectedItem is not ComboBoxItem item) return;
            // 組み込みを選んだらカスタム文体の割り当てを外し、カスタムを選んだら Preset は「なし」にする
            if (item.Tag is AppStylePreset chosen) UpdateApp(exe, a => a.WithPreset(chosen));
            else if (item.Tag is Guid id) UpdateApp(exe, a => a.WithCustomStyle(id));
        };
        preset.Children.Add(combo);
        panel.Children.Add(preset);

        panel.Children.Add(new TextBlock { Text = Strings.AppStyles_RulesLabel, Margin = new Thickness(0, 6, 0, 2) });
        var rules = new TextBox
        {
            Text = app.Rules,
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            MinHeight = 44,
            MaxHeight = 120,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Padding = new Thickness(4, 3, 4, 3),
            ToolTip = Strings.AppStyles_RulesExample,
        };
        AutomationProperties.SetName(rules, string.Format(Strings.AppStyles_Rules_A11y, name));
        rules.TextChanged += (_, _) =>
        {
            if (renderingAppStyles) return;
            var text = rules.Text;
            UpdateApp(exe, a => a with { Rules = text });
        };
        panel.Children.Add(rules);
        border.Child = panel;
        return border;
    }

    /// <summary>exe の行を書き換えて保存する（既定の一覧のままなら、写してから書き換える）</summary>
    private void UpdateApp(string exe, Func<AppStyleSetting, AppStyleSetting> change) =>
        Save(s => s.AppStyles = s.EffectiveAppStyles.Select(a => AppStyleLookup.NormalizeExe(a.Exe) == exe ? change(a) : a).ToList());

    private void RemoveApp(string exe)
    {
        Save(s => s.AppStyles = s.EffectiveAppStyles.Where(a => AppStyleLookup.NormalizeExe(a.Exe) != exe).ToList());
        ShowAppStylesStatus(null);
        RenderAppStyles();
    }

    /// <summary>アプリを一覧の末尾に足す（プリセットは「なし」）。すでにあれば知らせるだけ</summary>
    private void AddApp(string exe, string name)
    {
        var normalized = AppStyleLookup.NormalizeExe(exe);
        if (settings.Current.EffectiveAppStyles.Any(a => AppStyleLookup.NormalizeExe(a.Exe) == normalized))
        {
            ShowAppStylesStatus(string.Format(Strings.AppStyles_AlreadyAdded, name));
            return;
        }
        Save(s => s.AppStyles = [.. s.EffectiveAppStyles, new AppStyleSetting { Exe = normalized, Name = name }]);
        ShowAppStylesStatus(null);
        RenderAppStyles();
    }

    // 設計判断: DEC-DIC-216（実行中のアプリ（メインウインドウのあるプロセス）から足す。ストアアプリは見分けられないので出さない）
    private void OnAddRunningApp(object sender, RoutedEventArgs e)
    {
        var listed = settings.Current.EffectiveAppStyles.Select(a => AppStyleLookup.NormalizeExe(a.Exe)).ToHashSet();
        var running = new Dictionary<string, string>();
        foreach (var process in Process.GetProcesses())
        {
            using (process)
            {
                try
                {
                    if (process.Id == Environment.ProcessId || process.MainWindowHandle == IntPtr.Zero) continue;
                    if (ForegroundWindowTracker.ExeOf(process.MainWindowHandle) is not { } exe) continue;
                    if (exe == AppStyleLookup.StoreAppHost || listed.Contains(exe) || running.ContainsKey(exe)) continue;
                    running[exe] = ForegroundWindowTracker.AppNameOf(process.MainWindowHandle) ?? exe;
                }
                catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception)
                {
                    // 終わったプロセス・読めないプロセスは飛ばす
                }
            }
        }
        var menu = new ContextMenu { PlacementTarget = AddRunningAppButton, Placement = System.Windows.Controls.Primitives.PlacementMode.Bottom };
        if (running.Count == 0)
        {
            menu.Items.Add(new MenuItem { Header = Strings.AppStyles_NoRunningApps, IsEnabled = false });
        }
        foreach (var (exe, name) in running.OrderBy(r => r.Value, StringComparer.CurrentCultureIgnoreCase))
        {
            var item = new MenuItem { Header = $"{name}  ({exe})" };
            item.Click += (_, _) => AddApp(exe, name);
            menu.Items.Add(item);
        }
        menu.IsOpen = true;
    }

    private void OnChooseAppExe(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Filter = Strings.AppStyles_ExeFilter, Title = Strings.AppStyles_ChooseExe };
        if (dialog.ShowDialog(this) != true) return;
        string name;
        try
        {
            var description = FileVersionInfo.GetVersionInfo(dialog.FileName).FileDescription?.Trim();
            name = string.IsNullOrEmpty(description) ? Path.GetFileNameWithoutExtension(dialog.FileName) : description;
        }
        catch (FileNotFoundException)
        {
            name = Path.GetFileNameWithoutExtension(dialog.FileName);
        }
        AddApp(Path.GetFileName(dialog.FileName), name);
    }

    // 設計判断: DEC-DIC-213（アプリの割り当てだけを戻し、カスタム文体は消さない）
    private void OnResetAppStyles(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show(this, Strings.AppStyles_ConfirmReset, "Hanasu", MessageBoxButton.OKCancel, MessageBoxImage.Warning, MessageBoxResult.Cancel)
            != MessageBoxResult.OK) return;
        Save(AppStyleSetting.ResetToDefaults);
        ShowAppStylesStatus(null);
        RenderAppStyles();
    }
}
