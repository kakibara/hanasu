using System.Windows;
using Hanasu.Core.Dictation;
using Hanasu.Core.Meetings;
using Forms = System.Windows.Forms;

namespace Hanasu.Windows;

/// <summary>
/// タスクトレイのアイコンとメニュー（Mac 版のメニューバーにあたる）。
/// 音声入力の開始 / 翻訳して入力（英訳・和訳） / 会議の記録を開始・停止 / 会議ノートを開く / 最近の結果 / 履歴を開く / 設定 / 終了。
/// </summary>
internal sealed class TrayIcon : IDisposable
{
    private readonly AppHost host;
    private readonly Forms.NotifyIcon icon;
    private readonly Forms.ToolStripMenuItem dictateItem;
    private readonly Forms.ToolStripMenuItem translateItem;
    private readonly Forms.ToolStripMenuItem recentItem;
    private readonly Forms.ToolStripMenuItem meetingItem;
    private readonly Forms.Timer meetingTimer = new() { Interval = 1000 };
    private DictationState state = DictationState.Idle;
    private MeetingState meetingState = MeetingState.Idle;

    public TrayIcon(AppHost host)
    {
        this.host = host;
        var menu = new Forms.ContextMenuStrip();
        dictateItem = new Forms.ToolStripMenuItem("", null, (_, _) => host.StartFromMenu(DictationMode.Refine));
        // 設計判断: DEC-DIC-027（設定で選んだ翻訳の言語のうち最初で始める）
        translateItem = new Forms.ToolStripMenuItem("", null, (_, _) => host.StartFromMenu(host.Dictation.PrimaryTranslateMode));
        recentItem = new Forms.ToolStripMenuItem(Strings.Tray_Recent);
        meetingItem = new Forms.ToolStripMenuItem("", null, (_, _) => host.ToggleMeetingFromMenu());
        menu.Items.Add(dictateItem);
        menu.Items.Add(translateItem);
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add(meetingItem);
        menu.Items.Add(new Forms.ToolStripMenuItem(Strings.Tray_OpenMeetingNotes, null, (_, _) => host.ShowMeetings()));
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add(recentItem);
        menu.Items.Add(new Forms.ToolStripMenuItem(Strings.Tray_OpenHistory, null, (_, _) => host.ShowHistory()));
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add(new Forms.ToolStripMenuItem(Strings.Tray_Settings, null, (_, _) => host.ShowSettings()));
        menu.Items.Add(new Forms.ToolStripMenuItem(Strings.Tray_Quit, null, (_, _) => host.Quit()));

        icon = new Forms.NotifyIcon
        {
            Icon = LoadIcon(),
            Text = "Hanasu",
            ContextMenuStrip = menu,
            Visible = true,
        };
        icon.DoubleClick += (_, _) => host.ShowSettings();
        // 記録中は経過時間をメニューとアイコンの説明に出す
        meetingTimer.Tick += (_, _) => UpdateMenuLabels();
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
    }

    public void UpdateMeetingState(MeetingState newState)
    {
        meetingState = newState;
        if (newState == MeetingState.Recording) meetingTimer.Start();
        else meetingTimer.Stop();
        UpdateMenuLabels();
    }

    public void UpdateMenuLabels()
    {
        var s = host.Settings.Current;
        var busy = state is DictationState.Preparing or DictationState.Recording;
        dictateItem.Text = busy ? Strings.Tray_StopAndType : Strings.Tray_StartDictation;
        dictateItem.ShortcutKeyDisplayString = s.HotKey.DisplayString;
        translateItem.Text = TranslationLanguages.MenuTitle(s.TranslationLanguages);
        translateItem.ShortcutKeyDisplayString = s.TranslateHotKey.DisplayString;
        // 処理中はどちらも押せない。録音中は「止める」だけ押せる。会議の記録中は音声入力を使えない
        var meetingIdle = meetingState == MeetingState.Idle;
        dictateItem.Enabled = state != DictationState.Processing && meetingIdle;
        translateItem.Enabled = state == DictationState.Idle && meetingIdle;

        var elapsed = Meeting.Clock(host.Meetings.ElapsedSeconds);
        meetingItem.Text = meetingState switch
        {
            MeetingState.Recording => string.Format(Strings.Tray_StopMeeting, elapsed),
            MeetingState.Starting => Strings.Tray_MeetingStarting,
            MeetingState.Processing => Strings.Tray_MeetingProcessing,
            _ => Strings.Tray_StartMeeting,
        };
        meetingItem.ShortcutKeyDisplayString = s.MeetingHotKey.DisplayString;
        meetingItem.Enabled = meetingState is MeetingState.Idle or MeetingState.Recording && state == DictationState.Idle;
        var text = (state, meetingState) switch
        {
            (_, MeetingState.Recording) => string.Format(Strings.Tray_Tip_MeetingRecording, elapsed),
            (_, MeetingState.Processing) => Strings.Tray_Tip_MeetingProcessing,
            (DictationState.Recording, _) => Strings.Tray_Tip_Recording,
            (DictationState.Processing, _) => Strings.Tray_Tip_Processing,
            _ => "Hanasu",
        };
        icon.Text = text.Length > 63 ? text[..63] : text;  // NotifyIcon.Text は 63 文字まで
    }

    // 設計判断: DEC-DIC-078
    /// <summary>最近の結果（履歴の新しい順に 10 件）。押すとクリップボードにコピーする。最後に「すべての履歴を開く…」</summary>
    public void UpdateRecent()
    {
        recentItem.DropDownItems.Clear();
        var entries = host.History.Recent;
        if (entries.Count == 0)
        {
            recentItem.DropDownItems.Add(new Forms.ToolStripMenuItem(Strings.Tray_RecentEmpty) { Enabled = false });
        }
        foreach (var entry in entries)
        {
            var output = entry.Output;
            var tip = string.Format(Strings.Tray_RecentTip, DictationHistoryEntry.StatusLabel(entry.Status), Shorten(output), Shorten(entry.Raw));
            var item = new Forms.ToolStripMenuItem(DictationHistoryStore.MenuLabel(entry).Replace("&", "&&"), null, (_, _) => host.CopyToClipboard(output))
            {
                ToolTipText = tip,
            };
            recentItem.DropDownItems.Add(item);
        }
        recentItem.DropDownItems.Add(new Forms.ToolStripSeparator());
        if (entries.Count > 0) recentItem.DropDownItems.Add(new Forms.ToolStripMenuItem(Strings.Tray_RecentHint) { Enabled = false });
        recentItem.DropDownItems.Add(new Forms.ToolStripMenuItem(Strings.Tray_OpenAllHistory, null, (_, _) => host.ShowHistory()));
    }

    private static string Shorten(string text) => text.Length > 150 ? text[..150] + "…" : text;

    public void ShowBalloon(string title, string text, bool warning = false)
    {
        icon.ShowBalloonTip(4000, title, text, warning ? Forms.ToolTipIcon.Warning : Forms.ToolTipIcon.Info);
    }

    public void Dispose()
    {
        meetingTimer.Dispose();
        icon.Visible = false;
        icon.Dispose();
    }
}
