using Hanasu.Core.Dictation;

namespace Hanasu.Core.Tests;

// 確かめ方: REQ-DIC-080
public class PasteTargetTests
{
    private static PasteTargetDecision Judge(FocusSnapshot s) => PasteTargetJudge.Judge(s);

    [Fact]
    public void NoForegroundWindowIsNoTarget()
    {
        var d = Judge(new FocusSnapshot(HasForegroundWindow: false));
        Assert.False(d.CanPaste);
        Assert.Equal(NotPastedReason.NoForegroundWindow, d.Reason);
    }

    [Theory]
    [InlineData("Progman", NotPastedReason.Desktop)]
    [InlineData("WorkerW", NotPastedReason.Desktop)]
    [InlineData("Shell_TrayWnd", NotPastedReason.Taskbar)]
    [InlineData("Shell_SecondaryTrayWnd", NotPastedReason.Taskbar)]
    public void DesktopAndTaskbarAreNoTarget(string className, NotPastedReason reason)
    {
        // デスクトップのアイコンの一覧にフォーカスがある（キャレットはない）
        var d = Judge(new FocusSnapshot(true, className, HasFocusWindow: true, HasCaret: false, FocusedControl: FocusedControlKind.Other));
        Assert.False(d.CanPaste);
        Assert.Equal(reason, d.Reason);
        // UI Automation で調べられなくても、デスクトップなら貼らない
        Assert.Equal(reason, Judge(new FocusSnapshot(true, className, HasFocusWindow: true, HasCaret: false)).Reason);
    }

    [Fact]
    public void RenamingAnIconOnTheDesktopIsPasted()
    {
        // デスクトップでも、名前の変更の入力欄（Edit）にフォーカスがあれば貼る
        Assert.True(Judge(new FocusSnapshot(true, "Progman", true, true)).CanPaste);
        Assert.True(Judge(new FocusSnapshot(true, "WorkerW", true, false, FocusedControlKind.Edit, IsReadOnly: false)).CanPaste);
    }

    [Fact]
    public void NoFocusInTheForegroundWindowIsNoTarget()
    {
        var d = Judge(new FocusSnapshot(true, "Notepad", HasFocusWindow: false, HasCaret: false));
        Assert.False(d.CanPaste);
        Assert.Equal(NotPastedReason.NoFocus, d.Reason);
    }

    [Theory]
    [InlineData("ApplicationFrameWindow")]
    [InlineData("Windows.UI.Core.CoreWindow")]
    public void StoreAppsWithFocusInAnotherThreadArePasted(string className)
    {
        // ストアアプリは、枠のスレッドに hwndFocus がなくても中にフォーカスがある
        Assert.True(Judge(new FocusSnapshot(true, className, HasFocusWindow: false, HasCaret: false)).CanPaste);
    }

    [Fact]
    public void ReadOnlyEditIsNoTarget()
    {
        var d = Judge(new FocusSnapshot(true, "#32770", true, false, FocusedControlKind.Edit, IsReadOnly: true));
        Assert.False(d.CanPaste);
        Assert.Equal(NotPastedReason.ReadOnly, d.Reason);
    }

    [Theory]
    [InlineData(FocusedControlKind.Edit, false)]
    [InlineData(FocusedControlKind.Edit, null)]
    [InlineData(FocusedControlKind.Document, false)]
    [InlineData(FocusedControlKind.Document, true)]   // ブラウザのページ全体は読み取り専用の Document として出ることがある。分からないので貼る
    [InlineData(FocusedControlKind.Document, null)]
    public void EditableControlsArePasted(FocusedControlKind control, bool? readOnly)
    {
        Assert.True(Judge(new FocusSnapshot(true, "Chrome_WidgetWin_1", true, false, control, readOnly)).CanPaste);
    }

    [Fact]
    public void CaretMeansATextField()
    {
        Assert.True(Judge(new FocusSnapshot(true, "Notepad", true, HasCaret: true)).CanPaste);
    }

    [Fact]
    public void FileExplorerListIsNoTargetButItsAddressBarIsPasted()
    {
        var list = Judge(new FocusSnapshot(true, "CabinetWClass", true, false, FocusedControlKind.Other));
        Assert.False(list.CanPaste);
        Assert.Equal(NotPastedReason.FileExplorer, list.Reason);
        Assert.True(Judge(new FocusSnapshot(true, "CabinetWClass", true, false, FocusedControlKind.Edit, false)).CanPaste);
        // UI Automation で分からなければ貼る
        Assert.True(Judge(new FocusSnapshot(true, "CabinetWClass", true, false)).CanPaste);
    }

    [Theory]
    // ブラウザ・Electron（キャレットがなく、UI Automation も分からない）
    [InlineData("Chrome_WidgetWin_1", FocusedControlKind.Unknown)]
    // Excel のセル（DataItem など。入力欄ではないが Ctrl+V で入る）
    [InlineData("XLMAIN", FocusedControlKind.Other)]
    // 独自に描くアプリ・ゲーム
    [InlineData("SomeCustomWindow", FocusedControlKind.Other)]
    public void UnknownCasesArePasted(string className, FocusedControlKind control)
    {
        Assert.True(Judge(new FocusSnapshot(true, className, HasFocusWindow: true, HasCaret: false, FocusedControl: control)).CanPaste);
    }

    [Fact]
    public void NothingKnownIsPasted()
    {
        // GetGUIThreadInfo も UI Automation も失敗した
        Assert.True(Judge(new FocusSnapshot(true)).CanPaste);
    }

    [Fact]
    public void BasisDoesNotContainText()
    {
        var d = Judge(new FocusSnapshot(true, "Progman", true, false, FocusedControlKind.Other));
        Assert.Contains("Progman", d.Basis);
    }
}

public class UnpastedHudTextTests
{
    [Fact]
    public void TitlesFollowTheReason()
    {
        Assert.Equal("入力できる場所が見つかりませんでした", HudText.UnpastedTitle(NotPastedReason.Desktop));
        Assert.Equal("入力できる場所が見つかりませんでした", HudText.UnpastedTitle(NotPastedReason.NoFocus));
        Assert.Equal("管理者として動いているアプリには貼り付けられません", HudText.UnpastedTitle(NotPastedReason.HigherIntegrity));
        Assert.Equal("クリップボードを使えませんでした", HudText.UnpastedTitle(NotPastedReason.ClipboardUnavailable));
    }

    [Fact]
    public void UnpastedPhaseIsNotAutoHiddenAndAcceptsClicks()
    {
        Assert.Null(HudText.AutoHideDelay(HudPhase.Unpasted));
        Assert.True(HudText.AcceptsClicks(HudPhase.Unpasted));
        Assert.True(HudText.AcceptsClicks(HudPhase.Recording));
        Assert.False(HudText.AcceptsClicks(HudPhase.Done));
        Assert.False(HudText.AcceptsClicks(HudPhase.Error));
        Assert.False(HudText.CanChooseLanguage(HudPhase.Unpasted));
        Assert.False(HudText.ShowsRecordingControls(HudPhase.Unpasted));
    }

    [Fact]
    public void FullTextIsKeptEvenWhenLong()
    {
        var text = string.Concat(Enumerable.Repeat("長い文章です。", 200));
        var state = HudState.Unpasted(text, NotPastedReason.Desktop, clipboardHasText: false);
        Assert.Equal(text, state.ResultText);
    }
}
