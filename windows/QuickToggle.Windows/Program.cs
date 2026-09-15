using System.Reflection;
using System.Security.Principal;

namespace QuickToggle;

internal static class Program
{
    internal static string Version => typeof(Program).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion.Split('+')[0] ?? "1.0.0";

    [STAThread]
    private static int Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        if (args.Contains("--test-window"))
        {
            using var window = new Form { Text = "QuickToggle native test window", Size = new(360, 220) };
            using var timer = new System.Windows.Forms.Timer { Interval = 20000 };
            timer.Tick += (_, _) => window.Close(); timer.Start();
            Application.Run(window); return 0;
        }
        if (args.Contains("--self-test")) return SelfTests.Run();
        if (args.Contains("--ui-smoke-test")) return SelfTests.UI(args.SkipWhile(arg => arg != "--ui-smoke-test").Skip(1).FirstOrDefault());
        string sid = WindowsIdentity.GetCurrent().User?.Value ?? Environment.UserName;
        using var mutex = new Mutex(true, @"Local\QuickToggle.Instance." + sid, out bool first);
        using var signal = new EventWaitHandle(false, EventResetMode.AutoReset, @"Local\QuickToggle.Show." + sid);
        if (!first) { signal.Set(); return 0; }
        try
        {
            string path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "QuickToggle", "settings.json");
            var store = new ConfigurationStore(path);
            AppSettings settings;
            string? error = null;
            try { settings = store.Load(); }
            catch (Exception loadError) { settings = new(); error = loadError.Message; }
            using var form = new MainForm(store, settings, error);
            _ = form.Handle;
            var wait = ThreadPool.RegisterWaitForSingleObject(signal, (_, _) =>
            {
                try { if (!form.IsDisposed) form.BeginInvoke(form.Reopen); }
                catch (InvalidOperationException) { /* The first instance is exiting. */ }
            }, null, Timeout.Infinite, false);
            try
            {
                if (args.Contains("--background")) form.Shown += (_, _) => form.Hide();
                Application.Run(form);
            }
            finally { wait.Unregister(null); }
            return 0;
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "轻唤无法启动", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        finally { mutex.ReleaseMutex(); }
    }
}
