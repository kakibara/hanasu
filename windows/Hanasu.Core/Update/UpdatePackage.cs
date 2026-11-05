using System.IO.Compression;

namespace Hanasu.Core.Update;

/// <summary>
/// ダウンロードした zip を、作業用のフォルダに展開する。どの項目も、展開先のフォルダの中に収まることを確かめる
/// （「..」や絶対パスで外に書かれないように）。zip の中は、最上位の Hanasu フォルダの下に Hanasu.exe がある形。
/// </summary>
// 設計判断: DEC-REL-030
public static class UpdatePackage
{
    public const string RootFolderName = "Hanasu";
    public const string ExecutableName = "Hanasu.exe";
    /// <summary>展開したあとの大きさの上限（zip 爆弾を避ける）</summary>
    public const long MaxExtractedBytes = 4L * 1024 * 1024 * 1024;

    /// <summary>
    /// 入れ替えで消してよいか確かめる。今のインストール先の最上位の項目（ファイル・フォルダ）のうち、
    /// 新しい版の最上位に無く、古い版が置いたかもしれない .dll / .pdb のファイルでもないものの名前を返す（空なら入れ替えてよい）。
    /// 入れ替えは今のフォルダごと取り替えて消すので、Desktop や C:\Tools のように Hanasu 専用でないフォルダでは、利用者のほかのファイルが消える
    /// </summary>
    public static IReadOnlyList<string> FindForeignEntries(string installDir, string stagedDir)
    {
        var known = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var path in Directory.EnumerateFileSystemEntries(stagedDir)) known.Add(Path.GetFileName(path));
        var foreign = new List<string>();
        foreach (var path in Directory.EnumerateFileSystemEntries(installDir))
        {
            var name = Path.GetFileName(path);
            if (known.Contains(name)) continue;
            var isFile = File.Exists(path) && !Directory.Exists(path);
            var extension = Path.GetExtension(name);
            if (isFile && (extension.Equals(".dll", StringComparison.OrdinalIgnoreCase) || extension.Equals(".pdb", StringComparison.OrdinalIgnoreCase))) continue;
            foreign.Add(name);
        }
        foreign.Sort(StringComparer.OrdinalIgnoreCase);
        return foreign;
    }

    /// <summary>展開して、新しい Hanasu のフォルダ（stagingDirectory\Hanasu）を返す。形が違えば UpdateException</summary>
    public static string Extract(string zipPath, string stagingDirectory)
    {
        var root = Path.GetFullPath(stagingDirectory);
        var rootWithSeparator = root.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        Directory.CreateDirectory(root);
        try
        {
            using var archive = ZipFile.OpenRead(zipPath);
            long total = 0;
            foreach (var entry in archive.Entries)
            {
                var target = Path.GetFullPath(Path.Combine(root, entry.FullName));
                if (!target.StartsWith(rootWithSeparator, StringComparison.OrdinalIgnoreCase))
                {
                    throw new UpdateException($"zip の中に、展開先の外を指す項目があるので、使いません: {entry.FullName}");
                }
                total += entry.Length;
                if (total > MaxExtractedBytes) throw new UpdateException("zip を展開した大きさが想定より大きいので、使いません");
                if (entry.FullName.EndsWith('/') || entry.FullName.EndsWith('\\'))
                {
                    Directory.CreateDirectory(target);
                    continue;
                }
                Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                entry.ExtractToFile(target, overwrite: true);
            }
        }
        catch (InvalidDataException e)
        {
            throw new UpdateException("ダウンロードした zip を開けませんでした", e);
        }
        var staged = Path.Combine(root, RootFolderName);
        if (!File.Exists(Path.Combine(staged, ExecutableName)))
        {
            throw new UpdateException($"zip の中に {RootFolderName}\\{ExecutableName} がないので、使いません");
        }
        return staged;
    }
}
