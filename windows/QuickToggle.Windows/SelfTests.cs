using System.Drawing.Imaging;

namespace QuickToggle;

internal sealed class TestHotkeyBackend : IHotkeyBackend
{
    internal HashSet<Shortcut> Occupied { get; } = [];
    internal Dictionary<int, Shortcut> Active { get; } = [];
    public string? Register(int id, Shortcut shortcut)
    {
        if (Occupied.Contains(shortcut) || Active.ContainsValue(shortcut)) return "快捷键已被占用";
        Active.Add(id, shortcut); return null;
    }
    public void Unregister(int id) => Active.Remove(id);
}

internal static class SelfTests
{
    private static void Check(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }
    private static void Reject(Action action)
    {
        try { action(); } catch (InvalidDataException) { return; }
        throw new InvalidOperationException("Expected invalid data rejection");
    }
    internal static AppSettings Fixture() => new()
    {
        Apps = [
            new() { Name = "记事本", Executable = @"C:\Windows\System32\notepad.exe", Hotkey = new(3, (uint)Keys.D1) },
            new() { Name = "计算器", Executable = @"C:\Windows\System32\calc.exe" }
        ]
    };

    internal static int Run()
    {
        int passed = 0, failed = 0;
        void Test(string name, Action action)
        {
            try { action(); Console.WriteLine($"PASS {name}"); passed++; }
            catch (Exception error) { Console.Error.WriteLine($"FAIL {name}: {error}"); failed++; }
        }
        Test("supported shortcuts and reserved keys", () =>
        {
            Check(new Shortcut(3, (uint)Keys.D1).Validate() is null, "Ctrl+Alt+1");
            Check(new Shortcut(6, (uint)Keys.F11).Validate() is null, "Ctrl+Shift+F11");
            foreach (var key in new[] { new Shortcut(0, 65), new Shortcut(8, 65), new Shortcut(3, (uint)Keys.F12), new Shortcut(1, (uint)Keys.F4), new Shortcut(3, (uint)Keys.Delete) })
                Check(key.Validate() is not null, "Reserved key was accepted");
            Check(Shortcut.FromKeyData(Keys.Control | Keys.Alt | Keys.D1) == new Shortcut(3, 49), "key capture");
        });
        Test("duplicate bindings and settings shortcut collision", () =>
        {
            var settings = Fixture(); settings.Apps[1].Id = settings.Apps[0].Id; Reject(settings.Validate);
            settings = Fixture(); settings.Apps[1].Executable = settings.Apps[0].Executable.ToUpperInvariant(); Reject(settings.Validate);
            settings = Fixture(); settings.Apps[0].Hotkey = settings.SettingsHotkey; Reject(settings.Validate);
            settings = Fixture(); settings.Platform = "macos"; Reject(settings.Validate);
            settings = Fixture(); settings.SchemaVersion = 2; Reject(settings.Validate);
        });
        Test("path and null input validation", () =>
        {
            var settings = Fixture(); settings.Apps[0].Executable = "relative.exe"; Reject(settings.Validate);
            settings = Fixture(); settings.Apps[0].Executable = @"C:\script.ps1"; Reject(settings.Validate);
            settings = Fixture(); settings.Apps = null!; Reject(settings.Validate);
            settings = Fixture(); settings.Apps[0].Arguments = null!; Reject(settings.Validate);
        });
        Test("configuration roundtrip, backup, corrupt recovery and size limit", () =>
        {
            string directory = Path.Combine(Path.GetTempPath(), "QuickToggle-tests-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(directory);
            try
            {
                string path = Path.Combine(directory, "settings.json");
                var store = new ConfigurationStore(path); var settings = Fixture();
                Check(store.Load().Apps.Count == 0 && !File.Exists(path), "missing config must not write");
                store.Save(settings); settings.Enabled = false; store.Save(settings);
                Check(!store.Load().Enabled && ConfigurationStore.Read(path + ".bak").Enabled, "backup must retain preceding state");
                File.WriteAllText(path, "{broken");
                try { store.Load(); } catch (System.Text.Json.JsonException) { }
                Check(store.RecoveryRequired, "corrupt config must block writes");
                Reject(() => store.Save(settings));
                Check(File.ReadAllText(path) == "{broken", "corrupt original was overwritten");
                store.Save(settings, recover: true);
                Check(File.ReadAllText(path + ".bak") == "{broken", "recovery must preserve corrupt bytes");
                Check(store.Load().Apps.Count == 2 && !store.RecoveryRequired, "recovery");
                File.WriteAllBytes(path, new byte[ConfigurationStore.MaximumBytes + 1]); Reject(() => ConfigurationStore.Read(path));
                Check(Directory.GetFiles(directory, "*.tmp").Length == 0, "temporary file leak");
            }
            finally { Directory.Delete(directory, recursive: true); }
        });
        Test("hotkey conflict rollback and stale message rejection", () =>
        {
            var backend = new TestHotkeyBackend(); using var registry = new HotkeyRegistry(backend);
            var original = Fixture(); registry.Load(original);
            int staleId = backend.Active.Keys.First();
            var candidate = original.Copy(); var occupied = new Shortcut(3, (uint)Keys.D2);
            candidate.Apps[0].Hotkey = occupied; backend.Occupied.Add(occupied);
            Check(!registry.TryApply(candidate, out string error) && error.Length > 0, "conflict must fail");
            Check(backend.Active.ContainsValue(original.Apps[0].Hotkey!), "old shortcut not restored");
            Check(!backend.Active.ContainsValue(occupied), "failed candidate active");
            Check(!registry.TryResolve(staleId, out _), "stale WM_HOTKEY must be ignored");
            Check(registry.ActiveCount == 2, "registration leak");
            candidate = original.Copy(); candidate.Enabled = false;
            Check(registry.TryApply(candidate, out _), "pause");
            Check(registry.ActiveCount == 1 && registry.IsActive(Guid.Empty), "pause must retain settings key only");
        });
        Test("startup conflicts leave other app hotkeys active", () =>
        {
            var backend = new TestHotkeyBackend(); var settings = Fixture();
            backend.Occupied.Add(settings.Apps[0].Hotkey!);
            using var registry = new HotkeyRegistry(backend); registry.Load(settings);
            Check(registry.Failures.Count == 1 && registry.IsActive(Guid.Empty), "partial startup");
            var edit = settings.Copy(); edit.Apps[1].Name = "Calculator";
            Check(registry.TryApply(edit, out _), "existing external conflict must not block unrelated edits");
            registry.Clear(); Check(backend.Active.Count == 0, "unregister all");
        });
        Test("native RegisterHotKey detects collision and releases ownership", () =>
        {
            using var first = new HotkeyWindow(); using var second = new HotkeyWindow();
            Shortcut? available = null;
            foreach (Keys key in new[] { Keys.F10, Keys.F9, Keys.F8, Keys.F7 })
            {
                var candidate = new Shortcut(7, (uint)key);
                if (first.Register(700, candidate) is null) { available = candidate; break; }
            }
            Check(available is not null, "no test shortcut available on this runner");
            try
            {
                Check(second.Register(701, available!) is not null, "native collision not detected");
                first.Unregister(700);
                Check(second.Register(701, available!) is null, "native shortcut not released");
            }
            finally { first.Unregister(700); second.Unregister(701); }
        });
        Console.WriteLine($"Self-tests: {passed} passed, {failed} failed; {System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture}");
        return failed == 0 ? 0 : 1;
    }

    internal static int UI(string? output)
    {
        string directory = output ?? Path.Combine(Path.GetTempPath(), "QuickToggle-ui-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        string settingsPath = Path.Combine(directory, "must-not-create-settings.json");
        int result = 1;
        using var form = new MainForm(new ConfigurationStore(settingsPath), Fixture(), fixture: true);
        form.Shown += (_, _) => form.BeginInvoke((Action)(() =>
        {
            try
            {
                Check(form.Grid.Rows.Count == 2, "initial rows");
                form.Search.Text = "记事"; Check(form.Grid.Rows.Count == 1, "Chinese search");
                form.Search.Text = "no-match"; Check(form.Grid.Rows.Count == 0, "empty search");
                form.Search.Clear(); form.Filter.SelectedIndex = 1; Check(form.Grid.Rows.Count == 1, "pending filter");
                form.Filter.SelectedIndex = 2; Check(form.Grid.Rows.Count == 0, "conflict filter");
                form.Filter.SelectedIndex = 0;
                foreach (var size in new[] { new Size(720, 470), new Size(920, 660), new Size(1280, 820) })
                {
                    form.Size = size; form.PerformLayout(); form.Update();
                    Check(form.Grid.Width > 500 && form.Grid.Height > 100, "list collapsed");
                    var bounds = form.RectangleToClient(form.Grid.RectangleToScreen(form.Grid.ClientRectangle));
                    Check(form.ClientRectangle.Contains(bounds), "list outside window");
                    using var bitmap = new Bitmap(form.Width, form.Height);
                    form.DrawToBitmap(bitmap, new Rectangle(Point.Empty, bitmap.Size));
                    bitmap.Save(Path.Combine(directory, $"windows-{size.Width}.png"), ImageFormat.Png);
                }
                Check(!File.Exists(settingsPath), "UI fixture changed preferences");
                Console.WriteLine("PASS UI: search, filters, 720/920/1280 layout, isolated preferences");
                result = 0;
            }
            catch (Exception error) { Console.Error.WriteLine(error); }
            finally { form.Close(); }
        }));
        Application.Run(form);
        return result;
    }
}
