using Hanasu.Core.Ai;
using Hanasu.Core.Claude;
using Hanasu.Core.Gemini;
using Hanasu.Core.LocalLlm;
using Hanasu.Core.Settings;

namespace Hanasu.Core.Command;

/// <summary>どの用途の AI を使うか（refine・edit は音声入力、ask は会議）</summary>
public enum CommandAiUse
{
    Dictation,
    Meeting,
}

// 要件: REQ-COM-186
// 設計判断: DEC-COM-185, DEC-COM-190
/// <summary>AI の選び方（設定・--ai・--model）と、送る前の確かめ（認証情報・ローカルのサーバー）。Mac 版 HanasuAI の移植</summary>
public static class CommandAi
{
    public static readonly string[] Options = ["--ai", "--model"];

    /// <summary>--ai で選べる名前（Windows に apple はない）</summary>
    public static readonly string[] ProviderNames = ["local", "gemini", "claude"];

    // 要件: REQ-COM-186, REQ-MTG-126
    // 設計判断: DEC-COM-190
    /// <summary>hanasu ask の用途。Windows には「AI チャット・質問」の設定がないので、いつも会議の AI</summary>
    public static CommandAiUse AskUse => CommandAiUse.Meeting;

    /// <summary>--ai・--model があればそれ、なければその用途の設定の AI とモデル</summary>
    public static AiChoice Choice(CommandArguments args, CommandAiUse use, AppSettings settings) =>
        Choice(args.Value("--ai"), args.Value("--model"), use, settings);

    public static AiChoice Choice(string? ai, string? model, CommandAiUse use, AppSettings settings)
    {
        var provider = use == CommandAiUse.Dictation ? settings.DictationAi : settings.MeetingAi;
        if (ai is not null)
        {
            switch (ai.Trim().ToLowerInvariant())
            {
                case "local": provider = TextAiProvider.Local; break;
                case "gemini": provider = TextAiProvider.Gemini; break;
                case "claude": provider = TextAiProvider.Claude; break;
                case "apple":
                    throw new CommandException(HanasuExit.Usage, Strings.Cmd_AppleUnavailable,
                        [string.Format(Strings.Cmd_AllowedValues, string.Join(" / ", ProviderNames))]);
                default:
                    throw new CommandException(HanasuExit.Usage, string.Format(Strings.Cmd_UnknownAi, ai),
                        [string.Format(Strings.Cmd_AllowedValues, string.Join(" / ", ProviderNames))]);
            }
        }
        return new AiChoice(provider, string.IsNullOrWhiteSpace(model) ? SettingsModel(provider, use, settings) : model.Trim());
    }

    /// <summary>その AI と用途の、設定のモデル</summary>
    public static string SettingsModel(TextAiProvider provider, CommandAiUse use, AppSettings settings) => (provider, use) switch
    {
        (TextAiProvider.Claude, CommandAiUse.Dictation) => settings.ClaudeModel,
        (TextAiProvider.Claude, _) => settings.ClaudeMinutesModel,
        (TextAiProvider.Local, CommandAiUse.Dictation) => settings.LocalDictationModel,
        (TextAiProvider.Local, _) => settings.LocalMeetingModel,
        (_, CommandAiUse.Dictation) => settings.Model,
        _ => settings.MeetingMinutesModel,
    };

    /// <summary>
    /// 認証情報・ローカルのサーバーを確かめてから、クライアントを作る（まだ何も送らない）。
    /// 足りなければ終了コード 3、知らないモデルは 2、アプリがローカルの AI を使っていれば 1
    /// </summary>
    public static ITextAiClient MakeClient(AiChoice choice, TextPurpose purpose, TimeSpan timeout, CommandContext context)
    {
        if (choice.Provider == TextAiProvider.Local)
        {
            // 要件: REQ-COM-187
            // 設計判断: DEC-COM-184
            if (context.OtherLocalServerRunning())
            {
                throw new CommandException(HanasuExit.Failure, Strings.Cmd_LocalInUse, [Strings.Cmd_LocalInUseAdvice]);
            }
            if (LocalLlmModel.Find(choice.Model) is not { } model)
            {
                throw new CommandException(HanasuExit.Usage, string.Format(Strings.Cmd_UnknownLocalModel, choice.Model),
                    [string.Format(Strings.Cmd_AllowedValues, string.Join(" / ", LocalLlmModel.All.Select(m => m.Id)))]);
            }
            var server = context.LocalServer ?? LocalLlmServer.Shared;
            if (context.ClientFactory is null)
            {
                if (!server.IsDownloaded(model)) throw Credentials(LocalLlmException.ModelNotDownloaded(model).Message);
                if ((server.ExecutablePath ?? LocalLlmServer.ResolveExecutable()) is null) throw Credentials(LocalLlmException.ServerNotFound().Message);
            }
        }
        else if (context.ClientFactory is null && CredentialStatusOf(choice.Provider, context, read: false).Source is null)
        {
            throw Credentials(TextAiFactory.MissingCredentialsMessage(choice.Provider));
        }
        try
        {
            return context.ClientFactory?.Invoke(choice, purpose, timeout) ?? CreateClient(choice, purpose, timeout, context);
        }
        catch (Exception e) when (e is not CommandException)
        {
            throw Mapped(e);
        }
    }

    /// <summary>設定と認証情報（環境変数・保存したキー）から、本物のクライアントを作る</summary>
    private static ITextAiClient CreateClient(AiChoice choice, TextPurpose purpose, TimeSpan timeout, CommandContext context)
    {
        switch (choice.Provider)
        {
            case TextAiProvider.Local:
                var model = LocalLlmModel.Find(choice.Model)!;
                var use = purpose.IsLong() ? TextAiUse.Meeting : TextAiUse.Dictation;
                var minimum = LocalLlmClient.MinimumTimeout(use);
                return new LocalLlmClient(model, context.LocalServer ?? LocalLlmServer.Shared) { Timeout = timeout > minimum ? timeout : minimum };
            case TextAiProvider.Claude:
                if (context.Env("ANTHROPIC_API_KEY") is { } claudeKey) return new ClaudeClient(claudeKey) { Timeout = timeout };
                return (context.Secrets is { } secrets ? TextAiFactory.CreateClaude(secrets, timeout) : null)
                    ?? throw Credentials(TextAiFactory.MissingCredentialsMessage(choice.Provider));
            default:
                return new GeminiClient(GeminiAuthOf(context) ?? throw Credentials(TextAiFactory.MissingCredentialsMessage(choice.Provider)))
                {
                    Timeout = timeout,
                };
        }
    }

    /// <summary>Gemini の認証。環境変数のサービスアカウント → 設定（保存したキーかサービスアカウント） → 環境変数の API キー（Mac 版と同じ順）</summary>
    private static GeminiAuth? GeminiAuthOf(CommandContext context)
    {
        if (context.Env("GEMINI_SERVICE_ACCOUNT_JSON") is { } path)
        {
            return new GeminiAuth.ServiceAccount(ServiceAccountCredentials.Load(path), context.Env("GEMINI_VERTEX_LOCATION") ?? "global");
        }
        if (context.Secrets is { } secrets && GeminiAuthResolver.Resolve(context.Settings, secrets) is { } auth) return auth;
        if (context.Settings.AuthMode == GeminiAuthMode.ServiceAccount && context.Settings.ServiceAccountPath.Trim() is { Length: > 0 } settingsPath)
        {
            return new GeminiAuth.ServiceAccount(ServiceAccountCredentials.Load(settingsPath), context.Settings.VertexLocation);
        }
        return context.Env("GEMINI_API_KEY") is { } key ? new GeminiAuth.ApiKey(key) : null;
    }

    public static CommandException Credentials(string message) => new(HanasuExit.Credentials, message);

    // 要件: REQ-COM-182
    /// <summary>AI の処理の誤りを、終了コードの分かれる誤りにする（認証情報・モデルがなければ 3、ほかは 1）</summary>
    public static CommandException Mapped(Exception error) => error switch
    {
        CommandException command => command,
        TextAiException ai when ai.IsCredentialProblem => Credentials(ai.Message),
        ServiceAccountException or FileNotFoundException => Credentials(error.Message),
        _ => new CommandException(HanasuExit.Failure, string.Format(Strings.Cmd_AiFailed, error.Message)),
    };

    // 要件: REQ-COM-186
    // 設計判断: DEC-COM-185
    /// <summary>
    /// Claude・Gemini の認証情報を、クライアントを作るのと同じ順に探す。read なら、DPAPI で守ったキーは実際に読んで（値は捨てる）読めるかを確かめる。
    /// Windows Hello で守ったキーは、確認を出さないよう読まずに、守り方だけを出す（W3）
    /// </summary>
    public static CredentialStatus CredentialStatusOf(TextAiProvider provider, CommandContext context, bool read)
    {
        CredentialStatus Environment(string name) => new($"env:{name}", string.Format(Strings.Cmd_EnvVariable, name));
        CredentialStatus? Saved(SecretKind kind)
        {
            if (context.Secrets is not { } secrets) return null;
            var info = secrets.Describe(kind);
            if (!info.Exists) return null;
            if (info.Protection == SecretProtection.WindowsHello)
            {
                return new CredentialStatus("windowsHello", Strings.Cmd_SavedKeyHello);
            }
            var status = new CredentialStatus("dpapi", Strings.Cmd_SavedKeyDpapi);
            if (!read) return status;
            try
            {
                return secrets.GetAsync(kind).GetAwaiter().GetResult() is null ? null : status;
            }
            catch (Exception e) when (e is TextAiException or IOException or UnauthorizedAccessException)
            {
                return status with { Problem = e.Message };
            }
        }
        switch (provider)
        {
            case TextAiProvider.Claude:
                if (context.Env("ANTHROPIC_API_KEY") is not null) return Environment("ANTHROPIC_API_KEY");
                return Saved(SecretKind.ClaudeApiKey) ?? new CredentialStatus();
            case TextAiProvider.Gemini:
                if (context.Env("GEMINI_SERVICE_ACCOUNT_JSON") is not null) return Environment("GEMINI_SERVICE_ACCOUNT_JSON");
                switch (context.Settings.AuthMode)
                {
                    case GeminiAuthMode.ApiKey:
                        if (Saved(SecretKind.GeminiApiKey) is { } saved) return saved;
                        break;
                    case GeminiAuthMode.ServiceAccount:
                        var path = context.Settings.ServiceAccountPath.Trim();
                        if (path.Length > 0)
                        {
                            var status = new CredentialStatus("serviceAccount", string.Format(Strings.Cmd_ServiceAccount, path));
                            return read && !File.Exists(path) ? status with { Problem = string.Format(Strings.Cmd_CannotReadFile, path) } : status;
                        }
                        break;
                }
                if (context.Env("GEMINI_API_KEY") is not null) return Environment("GEMINI_API_KEY");
                return new CredentialStatus();
            default:
                return new CredentialStatus();
        }
    }
}
