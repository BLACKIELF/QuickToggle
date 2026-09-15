namespace QuickToggle;

internal sealed class MainForm : Form
{
    private readonly ConfigurationStore store;
    private readonly HotkeyWindow? hotkeyWindow;
    private readonly HotkeyRegistry hotkeys;
    private readonly ToggleEngine engine = new();
    private readonly bool fixture;
    private readonly NotifyIcon? tray;
    private readonly Button enabled = new() { AutoSize = true };
    private readonly Label feedback = new() { Dock = DockStyle.Fill, AutoEllipsis = true, TextAlign = ContentAlignment.MiddleLeft };
    internal TextBox Search { get; } = new() { PlaceholderText = "搜索应用名称或路径", Dock = DockStyle.Fill, AccessibleName = "搜索应用" };
    internal ComboBox Filter { get; } = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 112, AccessibleName = "筛选应用" };
    internal DataGridView Grid { get; } = new()
    {
        Dock = DockStyle.Fill, ReadOnly = true, AllowUserToAddRows = false, AllowUserToDeleteRows = false,
        MultiSelect = false, SelectionMode = DataGridViewSelectionMode.FullRowSelect, RowHeadersVisible = false,
        AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill, BackgroundColor = SystemColors.Window,
        BorderStyle = BorderStyle.FixedSingle, AllowUserToResizeRows = false, AccessibleName = "应用快捷键列表"
    };
    internal AppSettings Settings { get; private set; }
    private bool exiting;
    private bool recording;
    private int generation;

    internal MainForm(ConfigurationStore store, AppSettings settings, string? loadError = null, bool fixture = false)
    {
        this.store = store; Settings = settings; this.fixture = fixture;
        Text = $"轻唤 QuickToggle · {Program.Version} · Windows 预览版";
        ClientSize = new(920, 620); MinimumSize = new(720, 470); StartPosition = FormStartPosition.CenterScreen;
        Icon = SystemIcons.Application;
        if (fixture) hotkeys = new(new TestHotkeyBackend());
        else
        {
            hotkeyWindow = new(); hotkeys = new(hotkeyWindow);
            hotkeyWindow.Pressed += id =>
            {
                if (recording || !hotkeys.TryResolve(id, out var binding)) return;
                if (binding == Guid.Empty) { if (Visible && ContainsFocus) Hide(); else Reopen(); }
                else if (Settings.Apps.FirstOrDefault(app => app.Id == binding) is AppBinding app) _ = Toggle(app);
            };
        }
        var root = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new(18), ColumnCount = 1, RowCount = 5 };
        root.ColumnStyles.Add(new(SizeType.Percent, 100));
        root.RowStyles.Add(new(SizeType.Absolute, 56));
        root.RowStyles.Add(new(SizeType.Absolute, 42));
        root.RowStyles.Add(new(SizeType.Absolute, 76));
        root.RowStyles.Add(new(SizeType.Percent, 100));
        root.RowStyles.Add(new(SizeType.Absolute, 60));
        var title = new Label { Text = "轻唤\n按一次呼出，再按一次最小化。关闭窗口后继续在托盘运行。", Dock = DockStyle.Fill, AutoSize = false };
        root.Controls.Add(title, 0, 0);
        var searchRow = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 3 };
        searchRow.ColumnStyles.Add(new(SizeType.Percent, 100)); searchRow.ColumnStyles.Add(new(SizeType.Absolute, 125)); searchRow.ColumnStyles.Add(new(SizeType.Absolute, 112));
        Filter.Items.AddRange(["全部应用", "待设置", "占用 / 失败"]); Filter.SelectedIndex = 0;
        enabled.Click += (_, _) => Change(candidate => candidate.Enabled = !candidate.Enabled, "已更新应用热键状态。");
        searchRow.Controls.Add(Search, 0, 0); searchRow.Controls.Add(Filter, 1, 0); searchRow.Controls.Add(enabled, 2, 0);
        root.Controls.Add(searchRow, 0, 1);
        var actions = new FlowLayoutPanel { Dock = DockStyle.Fill, WrapContents = true };
        AddButton(actions, "添加应用…", AddApplication);
        AddButton(actions, "从运行中添加…", AddRunning);
        AddButton(actions, "呼出 / 最小化", () => { if (Selected() is AppBinding app) _ = Toggle(app); });
        AddButton(actions, "编辑…", EditApplication);
        AddButton(actions, "快捷键…", RecordApplication);
        AddButton(actions, "移除", RemoveApplication);
        AddButton(actions, "设置与帮助…", ShowSettings);
        root.Controls.Add(actions, 0, 2);
        Grid.Columns.Add(new DataGridViewTextBoxColumn { Name = "App", HeaderText = "应用（双击呼出）", FillWeight = 35 });
        Grid.Columns.Add(new DataGridViewTextBoxColumn { Name = "Shortcut", HeaderText = "快捷键", FillWeight = 25 });
        Grid.Columns.Add(new DataGridViewTextBoxColumn { Name = "State", HeaderText = "状态", FillWeight = 40 });
        Grid.RowTemplate.Height = 38; Grid.AutoSizeRowsMode = DataGridViewAutoSizeRowsMode.AllCells;
        Grid.DefaultCellStyle.WrapMode = DataGridViewTriState.True;
        Grid.CellDoubleClick += (_, args) => { if (args.RowIndex >= 0 && Selected() is AppBinding app) _ = Toggle(app); };
        Grid.KeyDown += (_, args) =>
        {
            if (args.KeyCode == Keys.Enter && Selected() is AppBinding app) { args.Handled = true; args.SuppressKeyPress = true; _ = Toggle(app); }
        };
        root.Controls.Add(Grid, 0, 3); root.Controls.Add(feedback, 0, 4); Controls.Add(root);
        Search.TextChanged += (_, _) => RefreshRows(); Filter.SelectedIndexChanged += (_, _) => RefreshRows();
        hotkeys.Load(settings);
        if (!fixture)
        {
            tray = new NotifyIcon { Icon = Icon, Text = "轻唤 QuickToggle", Visible = true };
            tray.DoubleClick += (_, _) => Reopen();
        }
        FormClosing += (_, args) =>
        {
            if (!exiting && args.CloseReason == CloseReason.UserClosing && !fixture) { args.Cancel = true; Hide(); }
        };
        RefreshRows();
        SetFeedback(loadError is null ? Summary() : $"配置未载入：{loadError} 原文件已保留；请从设置导入有效备份。");
    }

    private static void AddButton(Control parent, string text, Action action)
    {
        var button = new Button { Text = text, AutoSize = true, Height = 30, Padding = new(4, 0, 4, 0) };
        button.Click += (_, _) => action(); parent.Controls.Add(button);
    }

    private AppBinding? Selected()
    {
        if (Grid.SelectedRows.Count == 0) { SetFeedback("请先在列表中选择应用。"); return null; }
        return Settings.Apps.FirstOrDefault(app => app.Id == (Guid)Grid.SelectedRows[0].Tag!);
    }

    internal void RefreshRows()
    {
        Guid? selected = Grid.SelectedRows.Count > 0 ? Grid.SelectedRows[0].Tag as Guid? : null;
        Grid.Rows.Clear();
        string search = Search.Text.Trim();
        foreach (var app in Settings.Apps)
        {
            if (search.Length > 0 && !app.Name.Contains(search, StringComparison.CurrentCultureIgnoreCase)
                && !app.Executable.Contains(search, StringComparison.OrdinalIgnoreCase)) continue;
            bool failed = hotkeys.Failures.ContainsKey(app.Id);
            if (Filter.SelectedIndex == 1 && app.Hotkey is not null) continue;
            if (Filter.SelectedIndex == 2 && !failed) continue;
            string state = failed ? hotkeys.Failures[app.Id] : app.Hotkey is null ? "待设置快捷键"
                : !Settings.Enabled ? "已暂停" : hotkeys.IsActive(app.Id) ? "已注册" : "未注册";
            int row = Grid.Rows.Add(app.Name, app.Hotkey?.ToString() ?? "未设置", state);
            Grid.Rows[row].Tag = app.Id;
            Grid.Rows[row].Cells[0].ToolTipText = app.Executable;
            if (selected == app.Id) Grid.Rows[row].Selected = true;
        }
        enabled.Text = Settings.Enabled ? "暂停热键" : "启用热键";
        UpdateTray();
    }

    private string Summary() => $"{Settings.Apps.Count} 个应用 · 设置窗口：{Settings.SettingsHotkey}"
        + (hotkeys.Failures.TryGetValue(Guid.Empty, out var error) ? $" · {error}" : "");
    private void SetFeedback(string text) { if (!IsDisposed) feedback.Text = text; }

    private void UpdateTray()
    {
        if (tray is null) return;
        var old = tray.ContextMenuStrip;
        var menu = new ContextMenuStrip();
        menu.Items.Add("打开轻唤", null, (_, _) => Reopen());
        var apps = new ToolStripMenuItem("应用");
        foreach (var binding in Settings.Apps)
        {
            var item = apps.DropDownItems.Add(binding.Name);
            item.Click += (_, _) => _ = Toggle(binding);
        }
        menu.Items.Add(apps);
        menu.Items.Add(Settings.Enabled ? "暂停应用热键" : "启用应用热键", null, (_, _) => Change(candidate => candidate.Enabled = !candidate.Enabled, "已更新热键状态。"));
        menu.Items.Add("设置与帮助", null, (_, _) => { Reopen(); ShowSettings(); });
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("退出轻唤", null, (_, _) => { exiting = true; Close(); });
        tray.ContextMenuStrip = menu; old?.Dispose();
    }

    internal void Reopen()
    {
        if (IsDisposed) return;
        Show(); if (WindowState == FormWindowState.Minimized) WindowState = FormWindowState.Normal;
        Activate(); Search.Focus();
    }

    private async Task Toggle(AppBinding binding)
    {
        if (fixture) { SetFeedback($"预览操作：{binding.Name}"); return; }
        int startedGeneration = generation;
        SetFeedback($"正在切换 {binding.Name}…");
        string result = await engine.ToggleAsync(binding);
        if (startedGeneration == generation && !IsDisposed) SetFeedback(result);
    }

    private void Change(Action<AppSettings> edit, string success)
    {
        var candidate = Settings.Copy();
        try { edit(candidate); Commit(candidate); SetFeedback(success + " " + Summary()); }
        catch (Exception error) { SetFeedback(error.Message); }
        RefreshRows();
    }

    private void Commit(AppSettings candidate, bool recover = false)
    {
        candidate.Validate();
        if (!hotkeys.TryApply(candidate, out string error)) throw new InvalidOperationException(error);
        try { store.Save(candidate, recover); }
        catch { hotkeys.Load(Settings); throw; }
        generation++; engine.CancelPending(); Settings = candidate; RefreshRows();
    }

    private void AddApplication()
    {
        try
        {
            if (AppPicker.Choose(this) is not string path) return;
            var app = new AppBinding { Name = Path.GetFileNameWithoutExtension(path), Executable = path };
            Change(candidate => candidate.Apps.Add(app), "已添加应用。选择它后可录制快捷键。");
        }
        catch (Exception error) { SetFeedback(error.Message); }
    }
    private void AddRunning()
    {
        if (AppPicker.Running(this) is AppBinding app) Change(candidate => candidate.Apps.Add(app), "已添加应用。");
    }
    private void EditApplication()
    {
        if (Selected() is not AppBinding app) return;
        using var dialog = new BindingDialog(app);
        if (dialog.ShowDialog(this) == DialogResult.OK && dialog.Result is AppBinding result)
            Change(candidate => candidate.Apps[candidate.Apps.FindIndex(item => item.Id == app.Id)] = result, "已更新应用。");
    }
    private void RemoveApplication()
    {
        if (Selected() is not AppBinding app) return;
        if (MessageBox.Show(this, $"从轻唤移除 {app.Name} 及其快捷键？", "移除应用", MessageBoxButtons.OKCancel) == DialogResult.OK)
            Change(candidate => candidate.Apps.RemoveAll(item => item.Id == app.Id), "已移除应用。");
    }
    private void RecordApplication()
    {
        if (Selected() is not AppBinding app) return;
        Record(app.Hotkey, true, shortcut => Change(candidate => candidate.Apps.Single(item => item.Id == app.Id).Hotkey = shortcut, "已更新快捷键。"));
    }
    private void Record(Shortcut? initial, bool allowClear, Action<Shortcut?> apply)
    {
        recording = true; hotkeys.Clear();
        using var dialog = new ShortcutDialog(initial, allowClear);
        DialogResult result;
        try { result = dialog.ShowDialog(this); }
        finally { recording = false; hotkeys.Load(Settings); RefreshRows(); }
        if (result == DialogResult.OK) apply(dialog.Result);
    }

    private void ShowSettings()
    {
        using var dialog = new Form { Text = "设置与帮助", ClientSize = new(630, 480), MinimumSize = new(540, 480), StartPosition = FormStartPosition.CenterParent };
        var panel = new FlowLayoutPanel { Dock = DockStyle.Fill, Padding = new(18), FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true };
        var shortcut = new Button { Text = $"设置窗口快捷键：{Settings.SettingsHotkey}", AutoSize = true };
        shortcut.Click += (_, _) => Record(Settings.SettingsHotkey, false, value =>
        {
            if (value is not null) Change(candidate => candidate.SettingsHotkey = value, "已更新设置快捷键。");
            shortcut.Text = $"设置窗口快捷键：{Settings.SettingsHotkey}";
        });
        panel.Controls.Add(shortcut);
        var login = new CheckBox { Text = "登录 Windows 后在托盘启动", AutoSize = true };
        try { login.Checked = !fixture && Startup.Enabled(); } catch (Exception error) { SetFeedback(error.Message); }
        bool updating = false;
        login.CheckedChanged += (_, _) =>
        {
            if (updating || fixture) return;
            try { Startup.Set(login.Checked); }
            catch (Exception error) { updating = true; login.Checked = !login.Checked; updating = false; MessageBox.Show(dialog, error.Message, "开机启动设置失败"); }
        };
        panel.Controls.Add(login);
        AddButton(panel, "重新注册快捷键", () => { hotkeys.Load(Settings); RefreshRows(); SetFeedback("已重新尝试注册。" + Summary()); });
        AddButton(panel, "导出配置…", Export);
        AddButton(panel, "导入配置…", Import);
        panel.Controls.Add(new Label
        {
            AutoSize = true, MaximumSize = new(550, 0), Margin = new(3, 14, 3, 12),
            Text = $"轻唤 {Program.Version} · Windows 预览版\n\n选择 .exe 或指向 .exe 的快捷方式，录制 Ctrl / Alt 组合。Win、Fn、F12 等系统保留组合不支持。AltGr 键盘请优先使用 Ctrl+Shift 组合。\n\n应用在前台时再次按键会最小化当前窗口；后台应用会尝试恢复到前台。Windows 拒绝激活时，任务栏会闪烁提示。应用的其他窗口、管理员窗口、商店专用入口和虚拟桌面可能需要手动切换。\n\n关闭主窗口后仍在托盘运行。更新时先从托盘退出，再替换解压后的程序；移动目录后请重新设置开机启动。\n\n配置保存在本机 LocalAppData/QuickToggle。保存时保留上一份 .bak；导入前请确认其中的应用路径与启动参数。"
        });
        dialog.Controls.Add(panel); dialog.ShowDialog(this);
    }

    private void Export()
    {
        using var dialog = new SaveFileDialog { Title = "导出 Windows 配置", Filter = "JSON 配置|*.json", FileName = $"quicktoggle-backup-windows-{DateTime.Now:yyyyMMdd}.json" };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        try { ConfigurationStore.AtomicWrite(dialog.FileName, Settings); SetFeedback("配置已导出。"); }
        catch (Exception error) { SetFeedback(error.Message); }
    }
    private void Import()
    {
        using var dialog = new OpenFileDialog { Title = "导入 Windows 配置", Filter = "JSON 配置|*.json" };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        try
        {
            var candidate = ConfigurationStore.Read(dialog.FileName);
            string targets = string.Join("\n", candidate.Apps.Take(5).Select(app => $"{app.Name} — {app.Executable}"));
            if (MessageBox.Show(this, $"用 {candidate.Apps.Count} 个应用替换当前配置？原文件保留为 .bak。\n导入后快捷键会按配置生效，并可能启动所列程序。请只使用自己信任的备份。\n\n{targets}", "确认导入", MessageBoxButtons.OKCancel, MessageBoxIcon.Question) != DialogResult.OK) return;
            Commit(candidate, recover: true); SetFeedback("配置已导入。" + Summary());
        }
        catch (Exception error) { SetFeedback($"导入失败：{error.Message}"); }
        RefreshRows();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            exiting = true; generation++; engine.Dispose(); hotkeys.Dispose(); hotkeyWindow?.Dispose();
            if (tray is not null) { tray.Visible = false; tray.ContextMenuStrip?.Dispose(); tray.Dispose(); }
        }
        base.Dispose(disposing);
    }
}
