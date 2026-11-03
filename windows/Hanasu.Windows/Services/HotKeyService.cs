using System.Windows.Interop;
using System.Windows.Threading;
using Hanasu.Core.Dictation;
using Hanasu.Core.Settings;
using Hanasu.Windows.Native;

namespace Hanasu.Windows.Services;

/// <summary>
/// RegisterHotKey でグローバルショートカットを登録する。メッセージ専用のウインドウで WM_HOTKEY を受ける。
/// RegisterHotKey は押したときしか知らせないので、「押している間だけ録音」のために、押されたキーが離されるまで
/// GetAsyncKeyState で見張って Released を出す。
/// </summary>
internal sealed class HotKeyService : IDisposable
{
    private sealed record Registration(int Id, HotKeyCombo Combo, Action<HotKeyEventKind> Handler);

    private readonly HwndSource source;
    private readonly Dictionary<int, Registration> registrations = new();
    private readonly HashSet<int> held = new();
    private readonly DispatcherTimer releaseTimer;
    private int nextId = 1;

    public HotKeyService()
    {
        // HWND_MESSAGE（-3）を親にすると、画面に出ないメッセージ専用のウインドウになる
        var parameters = new HwndSourceParameters("Hanasu.HotKeys") { ParentWindow = new IntPtr(-3), Width = 0, Height = 0 };
        source = new HwndSource(parameters);
        source.AddHook(WndProc);
        releaseTimer = new DispatcherTimer(DispatcherPriority.Input) { Interval = TimeSpan.FromMilliseconds(15) };
        releaseTimer.Tick += (_, _) => CheckReleased();
    }

    /// <summary>登録する。ほかのアプリが使っているなどで登録できなければ null</summary>
    public int? Register(HotKeyCombo combo, Action<HotKeyEventKind> handler)
    {
        var id = nextId++;
        // MOD_NOREPEAT: 押しっぱなしのキーリピートで何度も届かないようにする
        if (!NativeMethods.RegisterHotKey(source.Handle, id, (uint)combo.Modifiers | NativeMethods.MOD_NOREPEAT, (uint)combo.VirtualKey))
        {
            return null;
        }
        registrations[id] = new Registration(id, combo, handler);
        return id;
    }

    public void Unregister(int? id)
    {
        if (id is not int value || !registrations.Remove(value)) return;
        held.Remove(value);
        NativeMethods.UnregisterHotKey(source.Handle, value);
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == NativeMethods.WM_HOTKEY && registrations.TryGetValue(wParam.ToInt32(), out var registration))
        {
            handled = true;
            if (held.Add(registration.Id)) releaseTimer.Start();
            registration.Handler(HotKeyEventKind.Pressed);
        }
        return IntPtr.Zero;
    }

    private void CheckReleased()
    {
        foreach (var id in held.ToArray())
        {
            if (!registrations.TryGetValue(id, out var registration))
            {
                held.Remove(id);
                continue;
            }
            if (NativeMethods.IsKeyDown(registration.Combo.VirtualKey)) continue;
            held.Remove(id);
            registration.Handler(HotKeyEventKind.Released);
        }
        if (held.Count == 0) releaseTimer.Stop();
    }

    public void Dispose()
    {
        releaseTimer.Stop();
        foreach (var id in registrations.Keys.ToArray()) Unregister(id);
        source.RemoveHook(WndProc);
        source.Dispose();
    }
}
