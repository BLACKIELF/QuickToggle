using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace QuickToggle;

internal static class Native
{
    [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool UnregisterHotKey(IntPtr window, int id);
    [DllImport("user32.dll")] internal static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool ShowWindowAsync(IntPtr window, int command);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] internal static extern IntPtr GetWindow(IntPtr window, uint command);
    [DllImport("user32.dll")] internal static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    internal delegate bool EnumWindowsCallback(IntPtr window, IntPtr parameter);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool EnumWindows(EnumWindowsCallback callback, IntPtr parameter);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    internal static extern int GetWindowText(IntPtr window, StringBuilder text, int maximum);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint access, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint processId);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool QueryFullProcessImageName(IntPtr process, uint flags, StringBuilder name, ref uint size);
    [DllImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr handle);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool FlashWindowEx(ref FlashInfo info);
    [StructLayout(LayoutKind.Sequential)]
    private struct FlashInfo { public uint Size; public IntPtr Window; public uint Flags; public uint Count; public uint Timeout; }

    internal static void Flash(IntPtr window)
    {
        var info = new FlashInfo { Size = (uint)Marshal.SizeOf<FlashInfo>(), Window = window, Flags = 3, Count = 3 };
        FlashWindowEx(ref info);
    }

    internal static string? ProcessPath(uint processId)
    {
        IntPtr process = OpenProcess(0x1000, false, processId);
        if (process == IntPtr.Zero) return null;
        try
        {
            uint length = 32768;
            var path = new StringBuilder((int)length);
            return QueryFullProcessImageName(process, 0, path, ref length) ? path.ToString() : null;
        }
        finally { CloseHandle(process); }
    }

    internal static List<(IntPtr Window, uint ProcessId, string Path, string Title)> Windows()
    {
        var windows = new List<(IntPtr, uint, string, string)>();
        EnumWindows((window, _) =>
        {
            if (!IsWindowVisible(window) || GetWindow(window, 4) != IntPtr.Zero) return true;
            GetWindowThreadProcessId(window, out uint pid);
            if (pid == Environment.ProcessId) return true;
            string? path = ProcessPath(pid);
            if (path is null) return true;
            var title = new StringBuilder(512);
            GetWindowText(window, title, title.Capacity);
            if (title.Length != 0) windows.Add((window, pid, path, title.ToString()));
            return true;
        }, IntPtr.Zero);
        return windows;
    }
}

internal sealed record WindowIdentity(IntPtr Handle, uint ProcessId, long StartedAt)
{
    internal static WindowIdentity? Capture(IntPtr window)
    {
        if (window == IntPtr.Zero || !Native.IsWindow(window)) return null;
        Native.GetWindowThreadProcessId(window, out uint pid);
        try
        {
            using var process = Process.GetProcessById((int)pid);
            return new(window, pid, process.StartTime.ToUniversalTime().Ticks);
        }
        catch (Exception error) when (error is ArgumentException or InvalidOperationException or System.ComponentModel.Win32Exception) { return null; }
    }
    internal bool StillValid() => Capture(Handle) == this;
}

internal sealed class ToggleEngine : IDisposable
{
    private readonly Dictionary<Guid, WindowIdentity> previous = [];
    private readonly Dictionary<Guid, CancellationTokenSource> pending = [];
    private bool disposed;

    public async Task<string> ToggleAsync(AppBinding app)
    {
        if (disposed) return "轻唤正在退出。";
        if (pending.ContainsKey(app.Id)) return $"{app.Name} 正在启动，请稍候。";
        var target = FindWindow(app);
        if (target != IntPtr.Zero) return ToggleWindow(app, target);
        if (!app.LaunchIfNeeded) return $"{app.Name} 没有可切换的窗口；可在设置中允许启动。";
        if (!File.Exists(app.Executable)) return $"找不到 {app.Name}，请编辑应用路径。";
        using var cancellation = new CancellationTokenSource();
        pending.Add(app.Id, cancellation);
        var beforeLaunch = WindowIdentity.Capture(Native.GetForegroundWindow());
        try
        {
            using var process = Process.Start(new ProcessStartInfo(app.Executable, app.Arguments)
            {
                UseShellExecute = true,
                WorkingDirectory = Path.GetDirectoryName(app.Executable)!
            });
            for (int attempt = 0; attempt < 50; attempt++)
            {
                await Task.Delay(200, cancellation.Token);
                target = FindWindow(app);
                if (target == IntPtr.Zero) continue;
                // A late launch must not steal focus after the user has moved elsewhere.
                IntPtr foreground = Native.GetForegroundWindow();
                Native.GetWindowThreadProcessId(foreground, out uint foregroundPid);
                Native.GetWindowThreadProcessId(target, out uint targetPid);
                if (foregroundPid != targetPid && foreground != beforeLaunch?.Handle)
                {
                    Native.Flash(target);
                    return $"{app.Name} 已启动；点击任务栏可切换到它。";
                }
                if (beforeLaunch is not null && beforeLaunch.ProcessId != targetPid) previous[app.Id] = beforeLaunch;
                return Reveal(app, target);
            }
            return $"已请求启动 {app.Name}，10 秒内未发现窗口；请检查启动画面或托盘。";
        }
        catch (OperationCanceledException) { return "已取消等待应用窗口。"; }
        catch (Exception error) when (error is System.ComponentModel.Win32Exception or InvalidOperationException or IOException)
        { return $"无法启动 {app.Name}：{error.Message}"; }
        finally { pending.Remove(app.Id); }
    }

    private static IntPtr FindWindow(AppBinding app)
    {
        var matches = Native.Windows().Where(window => string.Equals(window.Path, app.Executable, StringComparison.OrdinalIgnoreCase)).ToArray();
        IntPtr foreground = Native.GetForegroundWindow();
        return matches.Any(window => window.Window == foreground) ? foreground : matches.FirstOrDefault().Window;
    }

    private string ToggleWindow(AppBinding app, IntPtr target)
    {
        if (!Native.IsWindow(target)) return "应用窗口已关闭，请重试。";
        Native.GetWindowThreadProcessId(target, out uint targetPid);
        if (!string.Equals(Native.ProcessPath(targetPid), app.Executable, StringComparison.OrdinalIgnoreCase)) return "应用窗口已变化，请重试。";
        var foreground = WindowIdentity.Capture(Native.GetForegroundWindow());
        if (foreground?.ProcessId == targetPid)
        {
            bool requested = Native.ShowWindowAsync(target, 6);
            if (!requested) return $"{app.Name} 未接受最小化请求。";
            if (previous.Remove(app.Id, out var last) && last.StillValid()) Native.SetForegroundWindow(last.Handle);
            return $"已请求最小化 {app.Name}。";
        }
        if (foreground is not null) previous[app.Id] = foreground;
        return Reveal(app, target);
    }

    private static string Reveal(AppBinding app, IntPtr target)
    {
        if (Native.IsIconic(target)) Native.ShowWindowAsync(target, 9);
        if (Native.SetForegroundWindow(target)) return $"已呼出 {app.Name}。";
        Native.Flash(target);
        return $"{app.Name} 已在任务栏提示；Windows 暂未允许切换前台。";
    }

    public void CancelPending()
    {
        foreach (var cancellation in pending.Values) cancellation.Cancel();
        previous.Clear();
    }
    public void Dispose() { disposed = true; CancelPending(); }
}
