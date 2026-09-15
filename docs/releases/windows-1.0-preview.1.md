# 轻唤 Windows 1.0 预览版

发行阶段：0916v1，2026-09-16。相对 macOS 1.0，新增 Windows 原生托盘实现及两个架构的可运行包。

## 下载

- Intel / AMD 电脑：`QuickToggle-1.0.0-windows-preview.1-win-x64.zip`
- Windows on ARM：`QuickToggle-1.0.0-windows-preview.1-win-arm64.zip`

解压到固定目录后打开 `QuickToggle.exe`。包内包含运行时，无须另外安装 .NET。建议 Windows 11。首版没有 Authenticode 签名；使用随包校验值核对下载，不要关闭系统防护。

## 已实现

- 托盘常驻、重复启动显示已有实例、主窗口关闭后继续工作。
- 添加 .exe、普通快捷方式或运行中的桌面应用，编辑启动参数与启动开关。
- 全局快捷键录制、占用提示、注册失败回退、暂停与重新注册。
- 呼出后台窗口、最小化前台窗口，尝试返回先前窗口；系统拒绝抢占前台时给出任务栏提示。
- 名称和路径搜索、待设置和占用筛选、默认 Ctrl+Alt+3 设置入口。
- 当前用户开机启动、配置原子保存、上一份备份、导入导出及损坏保护。

## 验证与限制

Windows x64 和 ARM64 原生 CI 均执行构建、配置/热键自检、三种尺寸窗口布局、自带运行时 EXE 检查和 ZIP 内容检查。包内 `build-manifest.json` 记录版本、架构、源码提交和 EXE SHA-256；Release 的 SHA256SUMS 用于核对 ZIP。

物理按键、登录与休眠、多屏缩放和实际用户应用仍需在用户机器验收，所以此版标为预览版。Win/Fn/F12 等系统保留组合、商店专用入口、管理员窗口和跨虚拟桌面场景存在限制。Windows 使用独立配置格式，不能直接导入 macOS 备份。

完整说明：[Windows 使用与构建指南](https://github.com/BLACKIELF/QuickToggle/blob/main/windows/README.md)。macOS 稳定版继续使用 [1.0.0](https://github.com/BLACKIELF/QuickToggle/releases/tag/v1.0.0)。
