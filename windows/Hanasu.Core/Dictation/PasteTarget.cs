namespace Hanasu.Core.Dictation;

/// <summary>フォーカスのある要素の種類（UI Automation の ControlType をまとめたもの）</summary>
public enum FocusedControlKind
{
    /// <summary>UI Automation で調べられなかった（時間切れ・権限・要素がない など）</summary>
    Unknown,
    /// <summary>ControlType.Edit（1 行・複数行の入力欄）</summary>
    Edit,
    /// <summary>ControlType.Document（ブラウザのページ・ワープロの本文など）</summary>
    Document,
    /// <summary>そのほか（ボタン・一覧・ペインなど）</summary>
    Other,
}

/// <summary>
/// 貼り付ける直前に Win32 と UI Automation から集めた、前面のウインドウとフォーカスの様子。
/// 集めるのは Hanasu.Windows の FocusProbe。ここでは値だけを持ち、OS に触らない（Mac でもテストできる）。
/// 調べられなかった項目は null（分からない）にする。
/// </summary>
/// <param name="HasForegroundWindow">GetForegroundWindow が 0 でない</param>
/// <param name="ForegroundClass">前面のウインドウのクラス名（Progman・WorkerW・Shell_TrayWnd など）</param>
/// <param name="HasFocusWindow">GetGUIThreadInfo の hwndFocus が 0 でない。調べられなければ null</param>
/// <param name="HasCaret">GetGUIThreadInfo の hwndCaret が 0 でない（システムのキャレットがある）。調べられなければ null</param>
/// <param name="FocusedControl">UI Automation の FocusedElement の種類</param>
/// <param name="IsReadOnly">FocusedElement の ValuePattern の IsReadOnly。ValuePattern がなければ null</param>
public sealed record FocusSnapshot(
    bool HasForegroundWindow,
    string? ForegroundClass = null,
    bool? HasFocusWindow = null,
    bool? HasCaret = null,
    FocusedControlKind FocusedControl = FocusedControlKind.Unknown,
    bool? IsReadOnly = null);

/// <summary>貼り付けなかった（貼り付けられなかった）理由</summary>
public enum NotPastedReason
{
    /// <summary>前面にウインドウがない</summary>
    NoForegroundWindow,
    /// <summary>デスクトップ（Progman / WorkerW）が前面にある</summary>
    Desktop,
    /// <summary>タスクバー（Shell_TrayWnd / Shell_SecondaryTrayWnd）が前面にある</summary>
    Taskbar,
    /// <summary>エクスプローラーのウインドウで、ファイルの一覧など入力欄でない場所にフォーカスがある</summary>
    FileExplorer,
    /// <summary>前面のウインドウの中に、フォーカスのある場所がない</summary>
    NoFocus,
    /// <summary>フォーカスのある入力欄が読み取り専用</summary>
    ReadOnly,
    /// <summary>前面のウインドウが Hanasu より権限が高い（UIPI でキーが届かない。DEC-COM-149）</summary>
    HigherIntegrity,
    /// <summary>SendInput が Ctrl+V を送れなかった</summary>
    SendFailed,
    /// <summary>クリップボードに文章を置けなかった（ほかのアプリが開いたまま など）</summary>
    ClipboardUnavailable,
    /// <summary>入力の途中で例外が起きた</summary>
    Failed,
}

/// <summary>判定の結果。CanPaste が false なら Reason に理由が入る。Basis はログに書く根拠（文章の中身は入れない）</summary>
public sealed record PasteTargetDecision(bool CanPaste, NotPastedReason? Reason, string Basis)
{
    public static PasteTargetDecision Paste(string basis) => new(true, null, basis);
    public static PasteTargetDecision NoTarget(NotPastedReason reason, string basis) => new(false, reason, basis);
}

// 要件: REQ-DIC-080
// 設計判断: DEC-DIC-120
/// <summary>
/// 前面のウインドウとフォーカスの様子から、Ctrl+V で貼り付けてよいかを決める（純粋な関数）。
/// 分からないときは貼り付ける。誤って表示に回すより、貼り付けを試す方を優先する。
/// </summary>
public static class PasteTargetJudge
{
    /// <summary>デスクトップのウインドウのクラス（壁紙・アイコンの並ぶところ）</summary>
    public static readonly IReadOnlySet<string> DesktopClasses = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "Progman", "WorkerW" };

    /// <summary>タスクバーのウインドウのクラス（メインと、ほかの画面のもの）</summary>
    public static readonly IReadOnlySet<string> TaskbarClasses = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "Shell_TrayWnd", "Shell_SecondaryTrayWnd" };

    /// <summary>エクスプローラーのウインドウのクラス（Windows 10 / 11。タブがあっても同じ）</summary>
    public static readonly IReadOnlySet<string> FileExplorerClasses = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "CabinetWClass", "ExploreWClass" };

    /// <summary>
    /// フォーカスがほかのスレッド・プロセスのウインドウにあるので、GetGUIThreadInfo の hwndFocus が 0 になりうる前面のウインドウ。
    /// ストアアプリ（ApplicationFrameHost の枠と、中の CoreWindow）。これらは「フォーカスがない」とは決めない
    /// </summary>
    public static readonly IReadOnlySet<string> CrossThreadFocusClasses = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "ApplicationFrameWindow", "Windows.UI.Core.CoreWindow",
    };

    public static PasteTargetDecision Judge(FocusSnapshot s)
    {
        // 1. 前面にウインドウがない（すべて最小化した直後 など）
        if (!s.HasForegroundWindow) return PasteTargetDecision.NoTarget(NotPastedReason.NoForegroundWindow, "前面のウインドウがない");

        // 2. 入力欄にフォーカスがあるが、読み取り専用（貼っても入らない）
        if (s.FocusedControl == FocusedControlKind.Edit && s.IsReadOnly == true)
        {
            return PasteTargetDecision.NoTarget(NotPastedReason.ReadOnly, "読み取り専用の入力欄");
        }

        // 3. 文字を入れられる場所だと分かった。デスクトップの上でも（アイコンの名前の変更など）貼る
        if (s.FocusedControl is FocusedControlKind.Edit or FocusedControlKind.Document)
        {
            return PasteTargetDecision.Paste($"UI Automation: {s.FocusedControl}");
        }
        if (s.HasCaret == true) return PasteTargetDecision.Paste("キャレットがある");

        // 4. デスクトップ・タスクバーが前面（入力欄を見つけられなかった）。
        //    エクスプローラーは、UI Automation で入力欄でない（ファイルの一覧など）と分かったときだけ。アドレスバー・検索欄は 3 で貼る
        if (s.ForegroundClass is { } cls)
        {
            if (DesktopClasses.Contains(cls)) return PasteTargetDecision.NoTarget(NotPastedReason.Desktop, $"デスクトップ（{cls}）");
            if (TaskbarClasses.Contains(cls)) return PasteTargetDecision.NoTarget(NotPastedReason.Taskbar, $"タスクバー（{cls}）");
            if (FileExplorerClasses.Contains(cls) && s.FocusedControl == FocusedControlKind.Other)
            {
                return PasteTargetDecision.NoTarget(NotPastedReason.FileExplorer, $"エクスプローラー（{cls}）の入力欄でない場所");
            }
        }

        // 5. 前面のウインドウの中にフォーカスがない。ストアアプリは別のスレッドにフォーカスがあるので除く
        if (s.HasFocusWindow == false && !(s.ForegroundClass is { } c && CrossThreadFocusClasses.Contains(c)))
        {
            return PasteTargetDecision.NoTarget(NotPastedReason.NoFocus, $"フォーカスがない（{s.ForegroundClass ?? "?"}）");
        }

        // 6. 分からない（ブラウザ・Electron・独自に描くアプリ・Excel のセルなど）。今までどおり貼る
        return PasteTargetDecision.Paste($"分からない（{s.ForegroundClass ?? "?"}・{s.FocusedControl}）");
    }
}
