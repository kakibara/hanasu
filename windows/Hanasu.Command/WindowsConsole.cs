using System.Runtime.InteropServices;
using System.Text;
using Hanasu.Core.Command;
using Microsoft.Win32.SafeHandles;

namespace Hanasu.Command;

// 要件: REQ-COM-180, REQ-COM-181
// 設計判断: DEC-COM-195, DEC-COM-186
/// <summary>
/// cli\hanasu.exe の入出力（WD9）。相手がコンソールなら UTF-16 で読み書きし（WriteConsoleW。コードページに依らず表示できる）、
/// パイプ・ファイルなら UTF-8（BOM なし・改行は \n）で書き、UTF-8 として読む（正しくなければコンソールのコードページで読み直す）。
/// Console.OutputEncoding は変えない（親のコンソールの設定を書き換えない）。
/// hanasu mcp では、本当の stdout を複製して取っておき、プロセスの stdout を stderr に付け替える（WD6）
/// </summary>
internal sealed partial class WindowsConsole : ICommandConsole, IDisposable
{
    private const int StdInput = -10;
    private const int StdOutput = -11;
    private const int StdError = -12;
    private const uint FileTypeDisk = 0x0001;
    private const uint FileTypePipe = 0x0003;
    private const uint DuplicateSameAccess = 0x00000002;

    private readonly IntPtr output;
    private readonly IntPtr error;
    private readonly IntPtr input;
    private readonly IntPtr protocolOutput;
    private readonly object gate = new();
    private Stream? protocolInput;
    private byte[]? pendingRead;

    private WindowsConsole(IntPtr output, IntPtr error, IntPtr input, IntPtr protocolOutput)
    {
        this.output = output;
        this.error = error;
        this.input = input;
        this.protocolOutput = protocolOutput;
    }

    public static WindowsConsole Create(bool protocol)
    {
        var output = GetStdHandle(StdOutput);
        var error = GetStdHandle(StdError);
        var input = GetStdHandle(StdInput);
        if (!protocol) return new WindowsConsole(output, error, input, output);
        var process = GetCurrentProcess();
        if (!DuplicateHandle(process, output, process, out var saved, 0, false, DuplicateSameAccess)) saved = output;
        // これより後に stdout へ書かれたもの（Console.Out・子プロセス）は stderr に行く
        SetStdHandle(StdOutput, error);
        System.Console.SetOut(System.Console.Error);
        return new WindowsConsole(error, error, input, saved);
    }

    private static bool IsConsole(IntPtr handle) => handle != IntPtr.Zero && handle != new IntPtr(-1) && GetConsoleMode(handle, out _);

    private void Write(IntPtr handle, string text)
    {
        if (handle == IntPtr.Zero || handle == new IntPtr(-1)) return;
        lock (gate)
        {
            if (IsConsole(handle))
            {
                WriteConsoleW(handle, text, (uint)text.Length, out _, IntPtr.Zero);
                return;
            }
            var bytes = CommandEncoding.EncodeOutput(text);
            using var stream = new FileStream(new SafeFileHandle(handle, ownsHandle: false), FileAccess.Write, 1, false);
            stream.Write(bytes);
            stream.Flush();
        }
    }

    public void Out(string text) => Write(output, text.EndsWith('\n') ? text : text + "\n");
    public void Err(string text) => Write(error, text + "\n");

    public StdinKind StdinKind => input == IntPtr.Zero || input == new IntPtr(-1) ? StdinKind.None
        : IsConsole(input) ? StdinKind.Terminal
        : GetFileType(input) is FileTypeDisk or FileTypePipe ? StdinKind.Redirected
        : StdinKind.None;

    private static Encoding? ConsoleEncoding()
    {
        try { return Encoding.GetEncoding((int)GetConsoleCP()); }
        catch (Exception e) when (e is ArgumentException or NotSupportedException) { return null; }
    }

    private byte[] ReadAllBytes()
    {
        if (pendingRead is { } read) return read;
        using var stream = new FileStream(new SafeFileHandle(input, ownsHandle: false), FileAccess.Read, 1, false);
        using var buffer = new MemoryStream();
        stream.CopyTo(buffer);
        pendingRead = buffer.ToArray();
        return pendingRead;
    }

    public string ReadAllStdin() => StdinKind == StdinKind.Redirected ? CommandEncoding.DecodeInput(ReadAllBytes(), ConsoleEncoding()) : "";

    public string? PendingStdin()
    {
        if (StdinKind != StdinKind.Redirected) return null;
        var type = GetFileType(input);
        if (type == FileTypeDisk)
        {
            return GetFileSizeEx(input, out var size) && size > 0 ? ReadAllStdin() : null;
        }
        // パイプは、待たずに読める分があるときだけ読む（開いたまま何も書かないパイプは、来ていないとみなす）
        return PeekNamedPipe(input, IntPtr.Zero, 0, IntPtr.Zero, out var available, IntPtr.Zero) && available > 0 ? ReadAllStdin() : null;
    }

    public async Task<string?> ReadProtocolLineAsync(CancellationToken cancellationToken)
    {
        protocolInput ??= new FileStream(new SafeFileHandle(input, ownsHandle: false), FileAccess.Read, 1, false);
        using var line = new MemoryStream();
        var one = new byte[1];
        while (true)
        {
            var read = await protocolInput.ReadAsync(one, cancellationToken).ConfigureAwait(false);
            if (read == 0) return line.Length == 0 ? null : Encoding.UTF8.GetString(line.ToArray());
            // 行の区切りは \n だけ（U+2028 などで切らない）
            if (one[0] == (byte)'\n') return Encoding.UTF8.GetString(line.ToArray()).TrimEnd('\r');
            line.WriteByte(one[0]);
        }
    }

    public void WriteProtocolLine(string line)
    {
        var bytes = CommandEncoding.EncodeOutput(line + "\n");
        lock (gate)
        {
            using var stream = new FileStream(new SafeFileHandle(protocolOutput, ownsHandle: false), FileAccess.Write, 1, false);
            stream.Write(bytes);
            stream.Flush();
        }
    }

    public void Dispose() => protocolInput?.Dispose();

    [LibraryImport("kernel32.dll", SetLastError = true)]
    private static partial IntPtr GetStdHandle(int stdHandle);

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool SetStdHandle(int stdHandle, IntPtr handle);

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetConsoleMode(IntPtr handle, out uint mode);

    [LibraryImport("kernel32.dll", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool WriteConsoleW(IntPtr handle, string buffer, uint length, out uint written, IntPtr reserved);

    [LibraryImport("kernel32.dll")]
    private static partial uint GetConsoleCP();

    [LibraryImport("kernel32.dll")]
    private static partial uint GetFileType(IntPtr handle);

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetFileSizeEx(IntPtr handle, out long size);

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool PeekNamedPipe(IntPtr pipe, IntPtr buffer, uint size, IntPtr read, out uint available, IntPtr left);

    [LibraryImport("kernel32.dll")]
    private static partial IntPtr GetCurrentProcess();

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool DuplicateHandle(IntPtr sourceProcess, IntPtr source, IntPtr targetProcess, out IntPtr target,
        uint access, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint options);
}
