using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace QuickToggle;

internal static class Startup
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string Name = "QuickToggle";
    private static string Command => $"\"{Environment.ProcessPath}\" --background";
    public static bool Enabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey);
        return string.Equals(key?.GetValue(Name) as string, Command, StringComparison.OrdinalIgnoreCase);
    }
    public static void Set(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKey, true);
        if (enabled) key.SetValue(Name, Command, RegistryValueKind.String);
        else key.DeleteValue(Name, false);
        if (Enabled() != enabled) throw new IOException("未能确认开机启动设置，请重试。");
    }
}

internal static class AppPicker
{
    public static string? Choose(IWin32Window owner)
    {
        using var dialog = new OpenFileDialog { Title = "选择应用或快捷方式", Filter = "应用或快捷方式|*.exe;*.lnk", CheckFileExists = true };
        if (dialog.ShowDialog(owner) != DialogResult.OK) return null;
        string path = dialog.FileName;
        if (Path.GetExtension(path).Equals(".lnk", StringComparison.OrdinalIgnoreCase))
        {
            object? shell = null, shortcut = null;
            try
            {
                var type = Type.GetTypeFromProgID("WScript.Shell") ?? throw new IOException("系统无法读取此快捷方式，请直接选择 .exe。");
                shell = Activator.CreateInstance(type)!;
                shortcut = ((dynamic)shell).CreateShortcut(path);
                string arguments = ((dynamic)shortcut).Arguments;
                path = ((dynamic)shortcut).TargetPath;
                if (!string.IsNullOrWhiteSpace(arguments))
                    throw new IOException("此快捷方式包含启动参数。请直接选择其 .exe，并在编辑窗口填写所需参数。");
            }
            finally
            {
                if (shortcut is not null && Marshal.IsComObject(shortcut)) Marshal.FinalReleaseComObject(shortcut);
                if (shell is not null && Marshal.IsComObject(shell)) Marshal.FinalReleaseComObject(shell);
            }
        }
        if (!Path.GetExtension(path).Equals(".exe", StringComparison.OrdinalIgnoreCase) || !File.Exists(path))
            throw new IOException("只支持指向本地 .exe 的应用快捷方式。商店应用入口暂不支持。");
        return Path.GetFullPath(path);
    }

    public static AppBinding? Running(IWin32Window owner)
    {
        var apps = Native.Windows().GroupBy(window => window.Path, StringComparer.OrdinalIgnoreCase)
            .Select(group => new AppBinding { Name = Path.GetFileNameWithoutExtension(group.Key), Executable = group.Key })
            .OrderBy(app => app.Name, StringComparer.CurrentCultureIgnoreCase).ToArray();
        using var dialog = new Form { Text = "从运行中的应用添加", Size = new(560, 420), MinimumSize = new(420, 320), StartPosition = FormStartPosition.CenterParent };
        var list = new ListBox { Dock = DockStyle.Fill, DisplayMember = nameof(AppBinding.Name), DataSource = apps };
        var add = new Button { Text = "添加所选应用", Dock = DockStyle.Bottom, Height = 42, DialogResult = DialogResult.OK };
        dialog.Controls.Add(list);
        dialog.Controls.Add(add);
        dialog.AcceptButton = add;
        list.DoubleClick += (_, _) => { if (list.SelectedItem is not null) { dialog.DialogResult = DialogResult.OK; dialog.Close(); } };
        return dialog.ShowDialog(owner) == DialogResult.OK ? list.SelectedItem as AppBinding : null;
    }
}

internal sealed class BindingDialog : Form
{
    private readonly TextBox name = new() { Dock = DockStyle.Fill };
    private readonly TextBox executable = new() { Dock = DockStyle.Fill };
    private readonly TextBox arguments = new() { Dock = DockStyle.Fill };
    private readonly CheckBox launch = new() { Text = "未运行时允许启动", AutoSize = true };
    private readonly AppBinding original;
    public AppBinding? Result { get; private set; }

    public BindingDialog(AppBinding binding)
    {
        original = binding;
        Text = "编辑应用";
        ClientSize = new(620, 250);
        MinimumSize = new(520, 290);
        StartPosition = FormStartPosition.CenterParent;
        var table = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new(16), ColumnCount = 3, RowCount = 5 };
        table.ColumnStyles.Add(new(SizeType.Absolute, 76));
        table.ColumnStyles.Add(new(SizeType.Percent, 100));
        table.ColumnStyles.Add(new(SizeType.Absolute, 80));
        for (int i = 0; i < 5; i++) table.RowStyles.Add(new(SizeType.Percent, 20));
        name.Text = binding.Name; executable.Text = binding.Executable; arguments.Text = binding.Arguments; launch.Checked = binding.LaunchIfNeeded;
        table.Controls.Add(new Label { Text = "名称", AutoSize = true }, 0, 0); table.Controls.Add(name, 1, 0); table.SetColumnSpan(name, 2);
        table.Controls.Add(new Label { Text = "应用路径", AutoSize = true }, 0, 1); table.Controls.Add(executable, 1, 1);
        var browse = new Button { Text = "选择…", AutoSize = true };
        browse.Click += (_, _) =>
        {
            try { if (AppPicker.Choose(this) is string path) executable.Text = path; }
            catch (Exception error) { MessageBox.Show(this, error.Message, "无法选择应用"); }
        };
        table.Controls.Add(browse, 2, 1);
        table.Controls.Add(new Label { Text = "启动参数", AutoSize = true }, 0, 2); table.Controls.Add(arguments, 1, 2); table.SetColumnSpan(arguments, 2);
        table.Controls.Add(launch, 1, 3); table.SetColumnSpan(launch, 2);
        var buttons = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.RightToLeft, Dock = DockStyle.Fill };
        var save = new Button { Text = "保存", AutoSize = true };
        var cancel = new Button { Text = "取消", AutoSize = true, DialogResult = DialogResult.Cancel };
        buttons.Controls.Add(save); buttons.Controls.Add(cancel);
        table.Controls.Add(buttons, 0, 4); table.SetColumnSpan(buttons, 3);
        save.Click += (_, _) =>
        {
            try
            {
                var candidate = new AppBinding { Id = original.Id, Name = name.Text.Trim(), Executable = executable.Text.Trim(), Arguments = arguments.Text, LaunchIfNeeded = launch.Checked, Hotkey = original.Hotkey };
                new AppSettings { Apps = [candidate] }.Validate();
                if (!File.Exists(candidate.Executable)) throw new IOException("找不到应用文件，请重新选择。");
                Result = candidate; DialogResult = DialogResult.OK; Close();
            }
            catch (Exception error) { MessageBox.Show(this, error.Message, "无法保存"); }
        };
        AcceptButton = save; CancelButton = cancel; Controls.Add(table);
    }
}

internal sealed class ShortcutDialog : Form
{
    private readonly Label value = new() { Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter };
    private readonly Button save = new() { Text = "使用此快捷键", AutoSize = true };
    public Shortcut? Result { get; private set; }
    public ShortcutDialog(Shortcut? initial, bool allowClear)
    {
        Text = "录制快捷键"; ClientSize = new(490, 210); FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false; MinimizeBox = false; StartPosition = FormStartPosition.CenterParent;
        Result = initial; value.Text = initial?.ToString() ?? "按下 Ctrl / Alt + 字母、数字或 F1–F11";
        var hint = new Label { Text = "直接按下组合键；Esc 取消。录制期间暂停应用热键。", Dock = DockStyle.Top, Height = 45, TextAlign = ContentAlignment.MiddleCenter };
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 48, FlowDirection = FlowDirection.RightToLeft };
        save.Enabled = initial is not null; save.Click += (_, _) => { DialogResult = DialogResult.OK; Close(); };
        buttons.Controls.Add(save);
        buttons.Controls.Add(new Button { Text = "取消", AutoSize = true, DialogResult = DialogResult.Cancel });
        if (allowClear)
        {
            var clear = new Button { Text = "清除", AutoSize = true };
            clear.Click += (_, _) => { Result = null; DialogResult = DialogResult.OK; Close(); };
            buttons.Controls.Add(clear);
        }
        Controls.Add(value); Controls.Add(hint); Controls.Add(buttons);
    }
    protected override bool ProcessCmdKey(ref Message message, Keys keyData)
    {
        if (keyData == Keys.Escape) { DialogResult = DialogResult.Cancel; Close(); return true; }
        if (keyData == Keys.Tab || keyData == (Keys.Shift | Keys.Tab)) return base.ProcessCmdKey(ref message, keyData);
        if ((keyData & Keys.KeyCode) is Keys.ControlKey or Keys.ShiftKey or Keys.Menu or Keys.LWin or Keys.RWin) return true;
        var shortcut = Shortcut.FromKeyData(keyData);
        string? error = shortcut.Validate();
        value.Text = error ?? shortcut.ToString(); save.Enabled = error is null;
        if (error is null) Result = shortcut;
        return true;
    }
}
