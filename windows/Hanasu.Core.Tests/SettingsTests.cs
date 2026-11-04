using Hanasu.Core.Dictation;
using Hanasu.Core.Gemini;
using Hanasu.Core.Settings;

namespace Hanasu.Core.Tests;

public class SettingsTests
{
    [Fact]
    public void MissingFileGivesDefaults()
    {
        var store = new SettingsStore(Path.Combine(TestKeys.TempDirectory(), "settings.json"));
        var s = store.Load();
        Assert.Equal(HotKeyCombo.DefaultDictation, s.HotKey);
        Assert.Equal(HotKeyCombo.DefaultTranslate, s.TranslateHotKey);
        Assert.Equal(TranscriptionEngine.Windows, s.Engine);
        Assert.Equal(RecordingMode.Toggle, s.RecordingMode);
        Assert.Equal("gemini-3.5-flash-lite", s.Model);
        Assert.True(s.RefineWithGemini);
        Assert.True(s.SendAppName);
        // 貼り付けられないときは、クリップボードにも入れておく（DEC-DIC-122）
        Assert.Equal(PasteFallbackClipboard.KeepResult, s.PasteFallbackClipboard);
        // 整形の言語は、話した言語（REQ-DIC-082）
        Assert.Equal(RefineOutputLanguage.AsSpoken, s.RefineOutputLanguage);
    }

    // 確かめ方: REQ-DIC-082
    [Fact]
    public void RefineOutputLanguageIsSavedByName()
    {
        var path = Path.Combine(TestKeys.TempDirectory(), "settings.json");
        var store = new SettingsStore(path);
        store.Save(new AppSettings { RefineOutputLanguage = RefineOutputLanguage.Japanese });
        Assert.Contains("\"refineOutputLanguage\": \"Japanese\"", File.ReadAllText(path));
        Assert.Equal(RefineOutputLanguage.Japanese, store.Load().RefineOutputLanguage);
        // 前の版の settings.json（項目がない）は既定値になる
        File.WriteAllText(path, "{ \"playSounds\": true }");
        Assert.Equal(RefineOutputLanguage.AsSpoken, store.Load().RefineOutputLanguage);
    }

    // 確かめ方: REQ-DIC-013
    [Fact]
    public void TranslationLanguagesDefaultToEnglishAndAreSavedByName()
    {
        var path = Path.Combine(TestKeys.TempDirectory(), "settings.json");
        var store = new SettingsStore(path);
        // 既定は English だけ（今までの settings.json に項目がなくても）
        Assert.Equal([TranslationLanguage.English], store.Load().TranslationLanguages);
        File.WriteAllText(path, "{ \"playSounds\": true }");
        Assert.Equal([TranslationLanguage.English], store.Load().TranslationLanguages);

        store.Save(new AppSettings { TranslationLanguages = [TranslationLanguage.English, TranslationLanguage.Japanese] });
        Assert.Contains("\"Japanese\"", File.ReadAllText(path));
        var loaded = store.Load();
        Assert.Equal([TranslationLanguage.English, TranslationLanguage.Japanese], loaded.TranslationLanguages);
        Assert.Equal(TranslationLanguage.English, loaded.PrimaryTranslationLanguage);

        // 知らない値は捨て、並びをそろえ、空なら English に戻す（ファイル全体は読める）
        File.WriteAllText(path, "{ \"translationLanguages\": [\"Klingon\", \"Japanese\", \"English\", \"Japanese\", 7], \"playSounds\": false }");
        loaded = store.Load();
        Assert.Equal([TranslationLanguage.English, TranslationLanguage.Japanese], loaded.TranslationLanguages);
        Assert.False(loaded.PlaySounds);
        File.WriteAllText(path, "{ \"translationLanguages\": [] }");
        Assert.Equal([TranslationLanguage.English], store.Load().TranslationLanguages);
        File.WriteAllText(path, "{ \"translationLanguages\": [\"Japanese\"] }");
        Assert.Equal(TranslationLanguage.Japanese, store.Load().PrimaryTranslationLanguage);
    }

    [Fact]
    public void CloneCopiesTranslationLanguages()
    {
        var original = new AppSettings { TranslationLanguages = [TranslationLanguage.English] };
        var clone = original.Clone();
        clone.TranslationLanguages[0] = TranslationLanguage.Japanese;
        Assert.Equal(TranslationLanguage.English, original.TranslationLanguages[0]);
    }

    // 確かめ方: REQ-DIC-081
    [Fact]
    public void PasteFallbackClipboardIsSavedByName()
    {
        var path = Path.Combine(TestKeys.TempDirectory(), "settings.json");
        var store = new SettingsStore(path);
        store.Save(new AppSettings { PasteFallbackClipboard = PasteFallbackClipboard.RestoreOriginal });
        Assert.Contains("\"pasteFallbackClipboard\": \"RestoreOriginal\"", File.ReadAllText(path));
        Assert.Equal(PasteFallbackClipboard.RestoreOriginal, store.Load().PasteFallbackClipboard);
        // 前の版の settings.json（項目がない）は既定値になる
        File.WriteAllText(path, "{ \"playSounds\": true }");
        Assert.Equal(PasteFallbackClipboard.KeepResult, store.Load().PasteFallbackClipboard);
    }

    [Fact]
    public void SavesAndLoadsReadableJson()
    {
        var path = Path.Combine(TestKeys.TempDirectory(), "sub", "settings.json");
        var store = new SettingsStore(path);
        var s = new AppSettings
        {
            HotKey = new HotKeyCombo(HotKeyModifiers.Control | HotKeyModifiers.Shift, 0x44),
            RecordingMode = RecordingMode.PushToTalk,
            Engine = TranscriptionEngine.Whisper,
            WhisperModel = "large-v3-turbo-q5_0",
            DictionaryText = "ジェミニ => Gemini",
            MicrophoneDeviceId = "{0.0.1.00000000}.{abc}",
        };
        store.Save(s);
        var json = File.ReadAllText(path);
        Assert.Contains("\"engine\": \"Whisper\"", json);
        Assert.Contains("\"recordingMode\": \"PushToTalk\"", json);
        Assert.Contains("ジェミニ => Gemini", json);  // 日本語をエスケープしない

        var loaded = store.Load();
        Assert.Equal(s.HotKey, loaded.HotKey);
        Assert.Equal(RecordingMode.PushToTalk, loaded.RecordingMode);
        Assert.Equal(TranscriptionEngine.Whisper, loaded.Engine);
        Assert.Equal("large-v3-turbo-q5_0", loaded.WhisperModel);
        Assert.Equal(s.MicrophoneDeviceId, loaded.MicrophoneDeviceId);
    }

    [Fact]
    public void BrokenFileIsKeptAsideAndDefaultsAreUsed()
    {
        var path = Path.Combine(TestKeys.TempDirectory(), "settings.json");
        File.WriteAllText(path, "{ this is not json");
        var s = new SettingsStore(path).Load();
        Assert.Equal(HotKeyCombo.DefaultDictation, s.HotKey);
        Assert.True(File.Exists(path + ".broken"));
    }

    [Fact]
    public void InvalidValuesAreNormalized()
    {
        var path = Path.Combine(TestKeys.TempDirectory(), "settings.json");
        File.WriteAllText(path, """
            {
              "hotKey": { "modifiers": "None", "virtualKey": 65 },
              "translateHotKey": { "modifiers": "Alt", "virtualKey": 32 },
              "whisperModel": "no-such-model",
              "model": "",
              "unknownKey": 1,
            }
            """);
        var s = new SettingsStore(path).Load();
        Assert.Equal(HotKeyCombo.DefaultDictation, s.HotKey);
        Assert.Equal(HotKeyCombo.DefaultTranslate, s.TranslateHotKey);
        Assert.Equal("small", s.WhisperModel);
        Assert.Equal("gemini-3.5-flash-lite", s.Model);
    }

    [Fact]
    public async Task ApiKeyIsStoredOutsideSettings()
    {
        var dir = TestKeys.TempDirectory();
        var path = Path.Combine(dir, "settings.json");
        var secrets = TestKeys.Secrets(dir);
        var service = new SettingsService(new SettingsStore(path), secrets);

        await secrets.SetAsync(SecretKind.GeminiApiKey, "  AIza-secret-0123456789  ");
        service.Update(s => s.Model = "gemini-3.8-flash");
        Assert.DoesNotContain("AIza-secret", File.ReadAllText(path));
        Assert.DoesNotContain("AIza-secret", File.ReadAllText(secrets.Path));
        Assert.Equal("AIza-secret-0123456789", await secrets.GetAsync(SecretKind.GeminiApiKey));

        var auth = GeminiAuthResolver.Resolve(service.Current, secrets);
        Assert.IsType<GeminiAuth.StoredApiKey>(auth);
        Assert.DoesNotContain("AIza", auth!.ToString());

        await secrets.SetAsync(SecretKind.GeminiApiKey, "");
        Assert.Null(await secrets.GetAsync(SecretKind.GeminiApiKey));
        Assert.Null(GeminiAuthResolver.Resolve(service.Current, secrets));
    }

    [Fact]
    public void CurrentIsACopy()
    {
        var service = new SettingsService(new SettingsStore(Path.Combine(TestKeys.TempDirectory(), "s.json")), TestKeys.Secrets());
        var copy = service.Current;
        copy.Model = "changed";
        Assert.NotEqual("changed", service.Current.Model);
        service.Update(s => s.Model = "gemini-3.8-flash");
        Assert.Equal("gemini-3.8-flash", service.Current.Model);
    }

    [Fact]
    public void ServiceAccountModeNeedsAPath()
    {
        var s = new AppSettings { AuthMode = GeminiAuthMode.ServiceAccount, ServiceAccountPath = "" };
        Assert.Null(GeminiAuthResolver.Resolve(s, TestKeys.Secrets()));
        s.ServiceAccountPath = Path.Combine(TestKeys.TempDirectory(), "missing.json");
        Assert.Throws<ServiceAccountException>(() => GeminiAuthResolver.Resolve(s, TestKeys.Secrets()));
    }
}

public class HotKeyTests
{
    [Fact]
    public void DefaultsAvoidWindowsShortcuts()
    {
        Assert.Null(HotKeyCombo.DefaultDictation.Validate());
        Assert.Null(HotKeyCombo.DefaultTranslate.Validate());
        Assert.Equal("Ctrl + Alt + Space", HotKeyCombo.DefaultDictation.DisplayString);
        Assert.Equal("Ctrl + Alt + Shift + Space", HotKeyCombo.DefaultTranslate.DisplayString);
    }

    [Theory]
    [InlineData(HotKeyModifiers.Alt, 0x20, "ウインドウメニュー")]
    [InlineData(HotKeyModifiers.Win, 0x48, "音声入力")]
    [InlineData(HotKeyModifiers.None, 0x41, "組み合わせて")]
    [InlineData(HotKeyModifiers.Shift, 0x41, "Shift だけ")]
    [InlineData(HotKeyModifiers.Control, 0x1B, "Esc")]
    [InlineData(HotKeyModifiers.Control, 0x11, "キーを 1 つ")]
    public void RejectsUnusableCombos(HotKeyModifiers modifiers, int vk, string reason)
    {
        Assert.Contains(reason, new HotKeyCombo(modifiers, vk).Validate());
    }

    [Fact]
    public void FunctionKeysMayStandAlone()
    {
        Assert.Null(new HotKeyCombo(HotKeyModifiers.None, 0x7B).Validate());  // F12
        Assert.Equal("F12", KeyNames.Name(0x7B));
        Assert.Equal("Ctrl + Win + D", new HotKeyCombo(HotKeyModifiers.Control | HotKeyModifiers.Win, 0x44).DisplayString);
    }
}
