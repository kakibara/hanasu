using Hanasu.Core.Ai;
using Hanasu.Core.Dictation;
using Hanasu.Core.LocalLlm;
using Hanasu.Core.Settings;

namespace Hanasu.Core.Tests;

/// <summary>音声入力の録音中に、ローカルのモデルを先に読み込むかの判定（DEC-DIC-220）</summary>
// 確かめ方: REQ-COM-033
public class DictationPrewarmTests
{
    private static AppSettings Local(bool refine = true) => new()
    {
        DictationAi = TextAiProvider.Local,
        LocalDictationModel = LocalLlmModel.Lfm25JP.Id,
        RefineWithGemini = refine,
    };

    [Fact]
    public void LocalAiWithRefiningPrewarmsTheChosenModel() =>
        Assert.Equal(LocalLlmModel.Lfm25JP, DictationPrewarm.ModelToPrewarm(Local(), DictationMode.Refine, _ => true));

    [Fact]
    public void RefiningOffPrewarmsOnlyWhenTranslating()
    {
        Assert.Null(DictationPrewarm.ModelToPrewarm(Local(refine: false), DictationMode.Refine, _ => true));
        Assert.Equal(LocalLlmModel.Lfm25JP, DictationPrewarm.ModelToPrewarm(Local(refine: false), DictationMode.TranslateToEnglish, _ => true));
    }

    [Fact]
    public void OtherAisDoNotPrewarm()
    {
        var settings = Local();
        settings.DictationAi = TextAiProvider.Gemini;
        Assert.Null(DictationPrewarm.ModelToPrewarm(settings, DictationMode.Refine, _ => true));
    }

    [Fact]
    public void MissingModelIsNotPrewarmed() =>
        Assert.Null(DictationPrewarm.ModelToPrewarm(Local(), DictationMode.Refine, _ => false));
}
