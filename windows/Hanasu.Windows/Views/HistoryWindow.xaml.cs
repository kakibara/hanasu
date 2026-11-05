using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using Hanasu.Core.Dictation;
using Hanasu.Windows.Services;

namespace Hanasu.Windows.Views;

/// <summary>
/// 音声入力の履歴のウインドウ（Mac 版の DictationHistoryView）。日ごとの一覧・検索・「失敗・未整形」の絞り込み、
/// 選んだ項目の結果と原文の表示・コピー・削除。Delete キーでも消せる。
/// 整形し直す（REQ-DIC-061）と録音の再生は Windows 版にはない。
/// </summary>
// 要件: REQ-DIC-060
// 設計判断: DEC-DIC-079, DEC-DIC-131
public partial class HistoryWindow : Window
{
    /// <summary>一覧の 1 行</summary>
    private sealed record Row(DictationHistoryEntry Entry, string Day, string Time, string Summary, string Meta, string Mark);

    private readonly DictationHistoryStore history;
    private List<Row> rows = new();

    internal HistoryWindow(AppHost host)
    {
        history = host.History;
        InitializeComponent();
        WindowFit.FitToMouseScreen(this);
        history.Changed += OnHistoryChanged;
        Closed += (_, _) => history.Changed -= OnHistoryChanged;
        Reload();
        SearchBox.Focus();
    }

    private void OnHistoryChanged(object? sender, EventArgs e) => Dispatcher.BeginInvoke(Reload);

    /// <summary>今の検索と絞り込みで一覧を作り直す。選んでいた項目は、残っていれば選んだままにする</summary>
    private void Reload()
    {
        var selected = EntryList.SelectedItems.OfType<Row>().Select(r => r.Entry.Id).ToHashSet();
        var all = history.Entries;
        var now = DateTimeOffset.Now;
        var shown = DictationHistoryStore.Filter(all, SearchBox.Text, UnrefinedRadio.IsChecked == true);
        rows = shown.Select(e => new Row(
            e,
            DictationHistoryStore.DayLabel(e.Date, now),
            e.Date.ToLocalTime().ToString("HH:mm"),
            e.Output.ReplaceLineEndings(" ").Trim(),
            string.Join("・", new[] { DictationHistoryEntry.ModeLabel(e.Mode), e.AppName }.Where(s => !string.IsNullOrEmpty(s))),
            e.IsFailure ? "⚠" : e.IsUnrefined ? "未整形" : "")).ToList();

        var view = new ListCollectionView(rows);
        view.GroupDescriptions.Add(new PropertyGroupDescription(nameof(Row.Day)));
        EntryList.ItemsSource = view;
        foreach (var row in rows.Where(r => selected.Contains(r.Entry.Id))) EntryList.SelectedItems.Add(row);
        if (EntryList.SelectedItems.Count == 0 && rows.Count > 0) EntryList.SelectedIndex = 0;
        EmptyText.Text = all.Count == 0
            ? "まだ履歴がありません。音声入力をすると、ここに残ります。"
            : "条件に一致する履歴がありません。";
        EmptyText.Visibility = rows.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

        var policy = history.Policy;
        var kept = policy.Enabled
            ? $"{HistoryPolicy.DaysLabel(policy.MaxDays)}・{policy.MaxCount} 件まで残します（設定 → 履歴）"
            : "履歴をファイルに保存しない設定です。直近 10 件だけをメモリに置いています（設定 → 履歴）";
        CountText.Text = shown.Count == all.Count ? $"{all.Count} 件。{kept}" : $"{shown.Count} 件 / {all.Count} 件。{kept}";
        ErrorText.Text = history.LastError ?? "";
        ErrorText.Visibility = history.LastError is null ? Visibility.Collapsed : Visibility.Visible;
        ShowDetail();
    }

    private IReadOnlyList<DictationHistoryEntry> SelectedEntries => EntryList.SelectedItems.OfType<Row>().Select(r => r.Entry).ToArray();

    private void ShowDetail()
    {
        var selected = SelectedEntries;
        var entry = selected.Count == 1 ? selected[0] : null;
        OutputBox.Text = entry?.Output ?? "";
        RawBox.Text = entry?.Raw ?? "";
        CopyOutputButton.IsEnabled = CopyRawButton.IsEnabled = entry is not null;
        DeleteButton.IsEnabled = selected.Count > 0;
        CopyStatus.Text = "";
        if (entry is null)
        {
            DetailInfo.Text = selected.Count > 1 ? $"{selected.Count} 件を選んでいます（Delete キーか「削除」でまとめて消せます）" : "";
            return;
        }
        var parts = new List<string>
        {
            entry.Date.ToLocalTime().ToString("yyyy/MM/dd HH:mm:ss"),
            DictationHistoryEntry.ModeLabel(entry.Mode),
            DictationHistoryEntry.StatusLabel(entry.Status),
        };
        if (entry.AppName is { } app) parts.Add($"入力先: {app}");
        if (entry.Model is { } model) parts.Add($"モデル: {model}");
        DetailInfo.Text = string.Join("　", parts) + (entry.ErrorMessage is { } error ? $"\n{error}" : "");
    }

    private void OnSearchChanged(object sender, TextChangedEventArgs e) => Reload();

    private void OnFilterChanged(object sender, RoutedEventArgs e)
    {
        if (IsLoaded) Reload();
    }

    private void OnSelectionChanged(object sender, SelectionChangedEventArgs e) => ShowDetail();

    private void OnListKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Delete)
        {
            DeleteSelected();
            e.Handled = true;
        }
        else if (e.Key == Key.C && Keyboard.Modifiers == ModifierKeys.Control && SelectedEntries.Count == 1)
        {
            Copy(SelectedEntries[0].Output);
            e.Handled = true;
        }
    }

    private void OnCopyOutputClick(object sender, RoutedEventArgs e)
    {
        if (SelectedEntries is [var entry]) Copy(entry.Output);
    }

    private void OnCopyRawClick(object sender, RoutedEventArgs e)
    {
        if (SelectedEntries is [var entry]) Copy(entry.Raw);
    }

    private void Copy(string text)
    {
        try
        {
            Clipboard.SetText(text);
            CopyStatus.Text = "コピーしました";
        }
        catch (System.Runtime.InteropServices.ExternalException ex)
        {
            AppLog.Write($"history copy failed: {ex.Message}");
            CopyStatus.Text = "コピーできませんでした（ほかのアプリがクリップボードを使っています）";
        }
    }

    private void OnDeleteClick(object sender, RoutedEventArgs e) => DeleteSelected();

    private void DeleteSelected()
    {
        var selected = SelectedEntries;
        if (selected.Count == 0) return;
        // 1 件でも確かめる（DEC-DIC-079）
        var question = selected.Count > 1 ? $"選んだ {selected.Count} 件の履歴を削除しますか？" : "この履歴を削除しますか？";
        if (MessageBox.Show(this, $"{question}元に戻せません。", "Hanasu",
                MessageBoxButton.OKCancel, MessageBoxImage.Question, MessageBoxResult.Cancel) != MessageBoxResult.OK) return;
        history.Delete(selected.Select(s => s.Id));
    }

    private void OnDeleteAllClick(object sender, RoutedEventArgs e)
    {
        if (history.Entries.Count == 0) return;
        if (MessageBox.Show(this, $"音声入力の履歴 {history.Entries.Count} 件をすべて削除しますか？元に戻せません。", "Hanasu",
                MessageBoxButton.OKCancel, MessageBoxImage.Warning, MessageBoxResult.Cancel) != MessageBoxResult.OK) return;
        history.DeleteAll();
    }

    private void OnOpenFolderClick(object sender, RoutedEventArgs e)
    {
        Directory.CreateDirectory(history.Directory);
        Process.Start(new ProcessStartInfo("explorer.exe", $"\"{history.Directory}\"") { UseShellExecute = true });
    }

    private void OnCloseClick(object sender, RoutedEventArgs e) => Close();
}
