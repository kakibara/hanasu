namespace Hanasu.Core.Update;

// 設計判断: DEC-REL-021
/// <summary>インストールできる zip（Hanasu-&lt;版&gt;-Windows-x64.zip）。大きさと SHA-256 は API の値</summary>
public sealed record UpdateAsset(string Name, Uri DownloadUrl, long Size, string Sha256);

// 設計判断: DEC-REL-020, DEC-REL-021
/// <summary>公開された最新のリリース（GitHub の releases/latest の応答から取り出したもの）</summary>
public sealed record ReleaseInfo(AppVersion Version, string Tag, Uri ReleaseUrl, string Notes, UpdateAsset? Asset);

public enum UpdateCheckKind
{
    /// <summary>今の版が最新（またはそれより新しい）</summary>
    UpToDate,
    /// <summary>新しい版があり、アプリの中でインストールできる</summary>
    Available,
    /// <summary>新しい版はあるが、zip か SHA-256 が見つからない。リリースのページを開くことだけ案内する</summary>
    AvailableWithoutInstaller,
}

public sealed record UpdateCheckResult(UpdateCheckKind Kind, AppVersion Current, ReleaseInfo? Release)
{
    public bool HasUpdate => Kind != UpdateCheckKind.UpToDate;
}

/// <summary>確認やダウンロードに失敗した（画面に出せる文言を Message に入れる）</summary>
public sealed class UpdateException(string message, Exception? inner = null) : Exception(message, inner);
