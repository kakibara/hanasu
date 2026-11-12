using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Hanasu.Core.Command;

// 設定の「AI アプリにつなぐ」の中身（計画は docs/plans/agent-connect.md）。
// Claude Desktop・ChatGPT（Codex）・Claude Code の設定に、hanasu の MCP のサーバーを足す・外す。
// Mac 版 Sources/Hanasu/AgentConnect.swift と同じ決まり（見分け方・JSON と TOML の書き換え）。変えるときは両方を直す
// （共有のテストデータ common/testdata/connect/cases.json で比べる）。画面は Hanasu.Windows の SettingsWindow.CommandLine.cs、
// 動いているアプリと claude を探すのは Hanasu.Windows の Services/AgentApps.cs。

/// <summary>claude を動かした結果</summary>
public sealed record AgentProcessOutput(int Status, string Stdout, string Stderr, bool TimedOut = false);

/// <summary>「AI アプリにつなぐ」が見る環境（テストで差し替える）</summary>
public interface IAgentEnvironment
{
    /// <summary>%USERPROFILE%</summary>
    string Home { get; }
    /// <summary>%APPDATA%</summary>
    string AppData { get; }
    /// <summary>%LOCALAPPDATA%</summary>
    string LocalAppData { get; }
    /// <summary>動いている Claude Desktop の起動の引数（読めなければ null）</summary>
    IReadOnlyList<IReadOnlyList<string>?> ClaudeDesktopArguments();
    bool IsChatGPTRunning();
    bool IsClaudeCodeRunning();
    /// <summary>claude の場所（なければ null）</summary>
    string? FindClaude();
    /// <summary>claude を動かす（バックグラウンドで呼ぶ）</summary>
    AgentProcessOutput RunClaude(string claude, IReadOnlyList<string> arguments, TimeSpan timeout);
}

// 要件: REQ-COM-194
public static class AgentConnect
{
    // ---- 状態と結果 ----

    public enum ProblemKind { InvalidJson, UnexpectedShape, TomlUnsupported, Io }

    /// <summary>設定ファイルを書き換えられない理由</summary>
    public sealed record Problem(ProblemKind Kind, string Detail = "")
    {
        public static readonly Problem InvalidJson = new(ProblemKind.InvalidJson);
        public static readonly Problem UnexpectedShape = new(ProblemKind.UnexpectedShape);
        public static readonly Problem TomlUnsupported = new(ProblemKind.TomlUnsupported);
        public static Problem Io(string detail) => new(ProblemKind.Io, detail);

        /// <summary>共有のテストデータでの名前</summary>
        public string Code => Kind switch
        {
            ProblemKind.InvalidJson => "invalidJSON",
            ProblemKind.UnexpectedShape => "unexpectedShape",
            ProblemKind.TomlUnsupported => "tomlUnsupported",
            _ => "io",
        };
    }

    public enum StateKind { Connected, NotConnected, Other, Foreign, Unreadable }

    /// <summary>登録の状態。Other・Foreign の Command は、今の登録の command</summary>
    public sealed record State(StateKind Kind, string? Command = null, Problem? Problem = null)
    {
        public static readonly State Connected = new(StateKind.Connected);
        public static readonly State NotConnected = new(StateKind.NotConnected);
        public static State OtherHanasu(string command) => new(StateKind.Other, command);
        public static State ForeignEntry(string command) => new(StateKind.Foreign, command);
        public static State UnreadableFile(Problem problem) => new(StateKind.Unreadable, Problem: problem);

        public string Code => Kind switch
        {
            StateKind.Connected => "connected",
            StateKind.NotConnected => "notConnected",
            StateKind.Other => "other",
            StateKind.Foreign => "foreign",
            _ => "unreadable:" + Problem!.Code,
        };

        /// <summary>外せる Hanasu の項目があるか</summary>
        public bool Removable => Kind is StateKind.Connected or StateKind.Other;
    }

    public enum EditKind { Written, Unchanged, NeedsOverwrite, Unreadable, Nothing }

    /// <summary>書き換えの結果（ファイルの中身だけを扱う。書くのは呼んだ側）</summary>
    public sealed record Edit(EditKind Kind, string? Text = null, Problem? Problem = null)
    {
        public static readonly Edit Unchanged = new(EditKind.Unchanged);
        public static readonly Edit NeedsOverwrite = new(EditKind.NeedsOverwrite);
        public static readonly Edit Nothing = new(EditKind.Nothing);
        public static Edit Written(string text) => new(EditKind.Written, text);
        public static Edit UnreadableFile(Problem problem) => new(EditKind.Unreadable, Problem: problem);

        public string Code => Kind switch
        {
            EditKind.Written => "written",
            EditKind.Unchanged => "unchanged",
            EditKind.NeedsOverwrite => "needsOverwrite",
            EditKind.Unreadable => "unreadable",
            _ => "nothing",
        };
    }

    // ---- Hanasu の項目の見分け方 ----

    public enum Owner { Current, Other, Foreign }

    public static string Code(this Owner owner) => owner switch
    {
        Owner.Current => "current",
        Owner.Other => "other",
        _ => "foreign",
    };

    // 設計判断: DEC-COM-203
    /// <summary>Hanasu の実行ファイルの形か（Mac は Hanasu.app の中の実行ファイル、Windows は cli\hanasu.exe）</summary>
    public static bool IsHanasuExecutable(string path, bool windows)
    {
        if (windows) return path.Replace('/', '\\').ToLowerInvariant().EndsWith(@"\cli\hanasu.exe", StringComparison.Ordinal);
        return path.EndsWith("/Hanasu.app/Contents/MacOS/Hanasu", StringComparison.Ordinal);
    }

    /// <summary>
    /// 登録の command が、このアプリ・別の場所の Hanasu・Hanasu のものでない、のどれか。
    /// resolve は、シンボリックリンク（PATH に入れた hanasu など）をたどる
    /// </summary>
    public static Owner OwnerOf(string command, string executable, bool windows, Func<string, string>? resolve = null)
    {
        resolve ??= static p => p;
        string Normalized(string path)
        {
            var resolved = resolve(path);
            return windows ? resolved.Replace('/', '\\').ToLowerInvariant() : resolved;
        }
        var target = Normalized(command);
        if (target == Normalized(executable)) return Owner.Current;
        return IsHanasuExecutable(target, windows) ? Owner.Other : Owner.Foreign;
    }

    /// <summary>絶対パスだけ、シンボリックリンクをたどる（素の hanasu は PATH で探すので、Hanasu のものとは見なさない）</summary>
    public static string ResolveLink(string path) => Path.IsPathFullyQualified(path) ? ResolveReal(path) : path;

    /// <summary>シンボリックリンクなら、リンク先（最後までたどったもの）</summary>
    internal static string ResolveReal(string path)
    {
        try
        {
            var info = new FileInfo(path);
            if (info.LinkTarget is not null && info.ResolveLinkTarget(returnFinalTarget: true) is { } target) return target.FullName;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
        {
        }
        return path;
    }

    // ---- Claude Desktop の起動の引数 ----

    // 設計判断: DEC-COM-202
    /// <summary>起動の引数の --user-data-dir（なければ null = 既定の場所）</summary>
    public static string? UserDataDirectory(IReadOnlyList<string> arguments)
    {
        for (var index = 0; index < arguments.Count; index++)
        {
            var argument = arguments[index];
            if (argument.StartsWith("--user-data-dir=", StringComparison.Ordinal)) return Unquote(argument["--user-data-dir=".Length..]);
            if (argument == "--user-data-dir" && index + 1 < arguments.Count) return Unquote(arguments[index + 1]);
        }
        return null;
    }

    private static string Unquote(string text) =>
        text.Length >= 2 && text[0] == '"' && text[^1] == '"' ? text[1..^1] : text;

    /// <summary>Claude Desktop の実行ファイルか（名前だけでは Claude Code の claude.exe と見分けられないので、場所で見る）</summary>
    public static bool IsClaudeDesktopExecutable(string? path)
    {
        if (string.IsNullOrEmpty(path)) return false;
        var normalized = path.Replace('/', '\\');
        return normalized.Contains(@"\AnthropicClaude\", StringComparison.OrdinalIgnoreCase)
            || normalized.Contains(@"\WindowsApps\Claude_", StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>ChatGPT（Codex）のアプリの実行ファイルか（ストアの版。Codex CLI の codex は見ない）</summary>
    public static bool IsChatGPTExecutable(string? path) =>
        !string.IsNullOrEmpty(path) && path.Replace('/', '\\').Contains(@"\WindowsApps\OpenAI.", StringComparison.OrdinalIgnoreCase);

    /// <summary>Electron の子プロセス（--type=renderer など）。設定の場所を決めるのは親のプロセスなので見ない</summary>
    public static bool IsElectronChild(IReadOnlyList<string> arguments) =>
        arguments.Skip(1).Any(a => a.StartsWith("--type=", StringComparison.Ordinal));

    // ---- JSON（claude_desktop_config.json と ~/.claude.json） ----

    // 設計判断: DEC-COM-200, DEC-COM-204
    public static class ConfigJson
    {
        private static readonly JsonSerializerOptions Pretty = new()
        {
            WriteIndented = true,
            Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        };

        internal static readonly JsonSerializerOptions Compact = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

        /// <summary>空のファイル・ないファイルは {}。一番上がオブジェクトでないか、mcpServers がオブジェクトでなければ読めない</summary>
        internal static (JsonObject? Root, Problem? Problem) Parse(string? text)
        {
            // 先頭の BOM は読み飛ばす（書くときは付けない。Mac と同じ）
            if (text is not null && text.StartsWith('\uFEFF')) text = text[1..];
            if (string.IsNullOrWhiteSpace(text)) return (new JsonObject(), null);
            JsonNode? node;
            try
            {
                node = JsonNode.Parse(text);
                // 同じキーが 2 つあるオブジェクトは、中を読むときに例外になるので、ここで全部を読んでおく
                Materialize(node);
            }
            catch (Exception e) when (e is JsonException or ArgumentException or InvalidOperationException)
            {
                return (null, Problem.InvalidJson);
            }
            if (node is not JsonObject root) return (null, Problem.UnexpectedShape);
            if (root.TryGetPropertyValue("mcpServers", out var servers) && servers is not JsonObject) return (null, Problem.UnexpectedShape);
            return (root, null);
        }

        private static void Materialize(JsonNode? node)
        {
            switch (node)
            {
                case JsonObject obj:
                    foreach (var pair in obj) Materialize(pair.Value);
                    break;
                case JsonArray array:
                    foreach (var item in array) Materialize(item);
                    break;
            }
        }

        public static State StateOf(string? text, string executable, bool windows, Func<string, string>? resolve = null)
        {
            var (root, problem) = Parse(text);
            return problem is not null ? State.UnreadableFile(problem) : StateOf(root!, executable, windows, resolve);
        }

        private static State StateOf(JsonObject root, string executable, bool windows, Func<string, string>? resolve)
        {
            if (root["mcpServers"] is not JsonObject servers || !servers.TryGetPropertyValue("hanasu", out var entry)) return State.NotConnected;
            if (StringValue((entry as JsonObject)?["command"]) is not { } command) return State.ForeignEntry("?");
            return OwnerOf(command, executable, windows, resolve) switch
            {
                Owner.Current => State.Connected,
                Owner.Other => State.OtherHanasu(command),
                _ => State.ForeignEntry(command),
            };
        }

        private static string? StringValue(JsonNode? node) =>
            node is JsonValue value && value.GetValueKind() == JsonValueKind.String ? value.GetValue<string>() : null;

        public static Edit Connect(string? text, string executable, bool windows, bool overwrite, Func<string, string>? resolve = null)
        {
            var (root, problem) = Parse(text);
            if (problem is not null) return Edit.UnreadableFile(problem);
            var servers = root!["mcpServers"] as JsonObject;
            JsonObject? entry = null;
            switch (StateOf(root, executable, windows, resolve).Kind)
            {
                case StateKind.Connected:
                    return Edit.Unchanged;
                case StateKind.Foreign:
                    if (!overwrite) return Edit.NeedsOverwrite;
                    break;
                case StateKind.Other:
                    // 利用者が足したキー（env など）は残す
                    entry = servers!["hanasu"] as JsonObject;
                    break;
            }
            if (servers is null)
            {
                servers = new JsonObject();
                root["mcpServers"] = servers;
            }
            if (entry is null)
            {
                entry = new JsonObject();
                servers["hanasu"] = entry;
            }
            entry["command"] = executable;
            entry["args"] = new JsonArray("mcp");
            return Edit.Written(Render(root));
        }

        public static Edit Disconnect(string? text, string executable, bool windows, Func<string, string>? resolve = null)
        {
            var (root, problem) = Parse(text);
            if (problem is not null) return Edit.UnreadableFile(problem);
            if (!StateOf(root!, executable, windows, resolve).Removable) return Edit.Nothing;
            (root!["mcpServers"] as JsonObject)!.Remove("hanasu");
            return Edit.Written(Render(root));
        }

        /// <summary>~/.claude.json の projects の中に、そのフォルダだけの hanasu の登録があるか（DEC-COM-204）</summary>
        public static bool HasProjectEntry(string? text)
        {
            var (root, problem) = Parse(text);
            if (problem is not null || root!["projects"] is not JsonObject projects) return false;
            return projects.Any(p => (p.Value as JsonObject)?["mcpServers"] is JsonObject servers && servers.ContainsKey("hanasu"));
        }

        public static string Render(JsonObject root) => root.ToJsonString(Pretty) + "\n";
    }

    // ---- TOML（~/.codex/config.toml） ----

    // 設計判断: DEC-COM-201
    /// <summary>TOML を全部は読まず、[mcp_servers.hanasu] の表だけを行で扱う（Mac 版の ConfigTOML と 1 バイトまで同じ結果にする）</summary>
    public static class ConfigToml
    {
        public const string Marker = "# Added by Hanasu";

        private enum LineKind { Blank, Comment, Header, ArrayHeader, Key, Continuation }

        private readonly record struct Line(LineKind Kind, string[] Path);

        private sealed class Scan
        {
            /// <summary>改行（\n）を除いた行。\r は残す</summary>
            public List<string> Raw = [];
            public readonly List<Line> Kinds = [];
            /// <summary>その行のあとに閉じていない [ と { の数</summary>
            public readonly List<int> DepthAfter = [];
            public bool TrailingNewline;
            public bool Crlf;
            public bool Unsupported;
            /// <summary>先頭に BOM（U+FEFF）があったか（書くときも付ける）</summary>
            public bool Bom;

            public string Content(int index)
            {
                var line = Raw[index];
                return line.EndsWith('\r') ? line[..^1] : line;
            }
        }

        private sealed record Table(string[] Path, int Header, int End);

        private static readonly string[] HanasuPath = ["mcp_servers", "hanasu"];

        private static Scan ScanText(string? text)
        {
            text ??= "";
            var bom = text.StartsWith('\uFEFF');
            if (bom) text = text[1..];
            var raw = text.Split('\n').ToList();
            var trailingNewline = text.EndsWith('\n');
            if (trailingNewline || text.Length == 0) raw.RemoveAt(raw.Count - 1);
            var result = new Scan
            {
                Raw = raw,
                TrailingNewline = trailingNewline,
                Bom = bom,
                Crlf = text.Contains("\r\n", StringComparison.Ordinal),
                Unsupported = text.Contains("\"\"\"", StringComparison.Ordinal) || text.Contains("'''", StringComparison.Ordinal),
            };
            var depth = 0;
            string[] table = [];
            for (var index = 0; index < raw.Count; index++)
            {
                var content = result.Content(index);
                var trimmed = TrimSpaces(content);
                if (depth > 0)
                {
                    depth += BracketDelta(content);
                    result.Kinds.Add(new Line(LineKind.Continuation, []));
                }
                else if (trimmed.Length == 0)
                {
                    result.Kinds.Add(new Line(LineKind.Blank, []));
                }
                else if (trimmed.StartsWith('#'))
                {
                    result.Kinds.Add(new Line(LineKind.Comment, []));
                }
                else if (trimmed.StartsWith("[[", StringComparison.Ordinal))
                {
                    var path = HeaderPath(trimmed, array: true) ?? [];
                    if (path.Length == 0 || path[0] == "mcp_servers") result.Unsupported = true;
                    result.Kinds.Add(new Line(LineKind.ArrayHeader, path));
                    table = path;
                }
                else if (trimmed.StartsWith('['))
                {
                    if (HeaderPath(trimmed, array: false) is { } path)
                    {
                        result.Kinds.Add(new Line(LineKind.Header, path));
                        table = path;
                    }
                    else
                    {
                        result.Unsupported = true;
                        result.Kinds.Add(new Line(LineKind.Header, []));
                    }
                }
                else
                {
                    var (key, value) = SplitKey(content);
                    var path = key is null ? [] : KeyPath(key);
                    // mcp_servers を見出し以外で作っているファイルは扱わない
                    if ((table.Length == 0 && path.Length > 0 && path[0] == "mcp_servers") || table.SequenceEqual(["mcp_servers"])) result.Unsupported = true;
                    result.Kinds.Add(new Line(LineKind.Key, path));
                    depth = Math.Max(0, BracketDelta(value ?? ""));
                }
                result.DepthAfter.Add(depth);
            }
            return result;
        }

        /// <summary>[ a . "b" ] # コメント → ["a", "b"]。形が崩れていれば null</summary>
        private static string[]? HeaderPath(string trimmed, bool array)
        {
            var index = array ? 2 : 1;
            var inner = new StringBuilder();
            char? quote = null;
            var closed = false;
            while (index < trimmed.Length)
            {
                var character = trimmed[index++];
                if (quote is { } q)
                {
                    inner.Append(character);
                    if (character == '\\' && q == '"' && index < trimmed.Length)
                    {
                        inner.Append(trimmed[index++]);
                    }
                    else if (character == q)
                    {
                        quote = null;
                    }
                }
                else if (character is '"' or '\'')
                {
                    quote = character;
                    inner.Append(character);
                }
                else if (character == ']')
                {
                    if (array)
                    {
                        if (index >= trimmed.Length || trimmed[index] != ']') return null;
                        index++;
                    }
                    closed = true;
                    break;
                }
                else
                {
                    inner.Append(character);
                }
            }
            if (!closed) return null;
            var after = TrimSpaces(trimmed[index..]);
            if (!(after.Length == 0 || after.StartsWith('#'))) return null;
            var path = KeyPath(inner.ToString());
            return path.Any(p => p.Length == 0) ? null : path;
        }

        /// <summary>a . "b.c" . 'd' → ["a", "b.c", "d"]</summary>
        private static string[] KeyPath(string key)
        {
            var parts = new List<string>();
            var current = new StringBuilder();
            char? quote = null;
            var quoted = false;
            for (var index = 0; index < key.Length; index++)
            {
                var character = key[index];
                if (quote is { } q)
                {
                    if (character == '\\' && q == '"' && index + 1 < key.Length)
                    {
                        current.Append(key[++index]);
                    }
                    else if (character == q)
                    {
                        quote = null;
                    }
                    else
                    {
                        current.Append(character);
                    }
                }
                else if (character is '"' or '\'')
                {
                    quote = character;
                    quoted = true;
                    var trimmed = TrimSpaces(current.ToString());
                    current.Clear().Append(trimmed);
                }
                else if (character == '.')
                {
                    parts.Add(quoted ? current.ToString() : TrimSpaces(current.ToString()));
                    current.Clear();
                    quoted = false;
                }
                else if (!(character is ' ' or '\t') || !quoted)
                {
                    current.Append(character);
                }
            }
            parts.Add(quoted ? current.ToString() : TrimSpaces(current.ToString()));
            return [.. parts];
        }

        /// <summary>key = value の、引用の外の最初の = で分ける</summary>
        private static (string? Key, string? Value) SplitKey(string line)
        {
            char? quote = null;
            for (var index = 0; index < line.Length; index++)
            {
                var character = line[index];
                if (quote is { } q)
                {
                    if (character == q) quote = null;
                }
                else if (character is '"' or '\'')
                {
                    quote = character;
                }
                else if (character == '=')
                {
                    return (line[..index], line[(index + 1)..]);
                }
            }
            return (null, null);
        }

        /// <summary>文字列とコメントの外の [ { と ] } の差</summary>
        private static int BracketDelta(string text)
        {
            var depth = 0;
            char? quote = null;
            var escaped = false;
            foreach (var character in text)
            {
                if (quote is { } q)
                {
                    if (escaped) escaped = false;
                    else if (character == '\\' && q == '"') escaped = true;
                    else if (character == q) quote = null;
                }
                else if (character is '"' or '\'')
                {
                    quote = character;
                }
                else if (character == '#')
                {
                    break;
                }
                else if (character is '[' or '{')
                {
                    depth++;
                }
                else if (character is ']' or '}')
                {
                    depth--;
                }
            }
            return depth;
        }

        private static List<Table> Tables(Scan scan)
        {
            var result = new List<Table>();
            for (var index = 0; index < scan.Kinds.Count; index++)
            {
                var line = scan.Kinds[index];
                if (line.Kind is not (LineKind.Header or LineKind.ArrayHeader)) continue;
                if (result.Count > 0) result[^1] = result[^1] with { End = index };
                result.Add(new Table(line.Path, index, scan.Raw.Count));
            }
            return result;
        }

        private static bool IsHanasu(string[] path) => path.Length >= 2 && path[0] == "mcp_servers" && path[1] == "hanasu";

        /// <summary>Hanasu の表の見出し・command の行・args の行と、command の値</summary>
        private sealed class HanasuTable(Table table)
        {
            public Table Table { get; } = table;
            public int? CommandLine;
            public int? ArgsLine;
            public string? Command;
        }

        /// <summary>扱えなければ Supported が false</summary>
        private static (HanasuTable? Found, bool Supported) FindHanasuTable(Scan scan)
        {
            var all = Tables(scan);
            var mains = all.Where(t => t.Path.SequenceEqual(HanasuPath)).ToList();
            if (scan.Unsupported || mains.Count > 1) return (null, false);
            // 下の表だけがある（hanasu の表を暗に作っている）ものは扱わない
            if (mains.Count == 0) return (null, !all.Any(t => IsHanasu(t.Path)));
            var main = mains[0];
            var found = new HanasuTable(main);
            for (var index = main.Header + 1; index < main.End; index++)
            {
                var line = scan.Kinds[index];
                if (line.Kind != LineKind.Key) continue;
                if (line.Path is ["command"])
                {
                    if (scan.DepthAfter[index] > 0) return (null, false);
                    found.CommandLine = index;
                    found.Command = ParseString(SplitKey(scan.Content(index)).Value ?? "");
                }
                else if (line.Path is ["args"])
                {
                    if (scan.DepthAfter[index] > 0) return (null, false);
                    found.ArgsLine = index;
                }
            }
            return (found, true);
        }

        /// <summary>TOML の 1 行の文字列（基本・リテラル）を読む。後ろのコメントは許す</summary>
        public static string? ParseString(string value)
        {
            var text = TrimSpaces(value);
            if (text.Length == 0 || text[0] is not ('"' or '\'')) return null;
            var first = text[0];
            var result = new StringBuilder();
            var index = 1;
            while (index < text.Length)
            {
                var character = text[index++];
                if (character == first)
                {
                    var tail = TrimSpaces(text[index..]);
                    return tail.Length == 0 || tail.StartsWith('#') ? result.ToString() : null;
                }
                if (first == '"' && character == '\\')
                {
                    if (index >= text.Length) return null;
                    var escape = text[index++];
                    switch (escape)
                    {
                        case '\\': result.Append('\\'); break;
                        case '"': result.Append('"'); break;
                        case 'b': result.Append('\b'); break;
                        case 't': result.Append('\t'); break;
                        case 'n': result.Append('\n'); break;
                        case 'f': result.Append('\f'); break;
                        case 'r': result.Append('\r'); break;
                        case 'u' or 'U':
                            var hex = new StringBuilder();
                            for (var count = escape == 'u' ? 4 : 8; count > 0 && index < text.Length; count--) hex.Append(text[index++]);
                            if (!uint.TryParse(hex.ToString(), NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out var scalar)
                                || scalar > 0x10FFFF || scalar is >= 0xD800 and <= 0xDFFF) return null;
                            result.Append(char.ConvertFromUtf32((int)scalar));
                            break;
                        default: return null;
                    }
                }
                else
                {
                    result.Append(character);
                }
            }
            return null;
        }

        /// <summary>TOML の基本文字列（"…"）にする</summary>
        public static string Quote(string text)
        {
            var result = new StringBuilder("\"");
            foreach (var rune in text.EnumerateRunes())
            {
                switch (rune.Value)
                {
                    case '\\': result.Append(@"\\"); break;
                    case '"': result.Append("\\\""); break;
                    case '\b': result.Append(@"\b"); break;
                    case '\t': result.Append(@"\t"); break;
                    case '\n': result.Append(@"\n"); break;
                    case '\f': result.Append(@"\f"); break;
                    case '\r': result.Append(@"\r"); break;
                    default:
                        if (rune.Value < 0x20 || rune.Value == 0x7F) result.Append(CultureInfo.InvariantCulture, $"\\u{rune.Value:X4}");
                        else result.Append(rune.ToString());
                        break;
                }
            }
            return result.Append('"').ToString();
        }

        public static State StateOf(string? text, string executable, bool windows, Func<string, string>? resolve = null)
        {
            var (found, supported) = FindHanasuTable(ScanText(text));
            if (!supported) return State.UnreadableFile(Problem.TomlUnsupported);
            if (found is null) return State.NotConnected;
            if (found.Command is not { } command) return State.ForeignEntry("?");
            return OwnerOf(command, executable, windows, resolve) switch
            {
                Owner.Current => State.Connected,
                Owner.Other => State.OtherHanasu(command),
                _ => State.ForeignEntry(command),
            };
        }

        public static Edit Connect(string? text, string executable, bool windows, bool overwrite, Func<string, string>? resolve = null)
        {
            var scan = ScanText(text);
            var state = StateOf(text, executable, windows, resolve);
            switch (state.Kind)
            {
                case StateKind.Unreadable:
                    return Edit.UnreadableFile(state.Problem!);
                case StateKind.Connected:
                    return Edit.Unchanged;
                case StateKind.Foreign:
                    if (!overwrite) return Edit.NeedsOverwrite;
                    RemoveHanasu(scan);
                    return Edit.Written(Append(scan, executable));
                case StateKind.NotConnected:
                    return Edit.Written(Append(scan, executable));
            }
            // 別の場所の Hanasu: command と args の行だけを書き換える
            if (FindHanasuTable(scan).Found is not { } found) return Edit.UnreadableFile(Problem.TomlUnsupported);
            var end = scan.Crlf ? "\r" : "";
            // 書き換える行は、元の行の終わり（\r があるか）と字下げを保つ
            string Indent(int index) => new(scan.Content(index).TakeWhile(c => c is ' ' or '\t').ToArray());
            string Replacing(string line, int index) => Indent(index) + line + (scan.Raw[index].EndsWith('\r') ? "\r" : "");
            var command = "command = " + Quote(executable);
            const string args = "args = [\"mcp\"]";
            if (found.CommandLine is { } commandLine)
            {
                scan.Raw[commandLine] = Replacing(command, commandLine);
                if (found.ArgsLine is { } argsLine) scan.Raw[argsLine] = Replacing(args, argsLine);
                else Insert(scan, [Indent(commandLine) + args + end], commandLine + 1);
            }
            else
            {
                Insert(scan, [command + end, args + end], found.Table.Header + 1);
            }
            return Edit.Written(Join(scan));
        }

        public static Edit Disconnect(string? text, string executable, bool windows, Func<string, string>? resolve = null)
        {
            var scan = ScanText(text);
            var state = StateOf(text, executable, windows, resolve);
            if (state.Kind == StateKind.Unreadable) return Edit.UnreadableFile(state.Problem!);
            if (!state.Removable) return Edit.Nothing;
            RemoveHanasu(scan);
            return Edit.Written(Join(scan));
        }

        /// <summary>
        /// Hanasu の表（下の表も）を消す。表の見出しから最後のキーの行まで（後ろの空行と、次の表の前のコメントは残す）。
        /// 印の行は表と一緒に消す。ファイルの終わりまで消したら前の空行を 1 つ、前が空行（かファイルの始め）で後ろも空行なら後ろの空行を 1 つ消す
        /// </summary>
        private static void RemoveHanasu(Scan scan)
        {
            var regions = new List<(int Start, int Last)>();
            foreach (var table in Tables(scan).Where(t => IsHanasu(t.Path)))
            {
                var last = table.Header;
                for (var index = table.Header; index < table.End; index++)
                {
                    if (scan.Kinds[index].Kind is LineKind.Blank or LineKind.Comment) continue;
                    last = index;
                }
                var start = table.Header;
                if (table.Path.Length == 2 && start > 0 && TrimSpaces(scan.Content(start - 1)) == Marker) start--;
                regions.Add((start, last));
            }
            var lines = new List<string>(scan.Raw);
            bool Blank(int index) => TrimSpacesAndNewlines(lines[index]).Length == 0;
            foreach (var (start, last) in regions.OrderByDescending(r => r.Start))
            {
                lines.RemoveRange(start, last - start + 1);
                if (start >= lines.Count)
                {
                    if (start > 0 && Blank(start - 1)) lines.RemoveAt(start - 1);
                }
                else if ((start == 0 || Blank(start - 1)) && Blank(start))
                {
                    lines.RemoveAt(start);
                }
            }
            scan.Raw = lines;
        }

        /// <summary>行を足す。ファイルの終わり（改行のない最後の行のあと）に足すときは、最後の行を改行で終える</summary>
        private static void Insert(Scan scan, IEnumerable<string> lines, int index)
        {
            if (index >= scan.Raw.Count && !scan.TrailingNewline && scan.Raw.Count > 0)
            {
                if (scan.Crlf && !scan.Raw[^1].EndsWith('\r')) scan.Raw[^1] += "\r";
                scan.TrailingNewline = true;
            }
            scan.Raw.InsertRange(Math.Min(index, scan.Raw.Count), lines);
        }

        private static string Append(Scan scan, string executable)
        {
            var raw = new List<string>(scan.Raw);
            var end = scan.Crlf ? "\r" : "";
            if (scan.Crlf && !scan.TrailingNewline && raw.Count > 0 && !raw[^1].EndsWith('\r')) raw[^1] += "\r";
            if (raw.Count > 0 && TrimSpacesAndNewlines(raw[^1]).Length > 0) raw.Add(end);
            foreach (var line in new[] { Marker, "[mcp_servers.hanasu]", "command = " + Quote(executable), "args = [\"mcp\"]", "tool_timeout_sec = 300" })
            {
                raw.Add(line + end);
            }
            return Join(raw, trailingNewline: true, scan.Bom);
        }

        private static string Join(Scan scan) => Join(scan.Raw, scan.TrailingNewline, scan.Bom);

        private static string Join(List<string> raw, bool trailingNewline, bool bom) =>
            (bom ? "\uFEFF" : "") + (raw.Count == 0 ? "" : string.Join("\n", raw) + (trailingNewline ? "\n" : ""));

        /// <summary>空白（タブと Unicode の空白。改行は含まない）を両端から除く（Swift の .whitespaces と同じ）</summary>
        private static string TrimSpaces(string text)
        {
            static bool Space(char c) => c == '\t' || char.GetUnicodeCategory(c) == UnicodeCategory.SpaceSeparator;
            var start = 0;
            var end = text.Length;
            while (start < end && Space(text[start])) start++;
            while (end > start && Space(text[end - 1])) end--;
            return text[start..end];
        }

        /// <summary>空白と改行を両端から除く（Swift の .whitespacesAndNewlines と同じ）</summary>
        private static string TrimSpacesAndNewlines(string text) => text.Trim();
    }

    // ---- ファイルを読み書きする ----

    public const string BackupSuffix = ".hanasu-backup";

    private static readonly UTF8Encoding StrictUtf8 = new(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);
    private static readonly UTF8Encoding Utf8 = new(encoderShouldEmitUTF8Identifier: false);

    /// <summary>設定ファイルを読む。なければ Text が null</summary>
    public static (string? Text, Problem? Problem) Read(string file)
    {
        var real = ResolveReal(file);
        if (!File.Exists(real)) return (null, null);
        try
        {
            var bytes = File.ReadAllBytes(real);
            try
            {
                return (StrictUtf8.GetString(bytes), null);
            }
            catch (DecoderFallbackException)
            {
                return (null, Problem.Io("UTF-8"));
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            return (null, Problem.Io(e.Message));
        }
    }

    /// <summary>
    /// 書く前の写し（&lt;名前&gt;.hanasu-backup）を元と同じ権限で残し、一時ファイルに書いて置き換え、読み直して確かめる（違えば写しに戻す）。
    /// シンボリックリンクなら、リンクは残してリンク先を書き換える。Windows は置き換え（File.Replace）で元のファイルの ACL を保ち、
    /// Mac・Linux（テスト）は元の権限をそろえ、新しく作るファイルは 0600 にする
    /// </summary>
    public static void Write(string text, string file)
    {
        var real = ResolveReal(file);
        var directory = Path.GetDirectoryName(Path.GetFullPath(real)) ?? ".";
        var backup = real + BackupSuffix;
        var exists = File.Exists(real);
        UnixFileMode? mode = null;
        if (exists)
        {
            if (!OperatingSystem.IsWindows()) mode = File.GetUnixFileMode(real);
            File.Copy(real, backup, overwrite: true);
            if (!OperatingSystem.IsWindows() && mode is { } backupMode) File.SetUnixFileMode(backup, backupMode);
        }
        else
        {
            Directory.CreateDirectory(directory);
        }
        var temp = Path.Combine(directory, $".{Path.GetFileName(real)}.{Guid.NewGuid():N}.tmp");
        try
        {
            var options = new FileStreamOptions { Mode = FileMode.CreateNew, Access = FileAccess.Write, Share = FileShare.None };
            // 新しく作るファイルは、ほかのサーバーの鍵が入りうるので本人だけが読めるようにする
            var newMode = mode ?? (UnixFileMode.UserRead | UnixFileMode.UserWrite);
            if (!OperatingSystem.IsWindows()) options.UnixCreateMode = newMode;
            using (var stream = new FileStream(temp, options))
            {
                stream.Write(Utf8.GetBytes(text));
                stream.Flush(flushToDisk: true);
            }
            if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(temp, newMode);
            if (exists)
            {
                try
                {
                    File.Replace(temp, real, destinationBackupFileName: null);
                }
                catch (IOException)
                {
                    // 置き換えに使う API が使えない場所（ネットワークのドライブなど）は、上書きの移動にする
                    File.Move(temp, real, overwrite: true);
                }
            }
            else
            {
                File.Move(temp, real);
            }
        }
        finally
        {
            try
            {
                if (File.Exists(temp)) File.Delete(temp);
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
            }
        }
        string? back;
        try
        {
            back = StrictUtf8.GetString(File.ReadAllBytes(real));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or DecoderFallbackException)
        {
            back = null;
        }
        if (back != text)
        {
            if (File.Exists(backup)) File.Copy(backup, real, overwrite: true);
            throw new IOException(real);
        }
    }

    // ---- 行（画面の 1 行） ----

    public enum TargetKind { ClaudeDesktop, Codex, ClaudeCode }

    /// <summary>行の相手。Claude Desktop は設定の場所（%APPDATA%\Claude など）ごと</summary>
    public sealed record Target(TargetKind Kind, string? Directory = null);

    /// <param name="File">書く設定ファイル</param>
    /// <param name="Found">アプリ（か設定の場所）が見つかったか（DEC-COM-205）</param>
    /// <param name="Running">動いていて書けないか（DEC-COM-202）</param>
    /// <param name="ClaudePath">Claude Code の claude の場所（なければ %USERPROFILE%\.claude.json に直接書く）</param>
    /// <param name="ProjectEntry">.claude.json にフォルダだけの登録もあるか</param>
    public sealed record Row(Target Target, string File, bool Found, bool Running, State State, string? ClaudePath = null, bool ProjectEntry = false)
    {
        public bool IsDefaultClaude =>
            Target.Kind == TargetKind.ClaudeDesktop && string.Equals(Path.GetFileName(Target.Directory), "Claude", StringComparison.OrdinalIgnoreCase);
    }

    public enum OutcomeKind { Done, Unchanged, Nothing, NeedsOverwrite, Running, Unreadable, Failed, TimedOut }

    /// <summary>結果（画面で文にする）。NeedsOverwrite の Detail は今の登録の command、Failed の Detail は理由</summary>
    public sealed record Outcome(OutcomeKind Kind, string? Detail = null, Problem? Problem = null)
    {
        public static readonly Outcome Done = new(OutcomeKind.Done);
        public static readonly Outcome Unchanged = new(OutcomeKind.Unchanged);
        public static readonly Outcome Nothing = new(OutcomeKind.Nothing);
        public static readonly Outcome Running = new(OutcomeKind.Running);
        public static readonly Outcome TimedOut = new(OutcomeKind.TimedOut);
        public static Outcome NeedsOverwrite(string command) => new(OutcomeKind.NeedsOverwrite, command);
        public static Outcome UnreadableFile(Problem problem) => new(OutcomeKind.Unreadable, Problem: problem);
        public static Outcome Failed(string message) => new(OutcomeKind.Failed, message);
    }

    // ---- 行を集める ----

    /// <summary>Windows 版なので、パスは Windows の決まりで見分ける</summary>
    private const bool Windows = true;

    private static State ReadState(string file, Func<string?, State> state)
    {
        var (text, problem) = Read(file);
        return problem is not null ? State.UnreadableFile(problem) : state(text);
    }

    /// <summary>画面に出す行（Claude Desktop は設定の場所ごと）</summary>
    public static IReadOnlyList<Row> Rows(IAgentEnvironment env, string executable)
    {
        var rows = new List<Row>();

        // Claude Desktop（DEC-COM-200・202・205）
        var running = RunningClaudeDirectories(env);
        var locations = ClaudeDesktopLocations(env.AppData, env.LocalAppData);
        if (locations.Count == 0) locations = [DefaultClaudeDirectory(env.AppData, env.LocalAppData)];
        foreach (var directory in locations)
        {
            var file = Path.Combine(directory, "claude_desktop_config.json");
            var state = ReadState(file, text => ConfigJson.StateOf(text, executable, Windows, ResolveLink));
            var isRunning = running.All || running.Directories.Contains(DirectoryKey(directory));
            rows.Add(new Row(new Target(TargetKind.ClaudeDesktop, directory), file, System.IO.Directory.Exists(directory), isRunning, state));
        }

        // ChatGPT（Codex）
        var codexDirectory = Path.Combine(env.Home, ".codex");
        var codexFile = Path.Combine(codexDirectory, "config.toml");
        var codexState = ReadState(codexFile, text => ConfigToml.StateOf(text, executable, Windows, ResolveLink));
        rows.Add(new Row(new Target(TargetKind.Codex), codexFile, System.IO.Directory.Exists(codexDirectory), env.IsChatGPTRunning(), codexState));

        // Claude Code（DEC-COM-204）
        var claudeFile = Path.Combine(env.Home, ".claude.json");
        var claude = env.FindClaude();
        var projectEntry = false;
        State codeState;
        var (claudeText, claudeProblem) = Read(claudeFile);
        if (claudeProblem is not null)
        {
            codeState = State.UnreadableFile(claudeProblem);
        }
        else
        {
            codeState = ConfigJson.StateOf(claudeText, executable, Windows, ResolveLink);
            projectEntry = ConfigJson.HasProjectEntry(claudeText);
        }
        // claude があれば Claude Code が書くので、動いていても構わない
        var codeRunning = claude is null && env.IsClaudeCodeRunning();
        rows.Add(new Row(new Target(TargetKind.ClaudeCode), claudeFile, true, codeRunning, codeState, claude, projectEntry));
        return rows;
    }

    // 設計判断: DEC-COM-200
    /// <summary>ストアの版の Claude Desktop の設定の場所（%LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude）。なければ null</summary>
    public static string? StoreClaudeDirectory(string localAppData)
    {
        try
        {
            var packages = Path.Combine(localAppData, "Packages");
            if (!System.IO.Directory.Exists(packages)) return null;
            return System.IO.Directory.EnumerateDirectories(packages, "Claude_*")
                .Order(StringComparer.OrdinalIgnoreCase)
                .Select(p => Path.Combine(p, "LocalCache", "Roaming", "Claude"))
                .FirstOrDefault(System.IO.Directory.Exists);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            return null;
        }
    }

    /// <summary>既定の設定の場所（ストアの版があればそちら、なければ %APPDATA%\Claude）</summary>
    public static string DefaultClaudeDirectory(string appData, string localAppData) =>
        StoreClaudeDirectory(localAppData) ?? Path.Combine(appData, "Claude");

    // 設計判断: DEC-COM-200
    /// <summary>Claude と Claude- で始まるフォルダ（Claude 以外は設定ファイルのあるもの。deploymentMode のあるものは除く）</summary>
    public static List<string> ClaudeDesktopLocations(string appData, string localAppData)
    {
        List<string> names;
        try
        {
            names = System.IO.Directory.Exists(appData)
                ? System.IO.Directory.EnumerateDirectories(appData).Select(p => Path.GetFileName(p)).ToList()
                : [];
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            names = [];
        }
        var candidates = new List<(string Directory, bool IsDefault)>();
        if (StoreClaudeDirectory(localAppData) is { } store) candidates.Add((store, true));
        else if (names.Any(n => string.Equals(n, "Claude", StringComparison.OrdinalIgnoreCase))) candidates.Add((Path.Combine(appData, "Claude"), true));
        candidates.AddRange(names.Where(n => n.StartsWith("Claude-", StringComparison.OrdinalIgnoreCase))
            .Order(StringComparer.OrdinalIgnoreCase)
            .Select(n => (Path.Combine(appData, n), false)));
        var result = new List<string>();
        foreach (var (directory, isDefault) in candidates)
        {
            var file = Path.Combine(directory, "claude_desktop_config.json");
            if (!File.Exists(file))
            {
                if (isDefault) result.Add(directory);
                continue;
            }
            var (text, problem) = Read(file);
            if (problem is null && ConfigJson.Parse(text) is ({ } root, null) && root.ContainsKey("deploymentMode")) continue;
            result.Add(directory);
        }
        return result;
    }

    /// <summary>設定の場所を比べるための形（絶対パス・末尾の区切りなし・\・小文字）</summary>
    public static string DirectoryKey(string path)
    {
        string full;
        try
        {
            full = Path.GetFullPath(path);
        }
        catch (Exception e) when (e is ArgumentException or NotSupportedException or PathTooLongException or System.Security.SecurityException)
        {
            full = path;
        }
        return Path.TrimEndingDirectorySeparator(full).Replace('/', '\\').ToLowerInvariant();
    }

    // 設計判断: DEC-COM-202
    /// <summary>動いている Claude Desktop が使っている設定の場所（DirectoryKey の形）。引数を読めないものがあれば All</summary>
    public static (bool All, HashSet<string> Directories) RunningClaudeDirectories(IAgentEnvironment env)
    {
        var directories = new HashSet<string>();
        foreach (var arguments in env.ClaudeDesktopArguments())
        {
            if (arguments is null) return (true, []);
            var path = UserDataDirectory(arguments) ?? DefaultClaudeDirectory(env.AppData, env.LocalAppData);
            directories.Add(DirectoryKey(path));
        }
        return (false, directories);
    }

    // ---- つなぐ・外す ----

    /// <summary>確かめのあとで呼ぶ（バックグラウンドで）。overwrite は、Hanasu のものでない hanasu を置き換えてよいか</summary>
    public static Outcome Connect(Row row, IAgentEnvironment env, string executable, bool overwrite)
    {
        if (row.Target.Kind == TargetKind.ClaudeCode && row.ClaudePath is { } claude)
        {
            return ClaudeCli.Connect(claude, row.File, env, executable, overwrite);
        }
        return Change(row, env, text => row.Target.Kind == TargetKind.Codex
            ? ConfigToml.Connect(text, executable, Windows, overwrite, ResolveLink)
            : ConfigJson.Connect(text, executable, Windows, overwrite, ResolveLink));
    }

    public static Outcome Disconnect(Row row, IAgentEnvironment env, string executable)
    {
        if (row.Target.Kind == TargetKind.ClaudeCode && row.ClaudePath is { } claude)
        {
            return ClaudeCli.Disconnect(claude, row.File, env, executable);
        }
        return Change(row, env, text => row.Target.Kind == TargetKind.Codex
            ? ConfigToml.Disconnect(text, executable, Windows, ResolveLink)
            : ConfigJson.Disconnect(text, executable, Windows, ResolveLink));
    }

    /// <summary>今そのアプリが動いていて書けないか（押したときに確かめ直す）。Claude Code は claude に任せるときは見ない</summary>
    public static bool IsRunning(Row row, IAgentEnvironment env)
    {
        switch (row.Target.Kind)
        {
            case TargetKind.ClaudeDesktop:
                var running = RunningClaudeDirectories(env);
                return running.All || running.Directories.Contains(DirectoryKey(row.Target.Directory!));
            case TargetKind.Codex:
                return env.IsChatGPTRunning();
            default:
                return row.ClaudePath is null && env.IsClaudeCodeRunning();
        }
    }

    private static Outcome Change(Row row, IAgentEnvironment env, Func<string?, Edit> edit)
    {
        // 押したときにもう一度確かめる（画面を開いたあとで起動したかもしれない）
        if (IsRunning(row, env)) return Outcome.Running;
        var (text, problem) = Read(row.File);
        if (problem is not null) return Outcome.UnreadableFile(problem);
        var result = edit(text);
        switch (result.Kind)
        {
            case EditKind.Written:
                try
                {
                    Write(result.Text!, row.File);
                    return Outcome.Done;
                }
                catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.SecurityException or NotSupportedException or ArgumentException)
                {
                    return Outcome.Failed(e.Message);
                }
            case EditKind.Unchanged:
                return Outcome.Unchanged;
            case EditKind.Nothing:
                return Outcome.Nothing;
            case EditKind.Unreadable:
                return Outcome.UnreadableFile(result.Problem!);
            default:
                var state = row.Target.Kind == TargetKind.Codex
                    ? ConfigToml.StateOf(text, "", Windows)
                    : ConfigJson.StateOf(text, "", Windows);
                return Outcome.NeedsOverwrite(state.Kind == StateKind.Foreign ? state.Command! : "?");
        }
    }

    // ---- Claude Code の claude ----

    // 設計判断: DEC-COM-204
    public static class ClaudeCli
    {
        public static readonly TimeSpan Timeout = TimeSpan.FromSeconds(30);

        public static Outcome Connect(string claude, string file, IAgentEnvironment env, string executable, bool overwrite)
        {
            var (text, problem) = Read(file);
            if (problem is not null) return Outcome.UnreadableFile(problem);
            var (hasPrevious, previous) = PreviousEntry(text);
            var state = ConfigJson.StateOf(text, executable, Windows, ResolveLink);
            switch (state.Kind)
            {
                case StateKind.Connected:
                    return Outcome.Unchanged;
                case StateKind.Foreign when !overwrite:
                    return Outcome.NeedsOverwrite(state.Command!);
                case StateKind.Unreadable:
                    return Outcome.UnreadableFile(state.Problem!);
            }
            // 全部で 30 秒まで（remove・add・入れ直しの合計）
            var deadline = DateTime.UtcNow + Timeout;
            TimeSpan Remaining() => TimeSpan.FromTicks(Math.Max(TimeSpan.FromSeconds(1).Ticks, (deadline - DateTime.UtcNow).Ticks));
            // claude mcp add は同じ名前があると失敗するので、先に外す
            if (hasPrevious)
            {
                var removed = env.RunClaude(claude, ["mcp", "remove", "--scope", "user", "hanasu"], Remaining());
                if (removed.TimedOut) return Outcome.TimedOut;
                if (removed.Status != 0) return Outcome.Failed(Message(removed));
            }
            var added = env.RunClaude(claude, ["mcp", "add", "--scope", "user", "hanasu", "--", executable, "mcp"], Remaining());
            if (added.Status == 0 && !added.TimedOut) return Outcome.Done;
            var reasons = new List<string>();
            if (!added.TimedOut) reasons.Add(Message(added));
            // 足せなかったら、前の項目を入れ直す。入れ直せなかったら、そのことも出す
            if (previous is not null)
            {
                var restored = env.RunClaude(claude, ["mcp", "add-json", "--scope", "user", "hanasu", previous.ToJsonString(ConfigJson.Compact)], Remaining());
                if (restored.TimedOut) reasons.Add("claude mcp add-json: timeout");
                else if (restored.Status != 0) reasons.Add("claude mcp add-json: " + Message(restored));
            }
            if (added.TimedOut && reasons.Count == 0) return Outcome.TimedOut;
            return Outcome.Failed(string.Join("\n", reasons));
        }

        public static Outcome Disconnect(string claude, string file, IAgentEnvironment env, string executable)
        {
            var (text, problem) = Read(file);
            if (problem is not null) return Outcome.UnreadableFile(problem);
            if (!ConfigJson.StateOf(text, executable, Windows, ResolveLink).Removable) return Outcome.Nothing;
            var removed = env.RunClaude(claude, ["mcp", "remove", "--scope", "user", "hanasu"], Timeout);
            if (removed.TimedOut) return Outcome.TimedOut;
            return removed.Status == 0 ? Outcome.Done : Outcome.Failed(Message(removed));
        }

        /// <summary>一番上の mcpServers.hanasu があるか と、入れ直せる形（オブジェクト）ならその中身</summary>
        private static (bool Exists, JsonObject? Entry) PreviousEntry(string? text)
        {
            var (root, problem) = ConfigJson.Parse(text);
            if (problem is not null || root!["mcpServers"] is not JsonObject servers || !servers.TryGetPropertyValue("hanasu", out var entry)) return (false, null);
            return (true, entry as JsonObject);
        }

        private static string Message(AgentProcessOutput output)
        {
            var text = output.Stderr.Trim();
            return text.Length == 0 ? output.Stdout.Trim() : text;
        }

        // 設計判断: DEC-COM-204
        /// <summary>Claude Desktop に入っている Claude Code（root は ...\Claude\claude-code。いちばん新しい版の中の claude.exe）</summary>
        public static string? Bundled(string root)
        {
            try
            {
                if (!System.IO.Directory.Exists(root)) return null;
                var versions = System.IO.Directory.EnumerateDirectories(root)
                    .Where(p => Path.GetFileName(p) is { Length: > 0 } name && char.IsAsciiDigit(name[0]))
                    .OrderByDescending(p => Path.GetFileName(p), Comparer<string>.Create(CompareVersions));
                var options = new EnumerationOptions { RecurseSubdirectories = true, MaxRecursionDepth = 4, IgnoreInaccessible = true };
                foreach (var version in versions)
                {
                    if (System.IO.Directory.EnumerateFiles(version, "claude.exe", options).Order(StringComparer.Ordinal).FirstOrDefault() is { } path) return path;
                }
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.SecurityException)
            {
            }
            return null;
        }

        /// <summary>1.2.10 &gt; 1.2.9 のように、数字の部分は数として比べる</summary>
        public static int CompareVersions(string a, string b)
        {
            var left = a.Split('.');
            var right = b.Split('.');
            for (var index = 0; index < Math.Max(left.Length, right.Length); index++)
            {
                var l = index < left.Length ? left[index] : "";
                var r = index < right.Length ? right[index] : "";
                var compared = long.TryParse(l, NumberStyles.None, CultureInfo.InvariantCulture, out var ln)
                    && long.TryParse(r, NumberStyles.None, CultureInfo.InvariantCulture, out var rn)
                    ? ln.CompareTo(rn)
                    : string.CompareOrdinal(l, r);
                if (compared != 0) return compared;
            }
            return 0;
        }

        /// <summary>.cmd を cmd /c で動かしてよいパスか（&amp;・%・^・" を含むパスは、cmd の読み方で別のコマンドになりうるので動かさない）</summary>
        public static bool IsSafeCmdPath(string path) => path.IndexOfAny(['&', '%', '^', '"']) < 0;
    }

    /// <summary>子プロセスを動かし、timeout で打ち切る（子のプロセスもまとめて終わらせる）</summary>
    public static AgentProcessOutput RunProcess(ProcessStartInfo info, TimeSpan timeout)
    {
        info.UseShellExecute = false;
        info.CreateNoWindow = true;
        info.RedirectStandardInput = true;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.StandardOutputEncoding = Utf8;
        info.StandardErrorEncoding = Utf8;
        using var process = new Process { StartInfo = info };
        try
        {
            process.Start();
        }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or InvalidOperationException or IOException)
        {
            return new AgentProcessOutput(-1, "", e.Message);
        }
        process.StandardInput.Close();
        // パイプがいっぱいで止まらないように、並べて読む
        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();
        if (!process.WaitForExit(timeout))
        {
            try
            {
                process.Kill(entireProcessTree: true);
            }
            catch (Exception e) when (e is InvalidOperationException or System.ComponentModel.Win32Exception or NotSupportedException)
            {
            }
            process.WaitForExit(TimeSpan.FromSeconds(2));
            return new AgentProcessOutput(-1, "", "", TimedOut: true);
        }
        Task.WaitAll([stdout, stderr], TimeSpan.FromSeconds(5));
        return new AgentProcessOutput(process.ExitCode,
            stdout.IsCompletedSuccessfully ? stdout.Result : "",
            stderr.IsCompletedSuccessfully ? stderr.Result : "");
    }

    // ---- Windows のコマンドライン ----

    /// <summary>Windows のコマンドラインの分け方と組み立て方（純粋な関数。Mac の上でもテストする）</summary>
    public static class WindowsCommandLine
    {
        // 設計判断: DEC-COM-202
        /// <summary>
        /// コマンドライン（Win32_Process.CommandLine）を引数に分ける。CommandLineToArgvW と同じ決まり
        /// （最初の実行ファイルは引用符の中をそのまま。ほかは \ と " の決まりに従い、引用の中の "" は " 1 つ）
        /// </summary>
        public static List<string> Split(string commandLine)
        {
            var result = new List<string>();
            var text = commandLine;
            var index = 0;
            while (index < text.Length && text[index] is ' ' or '\t') index++;
            if (index >= text.Length) return result;
            var current = new StringBuilder();
            if (text[index] == '"')
            {
                index++;
                while (index < text.Length && text[index] != '"') current.Append(text[index++]);
                if (index < text.Length) index++;
            }
            else
            {
                while (index < text.Length && text[index] is not (' ' or '\t')) current.Append(text[index++]);
            }
            result.Add(current.ToString());
            while (true)
            {
                while (index < text.Length && text[index] is ' ' or '\t') index++;
                if (index >= text.Length) break;
                current.Clear();
                var inQuotes = false;
                while (index < text.Length)
                {
                    var character = text[index];
                    if (character is ' ' or '\t' && !inQuotes) break;
                    if (character == '\\')
                    {
                        var count = 0;
                        while (index < text.Length && text[index] == '\\')
                        {
                            count++;
                            index++;
                        }
                        if (index < text.Length && text[index] == '"')
                        {
                            current.Append('\\', count / 2);
                            if (count % 2 == 1)
                            {
                                current.Append('"');
                                index++;
                            }
                        }
                        else
                        {
                            current.Append('\\', count);
                        }
                        continue;
                    }
                    if (character == '"')
                    {
                        if (inQuotes && index + 1 < text.Length && text[index + 1] == '"')
                        {
                            current.Append('"');
                            index += 2;
                            continue;
                        }
                        inQuotes = !inQuotes;
                        index++;
                        continue;
                    }
                    current.Append(character);
                    index++;
                }
                result.Add(current.ToString());
            }
            return result;
        }

        private const string CmdMetaCharacters = "()[]%!^\"`<>&|;, *?";

        // 設計判断: DEC-COM-204
        /// <summary>
        /// npm の claude.cmd を cmd.exe で動かすときの引数（cmd.exe の後ろに付ける）。各引数を、node などが読む決まり（\ と "）で囲み、
        /// cmd の特別な文字を ^ で 2 回エスケープする（cmd /c と、.cmd の中の %* の 2 回読まれるため）。
        /// .cmd のパスに &amp;・%・^・" があるか、引数に改行があれば null（動かさない）
        /// </summary>
        public static string? CmdArguments(string script, IReadOnlyList<string> arguments)
        {
            if (!ClaudeCli.IsSafeCmdPath(script) || arguments.Any(a => a.IndexOfAny(['\r', '\n', '\0']) >= 0)) return null;
            var parts = arguments.Select(argument =>
            {
                var quoted = new StringBuilder("\"");
                var backslashes = 0;
                foreach (var character in argument)
                {
                    if (character == '\\')
                    {
                        backslashes++;
                        continue;
                    }
                    if (character == '"')
                    {
                        quoted.Append('\\', backslashes * 2 + 1);
                    }
                    else
                    {
                        quoted.Append('\\', backslashes);
                    }
                    quoted.Append(character);
                    backslashes = 0;
                }
                quoted.Append('\\', backslashes * 2).Append('"');
                var escaped = new StringBuilder();
                foreach (var character in quoted.ToString())
                {
                    if (CmdMetaCharacters.Contains(character)) escaped.Append("^^^");
                    escaped.Append(character);
                }
                return escaped.ToString();
            });
            return $"/d /s /c \"\"{script}\" {string.Join(' ', parts)}\"";
        }
    }
}
