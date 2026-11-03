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
    public void ApiKeyIsStoredProtected()
    {
        var path = Path.Combine(TestKeys.TempDirectory(), "settings.json");
        var service = new SettingsService(new SettingsStore(path), new ReversingProtector());
        SettingsChangedEventArgs? changed = null;
        service.Changed += (_, e) => changed = e;

        service.SetApiKey("  AIza-secret  ");
        Assert.DoesNotContain("AIza-secret", File.ReadAllText(path));
        Assert.Equal("AIza-secret", service.LoadApiKey());
        Assert.NotNull(changed);
        Assert.Equal("", changed!.Before.ProtectedApiKey);

        var auth = GeminiAuthResolver.Resolve(service.Current, service.Protector);
        Assert.Equal("AIza-secret", Assert.IsType<GeminiAuth.ApiKey>(auth).Key);
        Assert.DoesNotContain("AIza", auth!.ToString());

        service.SetApiKey("");
        Assert.Null(service.LoadApiKey());
        Assert.Null(GeminiAuthResolver.Resolve(service.Current, service.Protector));
    }

    [Fact]
    public void CurrentIsACopy()
    {
        var service = new SettingsService(new SettingsStore(Path.Combine(TestKeys.TempDirectory(), "s.json")), new ReversingProtector());
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
        Assert.Null(GeminiAuthResolver.Resolve(s, new ReversingProtector()));
        s.ServiceAccountPath = Path.Combine(TestKeys.TempDirectory(), "missing.json");
        Assert.Throws<ServiceAccountException>(() => GeminiAuthResolver.Resolve(s, new ReversingProtector()));
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
