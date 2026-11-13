using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Xml;
using Hanasu.Core.Ai;
using Hanasu.Core.LocalLlm;
using Hanasu.Core.Text;

namespace Hanasu.Core.Dictation;

// 文章から文体を学ぶ（REQ-DIC-022）。ファイルの読み込み（StyleSourceReader・DocxText）と、AI に文体のルールを書き出させる処理（StyleLearner）。
// Mac 版は Sources/Hanasu/StyleLearning.swift（同じ規則。共有の固定のファイル common/testdata/style/ で確かめる）。

// MARK: - ファイルの読み込み

/// <summary>読めなかった理由（common/testdata/style/cases.json の error と同じ名前）</summary>
public enum StyleSourceError
{
    /// <summary>扱わない拡張子</summary>
    Unsupported,
    /// <summary>壊れている・文字コードが分からない</summary>
    Unreadable,
    /// <summary>大きすぎる（ファイルが 20 MB より大きい・展開すると 50 MB を超える）</summary>
    TooLarge,
}

/// <summary>文体を学ぶ材料のファイルを読めなかった。Message はそのまま画面に出せる</summary>
public sealed class StyleSourceException(StyleSourceError error, Exception? inner = null) : Exception(MessageFor(error), inner)
{
    public StyleSourceError Error { get; } = error;

    /// <summary>cases.json の error と同じ名前（unsupported・unreadable・tooLarge）</summary>
    public string Code => Error switch
    {
        StyleSourceError.Unsupported => "unsupported",
        StyleSourceError.TooLarge => "tooLarge",
        _ => "unreadable",
    };

    public static string MessageFor(StyleSourceError error) => error switch
    {
        StyleSourceError.Unsupported => Strings.StyleSource_Unsupported,
        StyleSourceError.TooLarge => Strings.StyleSource_TooLarge,
        _ => Strings.StyleSource_Unreadable,
    };
}

// 要件: REQ-DIC-022
// 設計判断: DEC-DIC-211
/// <summary>
/// 文体を学ぶ材料のファイルを、本文の文字列にする（Mac 版の StyleSourceReader と同じ規則）。改行は LF にそろえ、前後の空白は取らない。
/// 読めなければ StyleSourceException
/// </summary>
public static class StyleSourceReader
{
    public static readonly IReadOnlyList<string> Extensions = [".docx", ".txt", ".md", ".markdown"];
    public const long MaxFileBytes = 20 * 1024 * 1024;

    /// <summary>ファイルを選ぶダイアログの絞り込み（*.docx;*.txt;*.md;*.markdown）</summary>
    public static string FilePattern => string.Join(";", Extensions.Select(e => "*" + e));

    public static string Read(string path)
    {
        var ext = Path.GetExtension(path).ToLowerInvariant();
        if (!Extensions.Contains(ext)) throw new StyleSourceException(StyleSourceError.Unsupported);
        byte[] data;
        try
        {
            if (new FileInfo(path).Length > MaxFileBytes) throw new StyleSourceException(StyleSourceError.TooLarge);
            data = File.ReadAllBytes(path);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            throw new StyleSourceException(StyleSourceError.Unreadable, e);
        }
        if (ext == ".docx") return DocxText.Read(data);
        return NormalizeNewlines(DecodeText(data) ?? throw new StyleSourceException(StyleSourceError.Unreadable));
    }

    // 設計判断: DEC-DIC-211
    /// <summary>
    /// BOM で UTF-8・UTF-16（LE・BE）を見分け、BOM がなければ UTF-8、UTF-8 として正しくなければ Shift_JIS（CP932）で読む。
    /// CP932 はアプリの起動で登録していないので、CodePagesEncodingProvider から直接取る。読めなければ null
    /// </summary>
    public static string? DecodeText(byte[] data)
    {
        try
        {
            if (data.AsSpan().StartsWith((ReadOnlySpan<byte>)[0xEF, 0xBB, 0xBF])) return new UTF8Encoding(false, true).GetString(data, 3, data.Length - 3);
            if (data.AsSpan().StartsWith((ReadOnlySpan<byte>)[0xFF, 0xFE])) return new UnicodeEncoding(false, false, true).GetString(data, 2, data.Length - 2);
            if (data.AsSpan().StartsWith((ReadOnlySpan<byte>)[0xFE, 0xFF])) return new UnicodeEncoding(true, false, true).GetString(data, 2, data.Length - 2);
        }
        catch (DecoderFallbackException)
        {
            return null;
        }
        try
        {
            return new UTF8Encoding(false, true).GetString(data);
        }
        catch (DecoderFallbackException)
        {
            var cp932 = CodePagesEncodingProvider.Instance.GetEncoding(932);
            return cp932?.GetString(data);
        }
    }

    public static string NormalizeNewlines(string text) => text.Replace("\r\n", "\n").Replace('\r', '\n');
}

// 要件: REQ-DIC-022
// 設計判断: DEC-DIC-211
/// <summary>
/// .docx の本文（word/document.xml）を読む（Mac 版の DocxText と同じ規則）。段落（w:p）を改行、w:t を文字、w:tab をタブ、
/// w:br・w:cr を改行にする。表のセルも段落として読む。番号・画像・脚注・コメント・ヘッダーとフッター・消した文字（w:delText）・
/// フィールドのコード（w:instrText）は読まない。段落の書式（w:pPr。タブ位置の w:tab を含む）と、消した部分（w:del）は飛ばす
/// </summary>
public static class DocxText
{
    public const long MaxDocumentBytes = 50 * 1024 * 1024;
    public const string DocumentPath = "word/document.xml";
    private const string Namespace = "http://schemas.openxmlformats.org/wordprocessingml/2006/main";

    public static string Read(byte[] data)
    {
        byte[] xml;
        try
        {
            using var zip = new ZipArchive(new MemoryStream(data, writable: false), ZipArchiveMode.Read);
            var entry = zip.GetEntry(DocumentPath) ?? throw new StyleSourceException(StyleSourceError.Unreadable);
            if (entry.Length > MaxDocumentBytes) throw new StyleSourceException(StyleSourceError.TooLarge);
            using var stream = entry.Open();
            using var buffer = new MemoryStream();
            // 中央ディレクトリの大きさが偽りでも、上限を超えたら読むのをやめる
            var chunk = new byte[81920];
            int read;
            while ((read = stream.Read(chunk, 0, chunk.Length)) > 0)
            {
                if (buffer.Length + read > MaxDocumentBytes) throw new StyleSourceException(StyleSourceError.TooLarge);
                buffer.Write(chunk, 0, read);
            }
            xml = buffer.ToArray();
        }
        catch (Exception e) when (e is InvalidDataException or IOException or NotSupportedException)
        {
            throw new StyleSourceException(StyleSourceError.Unreadable, e);
        }
        return Parse(xml);
    }

    public static string Parse(byte[] xml)
    {
        var settings = new XmlReaderSettings
        {
            // DTD は読まない（実体の展開で大きくなるのを防ぐ。あれば読めないものにする）
            DtdProcessing = DtdProcessing.Prohibit,
            XmlResolver = null,
            IgnoreComments = true,
            IgnoreProcessingInstructions = true,
        };
        var paragraphs = new List<string>();
        // 段落の中に段落（テキストボックス）があっても、閉じた順に段落にする（Mac 版と同じ）
        var open = new List<StringBuilder>();
        var inText = false;
        void Append(string text)
        {
            if (open.Count > 0) open[^1].Append(text);
        }
        try
        {
            using var reader = XmlReader.Create(new MemoryStream(xml, writable: false), settings);
            while (!reader.EOF)
            {
                if (reader.NodeType == XmlNodeType.Element && reader.NamespaceURI == Namespace)
                {
                    switch (reader.LocalName)
                    {
                        case "pPr" or "rPr" or "del":
                            reader.Skip();
                            continue;
                        case "p":
                            if (reader.IsEmptyElement) paragraphs.Add("");
                            else open.Add(new StringBuilder());
                            break;
                        case "t":
                            inText = !reader.IsEmptyElement;
                            break;
                        case "tab":
                            Append("\t");
                            break;
                        case "br" or "cr":
                            Append("\n");
                            break;
                    }
                }
                else if (reader.NodeType == XmlNodeType.EndElement && reader.NamespaceURI == Namespace)
                {
                    if (reader.LocalName == "p" && open.Count > 0)
                    {
                        paragraphs.Add(open[^1].ToString());
                        open.RemoveAt(open.Count - 1);
                    }
                    else if (reader.LocalName == "t")
                    {
                        inText = false;
                    }
                }
                else if (inText && reader.NodeType is XmlNodeType.Text or XmlNodeType.CDATA or XmlNodeType.Whitespace or XmlNodeType.SignificantWhitespace)
                {
                    Append(reader.Value);
                }
                reader.Read();
            }
        }
        catch (XmlException e)
        {
            throw new StyleSourceException(StyleSourceError.Unreadable, e);
        }
        return string.Join("\n", paragraphs);
    }
}

// MARK: - 学ぶ

/// <summary>AI が書き出した文体</summary>
public sealed record LearnedStyle(string Name, PromptLanguage Language, IReadOnlyList<string> Rules);

/// <summary>文体を学べなかった。Message はそのまま画面に出せる</summary>
public sealed class StyleLearningException(string message, Exception? inner = null) : Exception(message, inner);

// 要件: REQ-DIC-022
// 設計判断: DEC-DIC-210, DEC-DIC-212
/// <summary>
/// 文章を「議事録」の AI に送り、文体のルール（12 個まで）・名前の案・文章の言語を書き出してもらう（Mac 版の StyleLearner と同じ）。
/// 文章は保存しない。AI のクライアントは呼ぶ側が設定の「議事録」の AI で作る（待ち時間は Timeout）
/// </summary>
public static class StyleLearner
{
    // 設計判断: DEC-DIC-212
    public const int MinimumCharacters = 100;
    /// <summary>Gemini・Claude に送る上限（字）</summary>
    public const int CharacterLimit = 30_000;
    /// <summary>入力欄に入れる上限（字）</summary>
    public const int InputLimit = 100_000;
    // 設計判断: DEC-DIC-210
    public const int MaxRules = 12;
    /// <summary>AI を待つ時間</summary>
    public static readonly TimeSpan Timeout = TimeSpan.FromSeconds(120);

    // 設計判断: DEC-DIC-212
    /// <summary>字数（Unicode のスカラー値。Mac の unicodeScalars.count と同じ）</summary>
    public static int Count(string text) => text.EnumerateRunes().Count();

    /// <summary>先頭から n 字（スカラー値）まで</summary>
    public static string Prefix(string text, int n)
    {
        var sb = new StringBuilder();
        var taken = 0;
        foreach (var rune in text.EnumerateRunes())
        {
            if (taken++ >= n) break;
            sb.Append(rune.ToString());
        }
        return sb.ToString();
    }

    /// <summary>対応する言語のコード（AI に返させる値。PromptLanguage.All の順）</summary>
    public static string LanguageCodes => string.Join(", ", PromptLanguage.All.Select(l => l.Code));

    // 要件: REQ-COM-061
    public static string Instruction => Prompts.Text("styleLearn.system", ("languages", LanguageCodes));

    public static string UserPrompt(string material) => Prompts.Text("styleLearn.user", ("material", material));

    // 設計判断: DEC-DIC-212
    /// <summary>
    /// 送る上限。Gemini・Claude は字数（30,000）、ローカルは文脈の長さから出力・指示・枠・余白を引いた見積もりのトークン数
    /// （DictionarySuggester.BudgetFor と同じ出し方。LongInputFitter に切られない量）
    /// </summary>
    public static DictionarySuggester.Budget Budget(ITextGenerator client)
    {
        if (client is not LocalLlmClient local) return new DictionarySuggester.Budget(false, CharacterLimit);
        var frame = DictionarySuggester.EstimateTokens(Instruction + UserPrompt("")) + LongInputFitter.Margin;
        return new DictionarySuggester.Budget(true, Math.Max(0, local.Model.ContextLength - local.Model.MaxOutputTokens(longOutput: true) - frame));
    }

    /// <summary>送る材料（前後の空白を除き、上限までを先頭から）。TotalCharacters は入力した字数（前後の空白を除く）</summary>
    public sealed record MaterialText(string Text, int TotalCharacters)
    {
        public int UsedCharacters => Count(Text);
        public bool Truncated => UsedCharacters < TotalCharacters;
    }

    // 設計判断: DEC-DIC-212
    public static MaterialText Material(string text, DictionarySuggester.Budget budget)
    {
        var trimmed = text.Trim();
        var total = Count(trimmed);
        if (!budget.IsTokens) return new MaterialText(total <= budget.Limit ? trimmed : Prefix(trimmed, budget.Limit), total);
        if (DictionarySuggester.EstimateTokens(trimmed) <= budget.Limit) return new MaterialText(trimmed, total);
        // 入る長さを二分探索で探す（見積もりは長さに対して増えていく）
        int low = 0, high = total;
        while (low < high)
        {
            var middle = (low + high + 1) / 2;
            if (DictionarySuggester.EstimateTokens(Prefix(trimmed, middle)) <= budget.Limit) low = middle;
            else high = middle - 1;
        }
        return new MaterialText(Prefix(trimmed, low), total);
    }

    // 設計判断: DEC-DIC-210
    /// <summary>AI の答え（JSON）を読む。コードブロックで囲まれていても読めるよう、最初の { から最後の } までを使う</summary>
    public static LearnedStyle Parse(string text)
    {
        var start = text.IndexOf('{');
        var end = text.LastIndexOf('}');
        if (start < 0 || end <= start) throw new StyleLearningException(Strings.StyleLearn_InvalidResponse);
        string name, code;
        List<string> rules;
        try
        {
            using var document = JsonDocument.Parse(text[start..(end + 1)]);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object) throw new StyleLearningException(Strings.StyleLearn_InvalidResponse);
            name = OptionalString(root, "name");
            code = OptionalString(root, "language").Trim();
            rules = [];
            if (root.TryGetProperty("rules", out var array) && array.ValueKind != JsonValueKind.Null)
            {
                if (array.ValueKind != JsonValueKind.Array) throw new StyleLearningException(Strings.StyleLearn_InvalidResponse);
                foreach (var item in array.EnumerateArray())
                {
                    if (item.ValueKind != JsonValueKind.String) throw new StyleLearningException(Strings.StyleLearn_InvalidResponse);
                    rules.Add(item.GetString()!);
                }
            }
        }
        catch (JsonException e)
        {
            throw new StyleLearningException(Strings.StyleLearn_InvalidResponse, e);
        }
        var cleaned = rules.Select(r => r.Trim()).Where(r => r.Length > 0).Take(MaxRules).ToList();
        if (cleaned.Count == 0) throw new StyleLearningException(Strings.StyleLearn_InvalidResponse);
        var language = PromptLanguage.FromCode(code) ?? throw new StyleLearningException(string.Format(Strings.StyleLearn_UnknownLanguage, code));
        return new LearnedStyle(name.Trim(), language, cleaned);
    }

    private static string OptionalString(JsonElement root, string key)
    {
        if (!root.TryGetProperty(key, out var value) || value.ValueKind == JsonValueKind.Null) return "";
        if (value.ValueKind != JsonValueKind.String) throw new StyleLearningException(Strings.StyleLearn_InvalidResponse);
        return value.GetString()!;
    }

    // 要件: REQ-DIC-022
    // 設計判断: DEC-DIC-210
    /// <summary>学ぶ。材料の区切りのタグは無害にしてから &lt;material&gt; に入れる。100 字未満なら送らずに失敗する</summary>
    public static async Task<LearnedStyle> LearnAsync(string text, ITextGenerator client, string model, CancellationToken cancellationToken = default)
    {
        var material = Material(text, Budget(client));
        if (material.TotalCharacters < MinimumCharacters)
        {
            throw new StyleLearningException(string.Format(Strings.StyleLearn_TooShort, MinimumCharacters));
        }
        var answer = await client.GenerateTextAsync(TextPurpose.Minutes, Instruction,
            UserPrompt(PromptText.NeutralizeDelimiters(material.Text)), model, cancellationToken).ConfigureAwait(false);
        return Parse(answer);
    }
}
