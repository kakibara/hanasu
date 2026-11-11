using System.Text.Json.Nodes;
using Hanasu.Core.Ai;
using Hanasu.Core.Dictation;

namespace Hanasu.Core.Command;

// 要件: REQ-COM-189, REQ-COM-193, REQ-DIC-160
// 設計判断: DEC-COM-187, DEC-COM-191, DEC-DIC-190
/// <summary>
/// Mac 版と共有するファイル（Sources/Hanasu/Resources/Command/hanasu.json）。MCP の英語の文・エージェントへの説明・既定の文体の一覧。
/// ${device} は this PC を入れる（CommandContext.Device）
/// </summary>
public static class SharedText
{
    private static readonly Lazy<JsonObject> Data = new(() =>
    {
        using var stream = typeof(SharedText).Assembly.GetManifestResourceStream("Hanasu.Command.hanasu.json")
            ?? throw new InvalidOperationException("hanasu.json is not embedded");
        return JsonNode.Parse(stream)!.AsObject();
    });

    private static JsonNode? Node(string path)
    {
        JsonNode? node = Data.Value;
        foreach (var key in path.Split('.')) node = node is JsonObject o ? o[key] : null;
        return node;
    }

    /// <summary>入れ子のキーの文。${device} と args を埋める。なければ空</summary>
    public static string Text(string path, string device, params (string Name, string Value)[] args) =>
        Node(path) is JsonValue v && v.TryGetValue<string>(out var template) ? Fill(template, device, args) : "";

    /// <summary>入れ子のキーの文の配列（1 行 1 要素）</summary>
    public static IReadOnlyList<string> Lines(string path, string device, params (string Name, string Value)[] args) =>
        Node(path) is JsonArray array ? array.Select(n => Fill(n!.GetValue<string>(), device, args)).ToList() : Array.Empty<string>();

    private static string Fill(string template, string device, (string Name, string Value)[] args)
    {
        var values = args.ToDictionary(a => a.Name, a => a.Value);
        values.TryAdd("device", device);
        return Prompts.Fill(template, values);
    }

    // 要件: REQ-DIC-160
    // 設計判断: DEC-DIC-190
    /// <summary>
    /// --app の exe の名前（大文字小文字を区別しない。.exe は省いてもよい）の既定の文体。一覧になければ、
    /// 文体なしで、exe の名前から拡張子を外したものをアプリ名にする
    /// </summary>
    public static AppStyle StyleForApp(string exe)
    {
        // パスで渡されても名前だけを見る（\ と / のどちらの区切りでも）
        var trimmed = exe.Trim();
        var name = trimmed[(trimmed.LastIndexOfAny(['\\', '/']) + 1)..];
        var withExe = name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ? name : name + ".exe";
        foreach (var entry in Node("defaultAppStyles") as JsonArray ?? [])
        {
            if (entry is not JsonObject o || o["windows"] is not JsonArray exes) continue;
            if (!exes.Any(e => string.Equals(e?.GetValue<string>(), withExe, StringComparison.OrdinalIgnoreCase))) continue;
            var preset = AppStylePresets.FromRawValue(o["preset"]?.GetValue<string>()) ?? AppStylePreset.None;
            return new AppStyle(withExe.ToLowerInvariant(), o["name"]?.GetValue<string>() ?? name, preset);
        }
        return new AppStyle(withExe.ToLowerInvariant(), withExe[..^4], AppStylePreset.None);
    }
}
