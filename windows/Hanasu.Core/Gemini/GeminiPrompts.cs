using System.Text;
using Hanasu.Core.Settings;
using Hanasu.Core.Text;

namespace Hanasu.Core.Gemini;

/// <summary>音声入力の整形・翻訳に渡す内容。Mac 版の GeminiClient.Request にあたる。</summary>
public sealed record RefineRequest
{
    public required string Transcript { get; init; }
    public required string Model { get; init; }
    /// <summary>入力先アプリ名。null なら送らない</summary>
    public string? AppName { get; init; }
    /// <summary>ユーザー辞書の正しい表記の一覧</summary>
    public IReadOnlyList<string> Dictionary { get; init; } = Array.Empty<string>();
    /// <summary>追加の整形ルール（設定の「辞書・ルール」）</summary>
    public string ExtraInstructions { get; init; } = "";
    /// <summary>ユーザー辞書の置き換えルール（認識結果には先に当ててあるが、近い音の語も直せるよう Gemini にも渡す）</summary>
    public IReadOnlyList<UserDictionary.Rule> DictionaryRules { get; init; } = Array.Empty<UserDictionary.Rule>();
    // 要件: REQ-DIC-082
    /// <summary>整形の出力の言語（翻訳では使わない）</summary>
    public RefineOutputLanguage OutputLanguage { get; init; } = RefineOutputLanguage.AsSpoken;
    // 要件: REQ-DIC-020, REQ-DIC-023, REQ-DIC-160
    /// <summary>入力先アプリの文体（音声入力は設定の「アプリ別」から、hanasu refine は --app・--style から。なければ null）</summary>
    public Dictation.AppStyle? AppStyle { get; init; }
}

/// <summary>
/// Gemini に渡す指示。文面は Mac 版と共有の言語ごとの JSON（Sources/Hanasu/Resources/Prompts/&lt;言語&gt;.json）から読む
/// （Ai.Prompts。Mac 版の GeminiClient.swift も同じキーを読むので、Mac と Windows で同じ文面になる）。
/// </summary>
public static class GeminiPrompts
{
    // 要件: REQ-DIC-082, REQ-COM-061
    // 設計判断: DEC-COM-102
    /// <summary>
    /// 整形のシステムプロンプト。Mac 版の GeminiClient.refinePrompt と同じ組み立て（systemInstruction に、選んだ
    /// 整形の言語の指示を 1 つ足したもの）。文面は refine.system と refine.outputLanguage.*（Mac 版と共有）。
    /// </summary>
    public static string SystemInstruction(RefineOutputLanguage language = RefineOutputLanguage.AsSpoken) =>
        BaseSystemInstruction + "\n\n" + LanguageInstruction(language);

    // 要件: REQ-COM-061
    /// <summary>整形の言語の指示。Mac 版の GeminiClient.RefineOutputLanguage.instruction と同じキー</summary>
    public static string LanguageInstruction(RefineOutputLanguage language) => language switch
    {
        RefineOutputLanguage.Unified => UnifiedLanguageInstruction,
        _ => AsSpokenLanguageInstruction,
    };

    /// <summary>話した言語のまま書かせる指示（refine.outputLanguage.asSpoken）</summary>
    public static string AsSpokenLanguageInstruction => Ai.Prompts.Text("refine.outputLanguage.asSpoken");

    // 設計判断: DEC-DIC-200
    /// <summary>プロンプトの言語に統一させる指示（refine.outputLanguage.unified。各言語の JSON に、その言語自身にそろえる文面がある）</summary>
    public static string UnifiedLanguageInstruction => Ai.Prompts.Text("refine.outputLanguage.unified");

    // 要件: REQ-COM-061
    /// <summary>整形の指示（refine.system。Mac 版の GeminiClient.systemInstruction と同じキー）</summary>
    public static string BaseSystemInstruction => Ai.Prompts.Text("refine.system");

    // 要件: REQ-COM-061
    /// <summary>英語に翻訳するときの指示（translate.english.system。Mac 版の GeminiClient.translationInstruction と同じキー）</summary>
    public static string TranslationInstruction => Ai.Prompts.Text("translate.english.system");

    // 要件: REQ-DIC-013, REQ-COM-061
    // 設計判断: DEC-DIC-028
    /// <summary>日本語に翻訳するときの指示（translate.japanese.system。Mac 版の GeminiClient.japaneseTranslationInstruction と同じキー）</summary>
    public static string JapaneseTranslationInstruction => Ai.Prompts.Text("translate.japanese.system");

    // 要件: REQ-DIC-013, REQ-COM-061
    // 設計判断: DEC-DIC-151
    /// <summary>
    /// 英語・日本語以外に翻訳するときの指示（translate.other.system。Mac 版と同じキー）。
    /// ${language} は翻訳の言語の名前を、プロンプトの言語で書いたもの（languageName.&lt;コード&gt;）
    /// </summary>
    public static string OtherTranslationInstruction(Dictation.TranslationLanguage language) =>
        Ai.Prompts.Text("translate.other.system", ("language", language.NameIn(Ai.PromptLanguage.Current)));

    // 設計判断: DEC-DIC-151
    /// <summary>翻訳の言語ごとの指示（英語と日本語は専用の指示、ほかの言語は共通の指示に言語の名前を埋める）</summary>
    public static string TranslationSystemInstruction(Dictation.TranslationLanguage language) =>
        language == Dictation.TranslationLanguage.English ? TranslationInstruction
        : language == Dictation.TranslationLanguage.Japanese ? JapaneseTranslationInstruction
        : OtherTranslationInstruction(language);

    /// <summary>
    /// 文字起こしのエンジンに Gemini を選んだときの指示（Windows 版で足したもの。transcribe.windows.system）。
    /// 整形は次の呼び出しで行うので、ここでは聞こえたとおりに書き起こすだけにさせる。
    /// </summary>
    public static string TranscriptionInstruction => TranscriptionInstructionFor(Ai.PromptLanguage.Current,
        Ai.PromptLanguage.Override is null ? Ai.PromptLanguage.SettingsLocaleIdentifier : null);

    // 要件: REQ-COM-061
    /// <summary>
    /// 文字起こしの指示。「主に〇〇で」の言語の名前は、文字起こしの言語をプロンプトの言語で書いたもの。
    /// 文字起こしの言語が対応言語にない（sv-SE など）ときは、英語と書かずに識別子のまま書く
    /// </summary>
    public static string TranscriptionInstructionFor(Ai.PromptLanguage language, string? localeIdentifier = null)
    {
        var name = localeIdentifier is null
            ? Ai.Prompts.Text("languageName." + language.Code, language)
            : Ai.PromptLanguage.SupportedOrNull(localeIdentifier) is { } spoken
                ? Ai.Prompts.Text("languageName." + spoken.Code, language)
                : localeIdentifier;
        return Ai.Prompts.Text("transcribe.windows.system", language, ("language", name));
    }

    /// <summary>思考の度合いはモデル名から決める（lite なら minimal、それ以外は low）</summary>
    public static string ThinkingLevel(string model) => model.Contains("lite", StringComparison.Ordinal) ? "minimal" : "low";

    /// <summary>整形・翻訳の user content。Mac 版の GeminiClient.userPrompt と同じ組み立て（画面の文脈は Windows 版にはない）</summary>
    /// <param name="translation">翻訳の言語（整形なら null）</param>
    public static string UserPrompt(RefineRequest request, Dictation.TranslationLanguage? translation = null)
    {
        // 要件: REQ-COM-061（文面は Mac 版の GeminiClient.userPrompt と同じキー）
        var language = Ai.PromptLanguage.Current;
        var lines = new List<string>();
        if (!string.IsNullOrEmpty(request.AppName))
        {
            lines.Add(Ai.Prompts.Text("user.appName", language, ("app", request.AppName)));
        }
        if (request.Dictionary.Count > 0)
        {
            lines.Add(Ai.Prompts.Text("user.dictionary", language, ("words", string.Join(", ", request.Dictionary))));
        }
        if (request.DictionaryRules.Count > 0)
        {
            var separator = Ai.Prompts.Text("user.dictionaryRuleSeparator", language);
            var rules = request.DictionaryRules.Select(r => $"- {string.Join(separator, r.Sources)} → {r.Target}");
            lines.Add(Ai.Prompts.Text("user.dictionaryRules", language) + "\n" + string.Join("\n", rules));
        }
        // 設計判断: DEC-DIC-023, DEC-DIC-028, DEC-DIC-151
        // 追加ルールは話す人の言語の文体向けなので、整形と、和訳（プロンプトの言語が日本語のとき）だけで使う。
        // ほかの言語への翻訳と、日本語以外で話す人の和訳では使わない（Mac 版の GeminiClient.translationPrompt と同じ）
        var extra = translation is { } target && !target.KeepsExtraRules ? "" : request.ExtraInstructions.Trim();
        if (extra.Length > 0)
        {
            lines.Add(Ai.Prompts.Text("user.extraRules", language) + "\n" + extra);
        }
        // 要件: REQ-DIC-020（Mac 版と同じく、追加ルールのあとに文体の節）
        if (request.AppStyle?.PromptSection(request.AppName, translation, extra.Length > 0) is { } section)
        {
            lines.Add(section);
        }
        // 文字起こしの中の区切りのタグは無害にしてから埋め込む（プロンプトインジェクションの対策。Windows 版で足した）
        lines.Add($"<transcript>\n{Ai.PromptText.NeutralizeDelimiters(request.Transcript)}\n</transcript>");
        return string.Join("\n", lines);
    }

    // 要件: REQ-COM-061
    /// <summary>音声の文字起こしに添える user content（音声そのものは別のパートで送る）。transcribe.dictionary と transcribe.windows.user</summary>
    public static string TranscriptionPrompt(IReadOnlyList<string> dictionary)
    {
        var language = Ai.PromptLanguage.Current;
        var sb = new StringBuilder();
        if (dictionary.Count > 0)
        {
            sb.Append(Ai.Prompts.Text("transcribe.dictionary", language, ("words", string.Join(", ", dictionary)))).Append('\n');
        }
        sb.Append(Ai.Prompts.Text("transcribe.windows.user", language));
        return sb.ToString();
    }
}
