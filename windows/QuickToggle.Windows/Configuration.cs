using System.Text.Json;
using System.Text.Json.Serialization;

namespace QuickToggle;

internal sealed record Shortcut(uint Modifiers, uint Key)
{
    public const uint Alt = 1, Control = 2, Shift = 4;
    public string? Validate()
    {
        if ((Modifiers & ~7u) != 0 || (Modifiers & (Alt | Control)) == 0)
            return "请使用 Ctrl 或 Alt 组合；Win、Fn 组合由系统处理。";
        bool supported = Key is >= 0x30 and <= 0x39 or >= 0x41 and <= 0x5A
            or >= 0x60 and <= 0x69 or >= 0x70 and <= 0x7A or 0x20;
        if (!supported) return "支持字母、数字、空格和 F1–F11；F12 为系统保留。";
        if (Key == (uint)Keys.F4 && (Modifiers & Alt) != 0) return "Alt+F4 为系统保留。";
        return null;
    }

    public override string ToString()
    {
        var parts = new List<string>();
        if ((Modifiers & Control) != 0) parts.Add("Ctrl");
        if ((Modifiers & Alt) != 0) parts.Add("Alt");
        if ((Modifiers & Shift) != 0) parts.Add("Shift");
        parts.Add(Key is >= 0x30 and <= 0x39 ? ((char)Key).ToString() : ((Keys)Key).ToString());
        return string.Join(" + ", parts);
    }

    public static Shortcut FromKeyData(Keys keys) => new(
        ((keys & Keys.Control) != 0 ? Control : 0) |
        ((keys & Keys.Alt) != 0 ? Alt : 0) |
        ((keys & Keys.Shift) != 0 ? Shift : 0), (uint)(keys & Keys.KeyCode));
}

internal sealed class AppBinding
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public string Executable { get; set; } = "";
    public string Arguments { get; set; } = "";
    public bool LaunchIfNeeded { get; set; } = true;
    public Shortcut? Hotkey { get; set; }
}

internal sealed class AppSettings
{
    public int SchemaVersion { get; set; } = 1;
    public string Platform { get; set; } = "windows";
    public bool Enabled { get; set; } = true;
    public Shortcut SettingsHotkey { get; set; } = new(Shortcut.Control | Shortcut.Alt, (uint)Keys.D3);
    public List<AppBinding> Apps { get; set; } = [];

    public AppSettings Copy() => JsonSerializer.Deserialize<AppSettings>(JsonSerializer.Serialize(this, ConfigurationStore.Json), ConfigurationStore.Json)!;

    public void Validate()
    {
        if (SchemaVersion != 1 || Platform != "windows") throw new InvalidDataException("仅支持 Windows 版格式 1 的配置。macOS 配置不能直接导入。");
        if (SettingsHotkey is null || SettingsHotkey.Validate() is string)
            throw new InvalidDataException("设置窗口快捷键无效。");
        if (Apps is null || Apps.Count > 256) throw new InvalidDataException("应用数量不能超过 256。");
        var ids = new HashSet<Guid>();
        var paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var shortcuts = new HashSet<Shortcut> { SettingsHotkey };
        foreach (var app in Apps)
        {
            if (app is null || app.Id == Guid.Empty || !ids.Add(app.Id)) throw new InvalidDataException("应用标识重复或无效。");
            if (string.IsNullOrWhiteSpace(app.Name) || app.Name.Length > 128) throw new InvalidDataException("应用名称长度应为 1–128 个字符。");
            if (string.IsNullOrWhiteSpace(app.Executable) || app.Executable.Length > 4096 || !Path.IsPathFullyQualified(app.Executable)
                || !string.Equals(Path.GetExtension(app.Executable), ".exe", StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("请选择完整的 .exe 应用路径。");
            if (!paths.Add(Path.GetFullPath(app.Executable))) throw new InvalidDataException("同一应用只能添加一次。");
            if (app.Arguments is null || app.Arguments.Length > 4096) throw new InvalidDataException("启动参数过长。");
            if (app.Hotkey is not null)
            {
                if (app.Hotkey.Validate() is string reason) throw new InvalidDataException(reason);
                if (!shortcuts.Add(app.Hotkey)) throw new InvalidDataException($"{app.Hotkey} 已用于其他应用或设置窗口。");
            }
        }
    }
}

internal sealed class ConfigurationStore(string path)
{
    public const int MaximumBytes = 1024 * 1024;
    public static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow
    };
    public string FilePath { get; } = path;
    public bool RecoveryRequired { get; private set; }

    public AppSettings Load()
    {
        if (!File.Exists(FilePath)) return new();
        try { return Read(FilePath); }
        catch { RecoveryRequired = true; throw; }
    }

    public static AppSettings Read(string source)
    {
        using var stream = new FileStream(source, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (stream.Length > MaximumBytes) throw new InvalidDataException("配置文件超过 1 MB。");
        var settings = JsonSerializer.Deserialize<AppSettings>(stream, Json) ?? throw new InvalidDataException("配置内容为空。");
        settings.Validate();
        return settings;
    }

    public void Save(AppSettings settings, bool recover = false)
    {
        if (RecoveryRequired && !recover) throw new InvalidDataException("原配置无法读取。请先导入有效备份；原文件会保留为 .bak。");
        settings.Validate();
        AtomicWrite(FilePath, settings);
        RecoveryRequired = false;
    }

    public static void AtomicWrite(string destination, AppSettings settings)
    {
        settings.Validate();
        byte[] bytes = JsonSerializer.SerializeToUtf8Bytes(settings, Json);
        if (bytes.Length > MaximumBytes) throw new InvalidDataException("配置文件超过 1 MB。");
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(destination))!);
        string temporary = destination + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            {
                stream.Write(bytes);
                stream.Flush(true);
            }
            if (File.Exists(destination)) File.Replace(temporary, destination, destination + ".bak");
            else File.Move(temporary, destination);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
