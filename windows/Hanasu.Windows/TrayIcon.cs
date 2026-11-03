using System.Windows;
using Hanasu.Core.Dictation;
using Forms = System.Windows.Forms;

namespace Hanasu.Windows;

/// <summary>
/// タスクトレイのアイコンとメニュー（Mac 版のメニューバーにあたる）。
/// 音声入力の開始 / 英訳して入力 / 最近の結果 / 設定 / 終了。
/// </summary>
internal sealed class TrayIcon : IDisposable
{
    private readonly AppHost host;
    private readonly Forms.NotifyIcon icon;
    private readonly Forms.ToolStripMenuItem dictateItem;
    private readonly Forms.ToolStripMenuItem translateItem;
    private readonly Forms.ToolStripMenuItem recentItem;
    private DictationState state = DictationState.Idle;

    public TrayIcon(AppHost host)
    {
        this.host = host;
        var menu = new Forms.ContextMenuStrip();
        dictateItem = new Forms.ToolStripMenuItem("", null, (_, _) => host.StartFromMenu(DictationMode.Refine));
        translateItem = new Forms.ToolStripMenuItem("", null, (_, _) => host.StartFromMenu(DictationMode.TranslateToEnglish));
        recentItem = new Forms.ToolStripMenuItem("最近の結果");
        menu.Items.Add(dictateItem);
        menu.Items.Add(translateItem);
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add(recentItem);
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add(new Forms.ToolStripMenuItem("設定…", null, (_, _) => host.ShowSettings()));
        menu.Items.Add(new Forms.ToolStripMenuItem("終了", null, (_, _) => host.Quit()));

        icon = new Forms.NotifyIcon
        {
            Icon = LoadIcon(),
            Text = "Hanasu",
            ContextMenuStrip = menu,
            Visible = true,
        };
        icon.DoubleClick += (_, _) => host.ShowSettings();
        UpdateMenuLabels();
        UpdateRecent();
    }

    private static System.Drawing.Icon LoadIcon()
    {
        var resource = Application.GetResourceStream(new Uri("pack://application:,,,/Assets/Hanasu.ico"));
        if (resource is null) return System.Drawing.SystemIcons.Application;
        using var stream = resource.Stream;
        // タスクトレイは小さいアイコンを使う
        return new System.Drawing.Icon(stream, Forms.SystemInformation.SmallIconSize);
    }

    public void UpdateState(DictationState newState)
    {
        state = newState;
        UpdateMenuLabels();
        icon.Text = newState switch
        {
            DictationState.Recording => "Hanasu — 録音中",
            DictationState.Processing => "Hanasu — 処理中",
            _ => "Hanasu",
        };
    }

    public void UpdateMenuLabels()
    {
        var s = host.Settings.Current;
        var busy = state is DictationState.Preparing or DictationState.Recording;
        dictateItem.Text = busy ? "録音を止めて入力" : "音声入力を開始";
        dictateItem.ShortcutKeyDisplayString = s.HotKey.DisplayString;
        translateItem.Text = "英訳して入力";
        translateItem.ShortcutKeyDisplayString = s.TranslateHotKey.DisplayString;
        // 処理中はどちらも押せない。録音中は「止める」だけ押せる
        dictateItem.Enabled = state != DictationState.Processing;
        translateItem.Enabled = state == DictationState.Idle;
    }

    /// <summary>最近の結果（メモリ上の 10 件）。押すとクリップボードにコピーする</summary>
    public void UpdateRecent()
    {
        recentItem.DropDownItems.Clear();
        var entries = host.Recent.Entries;
        if (entries.Count == 0)
        {
            recentItem.DropDownItems.Add(new Forms.ToolStripMenuItem("（まだありません）") { Enabled = false });
            return;
        }
        foreach (var entry in entries)
        {
            var output = entry.Output;
            var item = new Forms.ToolStripMenuItem(RecentResults.MenuLabel(entry).Replace("&", "&&"), null, (_, _) => host.CopyToClipboard(output))
            {
                ToolTipText = output.Length > 300 ? output[..300] + "…" : output,
            };
            recentItem.DropDownItems.Add(item);
        }
        recentItem.DropDownItems.Add(new Forms.ToolStripSeparator());
        recentItem.DropDownItems.Add(new Forms.ToolStripMenuItem("押すとクリップボードにコピーします") { Enabled = false });
    }

    public void ShowBalloon(string title, string text, bool warning = false)
    {
        icon.ShowBalloonTip(4000, title, text, warning ? Forms.ToolTipIcon.Warning : Forms.ToolTipIcon.Info);
    }

    public void Dispose()
    {
        icon.Visible = false;
        icon.Dispose();
    }
}
