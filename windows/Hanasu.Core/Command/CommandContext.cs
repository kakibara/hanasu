using Hanasu.Core.Ai;
using Hanasu.Core.Settings;

namespace Hanasu.Core.Command;

/// <summary>AI と、そのモデル（設定か --ai・--model）</summary>
public sealed record AiChoice(TextAiProvider Provider, string Model)
{
    /// <summary>JSON の値（Mac 版と同じ小文字の名前）</summary>
    public string ProviderName => Provider switch
    {
        TextAiProvider.Claude => "claude",
        TextAiProvider.Local => "local",
        _ => "gemini",
    };
}

/// <summary>認証情報の置き場所。値は持たない</summary>
/// <param name="Source">JSON の値（dpapi・windowsHello・serviceAccount・env:&lt;名前&gt;）。なければ null</param>
/// <param name="Label">表示の言語での置き場所</param>
/// <param name="Problem">読めなかった理由</param>
public sealed record CredentialStatus(string? Source = null, string? Label = null, string? Problem = null);

/// <summary>
/// コマンドが外の世界から受け取るもの。exe は本物を、テストは固定した値と偽物を入れる。
/// 時計と時差は引数で渡す（共有のテストデータで、Mac と同じ「今」と時差で動かすため。DEC-COM-192）
/// </summary>
public sealed class CommandContext
{
    public required AppSettings Settings { get; init; }
    public required ICommandConsole Console { get; init; }
    /// <summary>保存した API キー（なければ認証情報は環境変数だけ）</summary>
    public SecretStore? Secrets { get; init; }
    public Func<DateTimeOffset> Now { get; init; } = () => DateTimeOffset.Now;
    public TimeZoneInfo TimeZone { get; init; } = TimeZoneInfo.Local;
    public IReadOnlyDictionary<string, string> Environment { get; init; } = new Dictionary<string, string>();
    /// <summary>アプリの設定の会議の保存先（空なら既定）</summary>
    public string DefaultMeetingsDirectory { get; init; } = Meetings.MeetingStore.DefaultBaseDirectory;
    /// <summary>cli\hanasu.exe の絶対パス</summary>
    public string ExecutablePath { get; init; } = "";
    public string Version { get; init; } = "dev";
    /// <summary>選択の書き換えのタグの乱数（テストで固定する。null なら毎回作る）</summary>
    public string? Nonce { get; init; }

    /// <summary>
    /// AI のクライアントを作る（テストでは偽物）。null なら CommandAi.CreateClient（設定と認証情報から本物を作る）
    /// </summary>
    public Func<AiChoice, TextPurpose, TimeSpan, ITextAiClient>? ClientFactory { get; init; }

    /// <summary>ほかのプロセス（アプリ）がローカルの AI のサーバーを動かしているか（DEC-COM-184・WD4）</summary>
    public Func<bool> OtherLocalServerRunning { get; init; } = () => false;

    /// <summary>ローカルの AI のサーバー（hanasu が起動するもの。null なら LocalLlmServer.Shared）</summary>
    public LocalLlm.LocalLlmServer? LocalServer { get; init; }

    /// <summary>PATH の状態など、Windows でだけ分かること（doctor が出す）。テストでは null</summary>
    public ICommandPlatform? Platform { get; init; }

    /// <summary>共有の英語の文の ${device}</summary>
    public string Device { get; init; } = "this PC";

    public string? Env(string name) => Environment.TryGetValue(name, out var value) && value.Length > 0 ? value : null;

    /// <summary>今の「今」（テストでは固定）</summary>
    public DateTimeOffset CurrentTime => Now();
}

/// <summary>Windows でだけ分かること（doctor・設定画面）</summary>
public interface ICommandPlatform
{
    /// <summary>cli フォルダが、ユーザーの PATH に入っているか（入っている項目の値）。別の場所の Hanasu を指す項目も返す</summary>
    PathStatus PathStatus();
    /// <summary>アプリが一時フォルダ（zip の中など）から動いているか</summary>
    bool IsRunningFromTemporaryFolder { get; }
}

/// <summary>ユーザーの PATH の状態</summary>
/// <param name="Current">この cli フォルダを指す項目（なければ null）</param>
/// <param name="Others">別の場所の Hanasu の cli を指す項目</param>
/// <param name="OnProcessPath">このプロセス（ターミナル）の PATH に、この cli フォルダがあるか</param>
public sealed record PathStatus(string? Current, IReadOnlyList<string> Others, bool OnProcessPath);
