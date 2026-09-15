# 轻唤 Windows 1.0 预览版

阶段版本：0916v1。相对 macOS 1.0：新增独立的原生 Windows 托盘程序，沿用“按一次呼出，再按一次收起”的使用方式。Windows 的收起动作是最小化当前应用窗口。

## 下载与运行

在 [Windows 预览版 Release](https://github.com/BLACKIELF/QuickToggle/releases/tag/v1.0.0-windows-preview.1) 下载与你的电脑匹配的 ZIP：

- Intel / AMD：`win-x64`。
- Windows on ARM：`win-arm64`。

建议使用 Windows 11。解压到固定目录，打开 `QuickToggle.exe`。发行包自带 .NET 运行时，无须另外安装 .NET。首版尚未使用商业代码签名证书，Windows 可能显示未识别的发行者；可先在 PowerShell 使用 `Get-FileHash` 与 Release 中的 SHA256SUMS 核对。不要关闭系统防护。

## 使用

1. 点击“添加应用”选择 `.exe` 或指向 `.exe` 的 `.lnk`；也可以从运行中的应用添加。
2. 选中应用，点击“快捷键”，按下 Ctrl / Alt 与字母、数字或 F1–F11 的组合。
3. 快捷键使后台窗口尝试恢复到前台；目标在前台时，再按一次会最小化当前窗口，并尝试返回先前窗口。
4. 默认 `Ctrl + Alt + 3` 打开或收起设置主窗口。暂停应用热键时，这个入口仍保留。
5. 主窗口关闭后继续在系统托盘运行；退出需使用托盘菜单的“退出轻唤”。重复打开程序会显示已有实例。

搜索支持名称和路径。“待设置”显示未配置快捷键的应用，“占用 / 失败”显示真实的注册失败原因。重新注册、设置窗口快捷键、开机启动和备份都在“设置与帮助”中。

## 配置与升级

- 配置：`%LOCALAPPDATA%\QuickToggle\settings.json`；每次保存保留上一份 `settings.json.bak`。
- 保存采用同目录临时文件和原子替换。配置损坏时保留原件、阻止自动覆盖，可导入有效的 Windows 备份恢复。
- 导入替换应用配置前会确认；请检查文件中的启动路径与参数。备份仅适用于 Windows，不能直接导入 macOS 配置。
- 开机启动只写入当前用户的 Windows Run 注册表项，由设置复选框控制，不需要管理员权限。Windows 任务管理器仍可禁用此启动项；复选框反映轻唤登记的命令。
- 更新前退出托盘程序，再替换解压目录中的文件。移动程序目录后重新勾选开机启动。
- 卸载：先取消开机启动，再退出并移除解压目录。是否保留上述配置目录由你决定。

## 当前边界

- Windows 会限制抢占前台；激活被拒绝时轻唤显示原因并让任务栏闪烁，不强行绕过系统规则。
- 系统保留的 Win、Fn、F12、Alt+F4 等组合不可用。使用 AltGr 的键盘优先选择 Ctrl+Shift 组合。
- 目前按完整 `.exe` 路径匹配桌面应用，处理一个可见顶层窗口。商店专用入口、多进程启动器、管理员应用、多窗口与跨虚拟桌面场景可能需要手动操作。
- 本版仍是预览版。CI 中的原生热键检查、配置测试和窗口布局检查不能代替实际用户机器上的物理按键、睡眠唤醒、多显示器缩放和登录验收。
- 自带运行时随新发行包更新；没有后台下载器或自动更新服务。

## 从源码构建

在 Windows 安装 .NET 10 SDK 后，从仓库根目录运行：

```powershell
./windows/build.ps1 -Runtime win-x64 -Package
# ARM64 Windows 上运行：
./windows/build.ps1 -Runtime win-arm64 -Package
```

脚本先执行配置与原生热键自检、三种尺寸界面检查，再打包并验证实际自带运行时的 EXE。输出位于 `build/windows/<架构>/`。ZIP 中包含版本、源码提交、架构和 EXE 校验值的 `build-manifest.json`。

技术依据：[RegisterHotKey](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerhotkey)、[SetForegroundWindow](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setforegroundwindow)、[.NET 单文件发布](https://learn.microsoft.com/en-us/dotnet/core/deploying/single-file/overview)。
