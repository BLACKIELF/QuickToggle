using System.ComponentModel;
using System.Runtime.InteropServices;

namespace QuickToggle;

internal interface IHotkeyBackend
{
    string? Register(int id, Shortcut shortcut);
    void Unregister(int id);
}

internal sealed class HotkeyWindow : NativeWindow, IHotkeyBackend, IDisposable
{
    public event Action<int>? Pressed;
    public HotkeyWindow() => CreateHandle(new CreateParams { Caption = "QuickToggle Hotkeys", Parent = new IntPtr(-3) });
    public string? Register(int id, Shortcut shortcut) => Native.RegisterHotKey(Handle, id, shortcut.Modifiers | 0x4000, shortcut.Key)
        ? null : new Win32Exception(Marshal.GetLastWin32Error()).Message;
    public void Unregister(int id) => Native.UnregisterHotKey(Handle, id);
    protected override void WndProc(ref Message message)
    {
        if (message.Msg == 0x0312) Pressed?.Invoke(message.WParam.ToInt32());
        base.WndProc(ref message);
    }
    public void Dispose() => DestroyHandle();
}

internal sealed class HotkeyRegistry(IHotkeyBackend backend) : IDisposable
{
    private readonly Dictionary<int, Guid> active = [];
    private AppSettings current = new();
    private int nextId = 100;
    public Dictionary<Guid, string> Failures { get; private set; } = [];
    public int ActiveCount => active.Count;
    public bool TryResolve(int id, out Guid binding) => active.TryGetValue(id, out binding);
    public bool IsActive(Guid binding) => active.ContainsValue(binding);

    private static Dictionary<Guid, Shortcut> Desired(AppSettings settings)
    {
        var desired = new Dictionary<Guid, Shortcut> { [Guid.Empty] = settings.SettingsHotkey };
        if (settings.Enabled)
            foreach (var app in settings.Apps)
                if (app.Hotkey is not null) desired.Add(app.Id, app.Hotkey);
        return desired;
    }

    public void Load(AppSettings settings)
    {
        Clear();
        Failures = [];
        foreach (var (binding, shortcut) in Desired(settings))
        {
            if (nextId > 0xBFFF)
            {
                Failures[binding] = "本次运行的快捷键变更次数已达上限，请退出并重新打开轻唤。";
                continue;
            }
            int id = nextId++;
            string? error = backend.Register(id, shortcut);
            if (error is null) active.Add(id, binding);
            else Failures[binding] = $"{shortcut} 注册失败：{error}";
        }
        current = settings.Copy();
    }

    public bool TryApply(AppSettings settings, out string error)
    {
        settings.Validate();
        var previous = current.Copy();
        var previousFailures = new Dictionary<Guid, string>(Failures);
        var previousDesired = Desired(previous);
        Load(settings);
        var desired = Desired(settings);
        var newFailures = Failures.Where(pair => !previousFailures.ContainsKey(pair.Key)
            || !previousDesired.TryGetValue(pair.Key, out var old) || old != desired[pair.Key]).ToArray();
        if (newFailures.Length == 0) { error = ""; return true; }
        error = string.Join("\n", newFailures.Select(pair => pair.Value));
        Load(previous);
        if (Failures.Keys.Except(previousFailures.Keys).Any()) error += "\n部分原快捷键也无法恢复，请查看占用筛选并重试注册。";
        return false;
    }

    public void Clear()
    {
        foreach (int id in active.Keys) backend.Unregister(id);
        active.Clear();
    }
    public void Dispose() => Clear();
}
