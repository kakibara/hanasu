namespace Hanasu.Core.Dictation;

public enum HudPhase { Preparing, Recording, Processing, Done, Error }

/// <summary>HUD に出す状態。Message は Preparing / Processing / Done では見出し、Error では本文。</summary>
public sealed record HudState(HudPhase Phase, string? Message = null)
{
    public static HudState Preparing(string message) => new(HudPhase.Preparing, message);
    public static HudState Recording { get; } = new(HudPhase.Recording);
    public static HudState Processing(string message) => new(HudPhase.Processing, message);
    public static HudState Done(string message) => new(HudPhase.Done, message);
    public static HudState Error(string message) => new(HudPhase.Error, message);
}

/// <summary>画面の下に出る小さな状態表示。実装は WPF（Hanasu.Windows の HudWindow）。</summary>
public interface IHud
{
    void Show(HudState state);
    void UpdateTranscript(string text);
    /// <summary>「日本語 / English」の切り替えの表示</summary>
    void SetTranslating(bool translating);
    /// <summary>HUD の「日本語 / English」が押されたとき（true = English）</summary>
    event EventHandler<bool>? LanguageSelected;
    /// <summary>HUD の「■ 停止」が押されたとき（ショートカットをもう一度押したのと同じ）</summary>
    event EventHandler? StopRequested;
    /// <summary>HUD の「取消」が押されたとき（Esc と同じ）</summary>
    event EventHandler? CancelRequested;
}

/// <summary>HUD の文言の決め方（Mac 版の HUDView と同じ）。UI から切り離してテストできるようにする。</summary>
public static class HudText
{
    /// <summary>準備中と録音中は、出力の言語を選べる（クリックを受け取る）</summary>
    public static bool CanChooseLanguage(HudPhase phase) => phase is HudPhase.Preparing or HudPhase.Recording;

    /// <summary>「取消」「■ 停止」のボタンを出すか（準備中・録音中）</summary>
    public static bool ShowsRecordingControls(HudPhase phase) => phase is HudPhase.Preparing or HudPhase.Recording;

    public static string Title(HudState state) => state.Phase switch
    {
        HudPhase.Recording => "録音中",
        HudPhase.Error => "エラー",
        _ => state.Message ?? "",
    };

    /// <summary>2 行目。録音中・処理中は文字起こし（長ければ末尾）、エラーは本文</summary>
    public static string? Detail(HudState state, string transcript) => state.Phase switch
    {
        HudPhase.Recording => transcript.Length > 0 ? Tail(transcript) : "話してください…",
        HudPhase.Processing => transcript.Length > 0 ? Tail(transcript) : null,
        HudPhase.Error => state.Message,
        _ => null,
    };

    /// <summary>処理中の見出し</summary>
    public static string ProcessingTitle(bool translating) =>
        translating ? "Gemini で英語に翻訳しています…" : "Gemini で整えています…";

    /// <summary>経過時間（m:ss）</summary>
    public static string Elapsed(TimeSpan elapsed)
    {
        var seconds = Math.Max(0, (int)elapsed.TotalSeconds);
        return $"{seconds / 60}:{seconds % 60:00}";
    }

    /// <summary>長い文字起こしは末尾だけを見せる（Mac 版の truncationMode(.head) にあたる）</summary>
    public static string Tail(string text, int maxChars = 120)
    {
        text = text.ReplaceLineEndings(" ");
        return text.Length <= maxChars ? text : "…" + text[^maxChars..];
    }

    /// <summary>完了・エラーの表示を消すまでの時間</summary>
    public static TimeSpan? AutoHideDelay(HudPhase phase) => phase switch
    {
        HudPhase.Done => TimeSpan.FromSeconds(1.2),
        HudPhase.Error => TimeSpan.FromSeconds(5),
        _ => null,
    };
}
