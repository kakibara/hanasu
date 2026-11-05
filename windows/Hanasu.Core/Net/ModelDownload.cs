using System.Security.Cryptography;

namespace Hanasu.Core;

/// <summary>ダウンロードしたモデルが、決めておいたものと違った（大きさかハッシュ）。</summary>
public sealed class ModelVerificationException(string message) : IOException(message);

/// <summary>
/// モデル（Whisper・話者分離）のダウンロード。決まった https のホストから取り、大きさと SHA-256 を確かめてから置く。
/// 1. 「.download」の名前に書く（途中のファイルは使わない）
/// 2. 書きながら SHA-256 を計算し、決めておいた値と比べる。違えば消して例外
/// 3. 合っていたら、本来の名前に変える
/// ファイル名はコードに書いた固定の名前だけを使う（応答から名前を取らないので、パスを辿られない）。
/// </summary>
// 要件: REQ-COM-022
// 設計判断: DEC-COM-146
public static class ModelDownload
{
    /// <summary>ダウンロードしてよいホスト（リダイレクトのあとの CDN は、ハッシュで確かめる）</summary>
    public static readonly IReadOnlySet<string> AllowedHosts = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "huggingface.co",
    };

    /// <param name="progress">受け取った量（バイト）と全体（分からなければ expectedBytes）</param>
    public static async Task DownloadVerifiedAsync(HttpClient http, Uri uri, string finalPath, string expectedSha256, long expectedBytes,
        Action<long, long>? progress, CancellationToken cancellationToken)
    {
        if (uri.Scheme != Uri.UriSchemeHttps || !AllowedHosts.Contains(uri.Host))
        {
            throw new ModelVerificationException(string.Format(Strings.Download_HostNotAllowed, uri.Host));
        }
        var partial = finalPath + ".download";
        try
        {
            using var response = await http.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead, cancellationToken).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                throw new HttpRequestException(string.Format(Strings.Download_HttpFailed, (int)response.StatusCode));
            }
            if (response.RequestMessage?.RequestUri is { } final && final.Scheme != Uri.UriSchemeHttps)
            {
                throw new ModelVerificationException(Strings.Download_RedirectedToNonHttps);
            }
            var total = response.Content.Headers.ContentLength ?? expectedBytes;
            if (response.Content.Headers.ContentLength is long length && length != expectedBytes)
            {
                throw new ModelVerificationException(string.Format(Strings.Download_SizeMismatch, length, expectedBytes));
            }
            using var sha = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            long received = 0;
            await using (var source = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false))
            await using (var target = new FileStream(partial, FileMode.Create, FileAccess.Write, FileShare.None, 1 << 16, useAsync: true))
            {
                var buffer = new byte[1 << 16];
                int read;
                while ((read = await source.ReadAsync(buffer, cancellationToken).ConfigureAwait(false)) > 0)
                {
                    // 想定より大きいものを書き続けない（ディスクを埋められないように）
                    if (received + read > expectedBytes) throw new ModelVerificationException(Strings.Download_TooLarge);
                    await target.WriteAsync(buffer.AsMemory(0, read), cancellationToken).ConfigureAwait(false);
                    sha.AppendData(buffer, 0, read);
                    received += read;
                    progress?.Invoke(received, total);
                }
            }
            if (received != expectedBytes) throw new IOException(Strings.Download_Interrupted);
            var actual = Convert.ToHexString(sha.GetHashAndReset());
            if (!string.Equals(actual, expectedSha256, StringComparison.OrdinalIgnoreCase))
            {
                throw new ModelVerificationException(Strings.Download_HashMismatch);
            }
            File.Move(partial, finalPath, overwrite: true);
        }
        catch
        {
            TryDelete(partial);
            throw;
        }
    }

    /// <summary>置いてあるファイルの SHA-256 が合っているか（大きさを先に比べるので、違うものはすぐ分かる）</summary>
    public static bool Matches(string path, string expectedSha256, long expectedBytes)
    {
        var info = new FileInfo(path);
        if (!info.Exists || info.Length != expectedBytes) return false;
        using var stream = File.OpenRead(path);
        return string.Equals(Convert.ToHexString(SHA256.HashData(stream)), expectedSha256, StringComparison.OrdinalIgnoreCase);
    }

    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); } catch (IOException) { } catch (UnauthorizedAccessException) { }
    }
}
