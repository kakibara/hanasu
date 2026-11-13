using Hanasu.Core.Ai;
using Hanasu.Core.LocalLlm;
using Hanasu.Core.Settings;

namespace Hanasu.Core.Dictation;

// 要件: REQ-COM-033
// 設計判断: DEC-DIC-220
/// <summary>
/// 音声入力の録音中に、ローカルのモデルを先に読み込むか（Mac 版の DictationController.prewarmLocalModelIfNeeded と同じ判定）。
/// この録音で AI を使い（整形がオンか翻訳する）、音声入力の AI がローカルで、そのモデルがダウンロード済みなら、そのモデルを返す
/// </summary>
public static class DictationPrewarm
{
    public static LocalLlmModel? ModelToPrewarm(AppSettings settings, DictationMode mode, Func<LocalLlmModel, bool> isDownloaded)
    {
        if (!DictationTextProcessor.UsesGemini(settings, mode)) return null;
        if (TextAiFactory.ProviderFor(settings, TextAiUse.Dictation) != TextAiProvider.Local) return null;
        var model = TextAiFactory.LocalModelFor(settings, TextAiUse.Dictation);
        // モデルがなければ読み込まない（止めたあとの整形が、設定でダウンロードするよう知らせる）
        return isDownloaded(model) ? model : null;
    }
}
