using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Hanasu.Core.Ai;

namespace Hanasu.Core.Settings;

/// <summary>保存する秘密の値の種類</summary>
public enum SecretKind
{
    GeminiApiKey,
    ClaudeApiKey,
}

/// <summary>秘密の値の守り方</summary>
[JsonConverter(typeof(JsonStringEnumConverter<SecretProtection>))]
public enum SecretProtection
{
    /// <summary>DPAPI（CurrentUser）。同じ Windows ユーザーでログインしていれば、確認なしに読める（既定）</summary>
    Dpapi,
    /// <summary>Windows Hello の鍵（TPM）から作った鍵で暗号化する。読むときに本人の確認（PIN・顔・指紋）が要る</summary>
    WindowsHello,
    /// <summary>PR #19 までの形（settings.json の protectedApiKey）をそのまま移したもの。DPAPI で、エントロピーが違う</summary>
    DpapiLegacy,
}

/// <summary>DPAPI（Windows の CryptProtectData）。テストでは偽物に差し替える</summary>
public interface IDataProtector
{
    byte[] Protect(byte[] data, byte[] entropy);
    /// <summary>復号できなければ null（別のユーザー・別の PC で暗号化したもの、壊れたもの）</summary>
    byte[]? Unprotect(byte[] data, byte[] entropy);
}

/// <summary>
/// 本人の確認をしてから使える鍵（Windows では Windows Hello の KeyCredentialManager）。テストでは偽物に差し替える。
/// 同じ鍵からは、いつも同じ 32 バイトを返すこと（それで暗号化した値を、次に起動したときも読むため）。
/// </summary>
public interface IUserPresenceKey
{
    /// <summary>この PC で使えるか（Windows Hello が設定されているか）</summary>
    Task<bool> IsAvailableAsync();

    /// <summary>本人の確認をして、32 バイトの鍵を返す。create なら、鍵がなければ作る。断られた・使えないときは SecretAccessException</summary>
    Task<byte[]> DeriveKeyAsync(bool create, CancellationToken cancellationToken);
}

/// <summary>秘密の値を読めなかった（Windows Hello の確認を断られた、別のユーザーで保存した など）。Message は画面に出せる日本語</summary>
public sealed class SecretAccessException(string message, Exception? inner = null) : TextAiException(message, inner)
{
    public override bool IsCredentialProblem => true;
}

/// <summary>画面に出してよい、秘密の値の状態（値そのものは含まない）</summary>
public sealed record SecretInfo(bool Exists, string? Hint, SecretProtection? Protection)
{
    /// <summary>「保存済み（…abcd、Windows Hello）」のような 1 行</summary>
    public string Describe()
    {
        if (!Exists) return Strings.Secret_NotSet;
        var hint = Hint is { Length: > 0 } h ? $"…{h}" : Strings.Secret_HintUnknown;
        var how = Protection switch
        {
            SecretProtection.WindowsHello => Strings.Secret_ProtectedByHello,
            _ => Strings.Secret_ProtectedByDpapi,
        };
        return string.Format(Strings.Secret_Saved, hint, how);
    }
}

/// <summary>
/// API キー（Gemini・Claude）を <c>%LOCALAPPDATA%\Hanasu\secrets.json</c> に暗号化して保存する。設定（settings.json）には入れない。
/// - 既定は DPAPI（CurrentUser・種類ごとのエントロピー）。Windows Hello を選ぶと、読むたびに本人の確認が要る鍵で暗号化する
///   （確認は起動してから最初に使うとき 1 回。鍵は画面のロックまでメモリに置く）
/// - 平文は保存しない。画面に出すのは末尾 4 文字（Hint）だけ
/// - PR #19 までの settings.json の protectedApiKey は、復号せずにそのまま移す（MigrateLegacy。移しても読めなくならない）
/// - 値は使うときに読む（GetAsync）。読んだ値をこのクラスは持たない
/// </summary>
// 要件: REQ-COM-021
// 設計判断: DEC-COM-144
public sealed class SecretStore
{
    /// <summary>PR #19 までの DPAPI のエントロピー（settings.json の protectedApiKey）</summary>
    internal static readonly byte[] LegacyEntropy = Encoding.UTF8.GetBytes("Hanasu.Windows.GeminiApiKey");

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    private readonly IDataProtector dpapi;
    private readonly IUserPresenceKey? presence;
    private readonly object gate = new();
    private readonly SemaphoreSlim presenceLock = new(1, 1);
    private byte[]? presenceKey;

    public string Path { get; }

    /// <summary>値が変わったとき（設定画面の表示を直すため）</summary>
    public event EventHandler<SecretKind>? Changed;

    public SecretStore(string path, IDataProtector dpapi, IUserPresenceKey? presence = null)
    {
        Path = path;
        this.dpapi = dpapi;
        this.presence = presence;
    }

    public static string DefaultPath => System.IO.Path.Combine(HanasuPaths.LocalDataDirectory, "secrets.json");

    /// <summary>Windows Hello を選べるか（この PC に IUserPresenceKey があるか。設定されているかは IsPresenceAvailableAsync）</summary>
    public bool SupportsPresence => presence is not null;

    public Task<bool> IsPresenceAvailableAsync() => presence?.IsAvailableAsync() ?? Task.FromResult(false);

    /// <summary>新しく保存するときの守り方</summary>
    public SecretProtection PreferredProtection
    {
        get { lock (gate) return Read().Preferred; }
    }

    public bool Has(SecretKind kind) => Describe(kind).Exists;

    public SecretInfo Describe(SecretKind kind)
    {
        lock (gate)
        {
            return Read().Entries.TryGetValue(Key(kind), out var e) && e.Data.Length > 0
                ? new SecretInfo(true, e.Hint, e.Protection)
                : new SecretInfo(false, null, null);
        }
    }

    /// <summary>値を読む。保存されていなければ null。読めなければ SecretAccessException（値を消しはしない）</summary>
    public async Task<string?> GetAsync(SecretKind kind, CancellationToken cancellationToken = default)
    {
        Entry? entry;
        lock (gate) entry = Read().Entries.GetValueOrDefault(Key(kind));
        if (entry is null || entry.Data.Length == 0) return null;
        byte[] data;
        try { data = Convert.FromBase64String(entry.Data); }
        catch (FormatException e) { throw new SecretAccessException(Strings.Secret_Corrupted, e); }

        byte[]? plain;
        switch (entry.Protection)
        {
            case SecretProtection.Dpapi:
                plain = dpapi.Unprotect(data, Entropy(kind));
                break;
            case SecretProtection.DpapiLegacy:
                plain = dpapi.Unprotect(data, LegacyEntropy);
                break;
            case SecretProtection.WindowsHello:
                var key = await PresenceKeyAsync(create: false, cancellationToken).ConfigureAwait(false);
                plain = AesGcmBox.Open(key, data, Aad(kind));
                if (plain is null)
                {
                    throw new SecretAccessException(Strings.Secret_HelloDecryptFailed);
                }
                break;
            default:
                plain = null;
                break;
        }
        if (plain is null)
        {
            throw new SecretAccessException(Strings.Secret_DpapiDecryptFailed);
        }
        try { return Encoding.UTF8.GetString(plain); }
        finally { CryptographicOperations.ZeroMemory(plain); }
    }

    /// <summary>値を保存する（前後の空白は除く）。空か null なら消す。守り方は PreferredProtection</summary>
    public async Task SetAsync(SecretKind kind, string? value, CancellationToken cancellationToken = default)
    {
        var trimmed = value?.Trim() ?? "";
        if (trimmed.Length == 0)
        {
            Mutate(f => f.Entries.Remove(Key(kind)));
            Changed?.Invoke(this, kind);
            return;
        }
        var entry = await SealAsync(kind, trimmed, PreferredProtection, cancellationToken).ConfigureAwait(false);
        Mutate(f => f.Entries[Key(kind)] = entry);
        Changed?.Invoke(this, kind);
    }

    /// <summary>
    /// 守り方を変え、保存してある値をすべてその形で暗号化し直す。
    /// Windows Hello にするときは、作った鍵でもう一度復号できることを確かめてから書き換える（確かめのために確認が 2 回出る）。
    /// 読めない値があれば、何も書き換えずに SecretAccessException
    /// </summary>
    public async Task ChangeProtectionAsync(SecretProtection protection, CancellationToken cancellationToken = default)
    {
        if (protection == SecretProtection.DpapiLegacy) throw new ArgumentException("古い形には変えられない", nameof(protection));  // skip-tr（開発者向けの例外）
        if (protection == SecretProtection.WindowsHello && presence is null)
        {
            throw new SecretAccessException(Strings.Secret_HelloUnavailable);
        }
        var plains = new Dictionary<SecretKind, string>();
        foreach (var kind in Enum.GetValues<SecretKind>())
        {
            if (await GetAsync(kind, cancellationToken).ConfigureAwait(false) is { } v) plains[kind] = v;
        }
        if (protection == SecretProtection.WindowsHello)
        {
            await VerifyPresenceKeyAsync(cancellationToken).ConfigureAwait(false);
        }
        var sealedEntries = new Dictionary<string, Entry>();
        foreach (var (kind, plain) in plains)
        {
            sealedEntries[Key(kind)] = await SealAsync(kind, plain, protection, cancellationToken).ConfigureAwait(false);
        }
        Mutate(f =>
        {
            f.Preferred = protection;
            foreach (var (k, e) in sealedEntries) f.Entries[k] = e;
        });
        if (protection != SecretProtection.WindowsHello) Lock();
        foreach (var kind in plains.Keys) Changed?.Invoke(this, kind);
    }

    /// <summary>
    /// PR #19 までの settings.json の protectedApiKey（DPAPI・Base64）を、復号せずにそのまま Gemini の値として移す。
    /// すでに Gemini の値があれば移さない。移したら true（呼ぶ側で settings.json の値を消す。書けなければ消さない）
    /// </summary>
    public bool MigrateLegacy(string legacyProtectedApiKey)
    {
        if (string.IsNullOrWhiteSpace(legacyProtectedApiKey)) return false;
        if (Has(SecretKind.GeminiApiKey)) return true;
        string? hint = null;
        try
        {
            if (dpapi.Unprotect(Convert.FromBase64String(legacyProtectedApiKey), LegacyEntropy) is { } plain)
            {
                hint = HintOf(Encoding.UTF8.GetString(plain));
                CryptographicOperations.ZeroMemory(plain);
            }
        }
        catch (FormatException)
        {
            // 末尾が分からないだけで、値はそのまま移す
        }
        Mutate(f => f.Entries[Key(SecretKind.GeminiApiKey)] = new Entry
        {
            Protection = SecretProtection.DpapiLegacy,
            Data = legacyProtectedApiKey.Trim(),
            Hint = hint,
        });
        Changed?.Invoke(this, SecretKind.GeminiApiKey);
        return true;
    }

    /// <summary>メモリに置いた Windows Hello の鍵を忘れる（画面のロック・スリープのとき。次に使うときにまた確認する）</summary>
    public void Lock()
    {
        lock (gate)
        {
            if (presenceKey is not null) CryptographicOperations.ZeroMemory(presenceKey);
            presenceKey = null;
        }
    }

    /// <summary>末尾 4 文字（画面に出してよい分）。短いキーなら出さない</summary>
    public static string? HintOf(string value) => value.Length >= 12 ? value[^4..] : null;

    // MARK: - 中身

    private async Task<Entry> SealAsync(SecretKind kind, string plain, SecretProtection protection, CancellationToken cancellationToken)
    {
        var bytes = Encoding.UTF8.GetBytes(plain);
        try
        {
            var data = protection == SecretProtection.WindowsHello
                ? AesGcmBox.Seal(await PresenceKeyAsync(create: true, cancellationToken).ConfigureAwait(false), bytes, Aad(kind))
                : dpapi.Protect(bytes, Entropy(kind));
            return new Entry { Protection = protection == SecretProtection.DpapiLegacy ? SecretProtection.Dpapi : protection, Data = Convert.ToBase64String(data), Hint = HintOf(plain) };
        }
        finally
        {
            CryptographicOperations.ZeroMemory(bytes);
        }
    }

    private async Task<byte[]> PresenceKeyAsync(bool create, CancellationToken cancellationToken)
    {
        if (presence is null) throw new SecretAccessException(Strings.Secret_HelloUnavailableCannotRead);
        lock (gate)
        {
            if (presenceKey is not null) return presenceKey;
        }
        // 確認の画面を 2 つ同時に出さない
        await presenceLock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            lock (gate)
            {
                if (presenceKey is not null) return presenceKey;
            }
            var key = await presence.DeriveKeyAsync(create, cancellationToken).ConfigureAwait(false);
            if (key.Length != 32) throw new SecretAccessException(Strings.Secret_HelloKeyFailed);
            lock (gate) presenceKey = key;
            return key;
        }
        finally
        {
            presenceLock.Release();
        }
    }

    /// <summary>同じ鍵から同じ値が出ることを確かめる（出なければ、Hello で暗号化した値を次に読めない）</summary>
    private async Task VerifyPresenceKeyAsync(CancellationToken cancellationToken)
    {
        Lock();
        var first = (byte[])(await PresenceKeyAsync(create: true, cancellationToken).ConfigureAwait(false)).Clone();
        Lock();
        var second = await PresenceKeyAsync(create: false, cancellationToken).ConfigureAwait(false);
        var same = CryptographicOperations.FixedTimeEquals(first, second);
        CryptographicOperations.ZeroMemory(first);
        if (!same)
        {
            Lock();
            throw new SecretAccessException(Strings.Secret_HelloKeyMismatch);
        }
    }

    private static string Key(SecretKind kind) => kind switch
    {
        SecretKind.GeminiApiKey => "geminiApiKey",
        SecretKind.ClaudeApiKey => "claudeApiKey",
        _ => throw new ArgumentOutOfRangeException(nameof(kind)),
    };

    /// <summary>種類ごとに違うエントロピーにする（Gemini の値を Claude の値として読ませない）</summary>
    private static byte[] Entropy(SecretKind kind) => Encoding.UTF8.GetBytes($"Hanasu.Windows.Secret.v1.{Key(kind)}");

    private static byte[] Aad(SecretKind kind) => Encoding.UTF8.GetBytes($"Hanasu.Windows.Secret.v1.hello.{Key(kind)}");

    private SecretsFile Read()
    {
        if (!File.Exists(Path)) return new SecretsFile();
        try
        {
            return JsonSerializer.Deserialize<SecretsFile>(IO.SharedFile.ReadAllText(Path), JsonOptions) ?? new SecretsFile();
        }
        catch (JsonException)
        {
            // 壊れていても消さない（読めない値を勝手に捨てない）。退けてから空で始める
            try { File.Copy(Path, Path + ".broken", overwrite: true); } catch (IOException) { }
            return new SecretsFile();
        }
    }

    private void Mutate(Action<SecretsFile> mutate)
    {
        lock (gate)
        {
            var file = Read();
            mutate(file);
            var dir = System.IO.Path.GetDirectoryName(Path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            // 設計判断: DEC-COM-194
            IO.SharedFile.WriteAllTextAtomically(Path, JsonSerializer.Serialize(file, JsonOptions));
        }
    }

    private sealed class SecretsFile
    {
        public int Version { get; set; } = 1;
        public SecretProtection Preferred { get; set; } = SecretProtection.Dpapi;
        public Dictionary<string, Entry> Entries { get; set; } = new();
    }

    private sealed class Entry
    {
        public SecretProtection Protection { get; set; }
        /// <summary>暗号化した値（Base64）</summary>
        public string Data { get; set; } = "";
        /// <summary>末尾 4 文字（画面の表示用）</summary>
        public string? Hint { get; set; }
    }
}

/// <summary>AES-256-GCM。形は nonce（12）| 暗号文 | タグ（16）</summary>
internal static class AesGcmBox
{
    public static byte[] Seal(byte[] key, byte[] plaintext, byte[] aad)
    {
        var output = new byte[12 + plaintext.Length + 16];
        var nonce = output.AsSpan(0, 12);
        RandomNumberGenerator.Fill(nonce);
        using var aes = new AesGcm(key, 16);
        aes.Encrypt(nonce, plaintext, output.AsSpan(12, plaintext.Length), output.AsSpan(12 + plaintext.Length), aad);
        return output;
    }

    /// <summary>鍵が違う・壊れていれば null</summary>
    public static byte[]? Open(byte[] key, byte[] box, byte[] aad)
    {
        if (box.Length < 28) return null;
        var plain = new byte[box.Length - 28];
        try
        {
            using var aes = new AesGcm(key, 16);
            aes.Decrypt(box.AsSpan(0, 12), box.AsSpan(12, plain.Length), box.AsSpan(12 + plain.Length), plain, aad);
            return plain;
        }
        catch (CryptographicException)
        {
            return null;
        }
    }
}
