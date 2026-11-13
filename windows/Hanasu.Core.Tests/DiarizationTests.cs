using System.Runtime.InteropServices;
using Hanasu.Core.Properties;
using Hanasu.Diarization;

namespace Hanasu.Core.Tests;

/// <summary>
/// sherpa-onnx のネイティブ ライブラリを実際に読むテスト（Windows の CI では win-x64 の DLL、Mac では osx-arm64 の dylib）
/// </summary>
public class DiarizationTests
{
    // 設計判断: DEC-MTG-104
    // 版を上げて sherpa-onnx の private のフィールドの名前が変わったら、NULL の確かめが効かなくなる（落ちはせず、いつも「相手」1 人になる）ので、ここで気づく
    [Fact]
    public void SherpaHandleFieldExists()
    {
        Assert.NotNull(SherpaSpeakerDiarizer.HandleField);
        Assert.Equal(typeof(HandleRef), SherpaSpeakerDiarizer.HandleField!.FieldType);
    }

    // 設計判断: DEC-MTG-104
    // モデルを読めないと C の API は NULL を返す。そのまま SampleRate を呼ぶとプロセスが落ちるので、例外になることを確かめる
    [Fact]
    public async Task BrokenModelsThrowInsteadOfCrashing()
    {
        var dir = TestKeys.TempDirectory();
        Directory.CreateDirectory(dir);
        foreach (var model in DiarizationModels.All)
        {
            // IsReady が真になる大きさにして、ダウンロードに行かないようにする（中身はゼロで、ONNX としては読めない）
            using var file = File.Create(Path.Combine(dir, model.FileName));
            file.SetLength(model.Bytes);
        }
        var http = new HttpClient(new FakeHandler((_, _) => throw new InvalidOperationException("ダウンロードしてはいけない")));
        var models = new DiarizationModels(dir, http);
        Assert.True(models.IsReady);

        var error = await Assert.ThrowsAsync<InvalidOperationException>(() => new SherpaSpeakerDiarizer(models).DiarizeAsync(new float[16_000]));
        Assert.Equal(Strings.Diarization_CreateFailed, error.Message);
        var diagnostics = Assert.IsType<string>(error.Data[SherpaSpeakerDiarizer.DiagnosticsKey]);
        Assert.Contains("handleField=ok", diagnostics);
        Assert.Contains("exists=True", diagnostics);
    }

    [DllImport("sherpa-onnx-c-api", EntryPoint = "SherpaOnnxFileExists")]
    private static extern int SherpaOnnxFileExists([MarshalAs(UnmanagedType.LPUTF8Str)] string filename);

    // 設計判断: DEC-COM-206
    // sherpa-onnx は Windows でパスを UTF-8 として読む。アプリ（Hanasu.exe）は ANSI のコードページを UTF-8 にして、sherpa-onnx の C# の API の
    // LPStr（ANSI）でも UTF-8 が渡るようにしている。ここでは、UTF-8 で渡せば日本語の名前のフォルダのファイルを見つけることを確かめる
    [Fact]
    public void SherpaReadsUtf8Paths()
    {
        var dir = Path.Combine(TestKeys.TempDirectory(), "話者テスト");
        Directory.CreateDirectory(dir);
        var path = Path.Combine(dir, "モデル.onnx");
        File.WriteAllBytes(path, [0]);
        Assert.Equal(1, SherpaOnnxFileExists(path));
        Assert.Equal(0, SherpaOnnxFileExists(Path.Combine(dir, "ない.onnx")));
    }

    // 設計判断: DEC-COM-206
    [Fact]
    public void AppManifestUsesUtf8CodePage()
    {
        string? manifest = null;
        for (var d = new DirectoryInfo(AppContext.BaseDirectory); d is not null && manifest is null; d = d.Parent)
        {
            var candidate = Path.Combine(d.FullName, "windows", "Hanasu.Windows", "app.manifest");
            if (File.Exists(candidate)) manifest = candidate;
        }
        Assert.NotNull(manifest);
        var xml = System.Xml.Linq.XDocument.Load(manifest!);
        var codePage = xml.Descendants().Single(e => e.Name.LocalName == "activeCodePage");
        Assert.Equal("http://schemas.microsoft.com/SMI/2019/WindowsSettings", codePage.Name.NamespaceName);
        Assert.Equal("UTF-8", codePage.Value.Trim());
    }
}
