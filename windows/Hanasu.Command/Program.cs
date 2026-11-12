using System.Reflection;
using System.Text;
using Hanasu.Core.Command;
using Hanasu.Core.LocalLlm;
using Hanasu.Core.Meetings;
using Hanasu.Core.Settings;
using Hanasu.Platform;
using Microsoft.Win32;

namespace Hanasu.Command;

// 要件: REQ-COM-180, REQ-COM-183
// 設計判断: DEC-COM-148, DEC-COM-193
/// <summary>cli\hanasu.exe の入り口。アプリ（Hanasu.exe）は起動せず、会議のファイルを書き換えない</summary>
internal static class Program
{
    public static async Task<int> Main(string[] args)
    {
        // DLL を探す場所を絞る（作業フォルダと PATH を外す）
        DllSearch.Harden();
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        var protocol = args.Length > 0 && args[0] == "mcp";
        // 設計判断: DEC-COM-186（WD6）
        // hanasu mcp は、本当の stdout を取っておき、プロセスの stdout を stderr に付け替える（どこかが stdout に書いても、接続を壊さない）
        using var console = WindowsConsole.Create(protocol);

        var environment = System.Environment.GetEnvironmentVariables().Cast<System.Collections.DictionaryEntry>()
            .ToDictionary(e => (string)e.Key, e => e.Value?.ToString() ?? "", StringComparer.OrdinalIgnoreCase);
        var settings = new SettingsStore().Load();
        // 要件: REQ-COM-060（ヘルプとエラーは表示の言語）
        UiLanguage.Apply();

        // 要件: REQ-COM-186
        // 設計判断: DEC-COM-144, DEC-COM-198（W3。Windows Hello の確認は、画面のないセッションでは出さず、60 秒で諦める）
        var secrets = new SecretStore(SecretStore.DefaultPath, new DpapiDataProtector(),
            new GuardedPresenceKey(new WindowsHelloKey(), () => GuardedPresenceKey.DesktopAvailable(environment), GuardedPresenceKey.DefaultTimeout));
        if (protocol)
        {
            // hanasu mcp は鍵を持ち続けるので、アプリと同じく、画面のロック・ログオフ・スリープで捨てる
            SystemEvents.SessionSwitch += (_, e) =>
            {
                if (e.Reason is SessionSwitchReason.SessionLock or SessionSwitchReason.SessionLogoff or SessionSwitchReason.ConsoleDisconnect
                    or SessionSwitchReason.RemoteDisconnect) secrets.Lock();
            };
            SystemEvents.PowerModeChanged += (_, e) =>
            {
                if (e.Mode == PowerModes.Suspend) secrets.Lock();
            };
        }

        // 要件: REQ-COM-187
        // 設計判断: DEC-COM-184（WD4。llama-server はジョブオブジェクトに入れ、Ctrl-C や異常な終了でも残さない）
        LocalLlmServer.Shared.ProcessStarted = ChildProcessJob.Assign;
        LocalLlmServer.Shared.Log = AppLog.Write;
        System.Console.CancelKeyPress += (_, _) => LocalLlmServer.Shared.Stop();
        AppDomain.CurrentDomain.ProcessExit += (_, _) => LocalLlmServer.Shared.Stop();

        var executable = System.Environment.ProcessPath ?? Path.Combine(AppContext.BaseDirectory, "hanasu.exe");
        var context = new CommandContext
        {
            Settings = settings,
            Console = console,
            Secrets = secrets,
            Environment = environment,
            DefaultMeetingsDirectory = settings.MeetingsDirectory.Trim().Length > 0 ? settings.MeetingsDirectory.Trim() : MeetingStore.DefaultBaseDirectory,
            ExecutablePath = executable,
            Version = Version(),
            OtherLocalServerRunning = LocalLlmServerRecords.OtherProcessServerRunning,
            Platform = new WindowsCommandPlatform(Path.GetDirectoryName(executable)!, executable, settings),
        };
        // ログには中身を書かない（起動と終了コードだけ。security-windows.md の約束）
        var exit = await HanasuCommand.RunAsync(args, context).ConfigureAwait(false);
        if (protocol) AppLog.Write($"hanasu mcp exited {(int)exit}");
        LocalLlmServer.Shared.Stop();
        return (int)exit;
    }

    /// <summary>版（配布のときに -p:Version で入れる。InformationalVersion の + 以降は除く）</summary>
    private static string Version()
    {
        var info = typeof(Program).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "dev";
        var plus = info.IndexOf('+');
        return plus >= 0 ? info[..plus] : info;
    }
}
