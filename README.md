# QuickToggle（轻唤）

轻量、原生的 macOS 菜单栏应用切换工具。为常用 App 设置全局快捷键：按一下呼出，再按一次安全恢复。

当前版本：`0.0.3`

## 下载与运行

- Apple Silicon Mac，macOS 13 或更高版本。
- 可从 [Releases](https://github.com/BLACKIELF/QuickToggle/releases/latest) 下载 `QuickToggle-0.0.3-macOS-arm64.zip`。
- 当前版本使用 ad-hoc 签名，未经 Apple 公证，不会自动安装到 `/Applications`。首次运行若被 Gatekeeper 拦截，请在“系统设置 > 隐私与安全性”中确认打开；不放心时请直接从源码构建。

从源码构建需要 Xcode Command Line Tools：

```bash
bash build.sh
open "build/QuickToggle.app"
```

## 特性

- 支持多个应用，每个应用独立录制快捷键，推荐使用未占用的 `⌘0–9`。
- 记住按键前的隐藏、最小化或显示状态，第二次按键尽量安全恢复。
- 新快捷键先注册再替换；发生冲突时旧快捷键继续有效。
- 设置窗口默认使用 `⌘3` 显示或隐藏，也可以直接重新录制。
- 无辅助功能权限时仍可激活、隐藏和重新打开窗口；精确恢复最小化窗口需要用户主动授权。
- 只使用 Swift、AppKit、Carbon 与 ApplicationServices，无第三方依赖、网络请求、遥测或账号系统。

## 使用

首次启动会打开单页设置，之后默认按 `⌘3` 显示或隐藏：

1. 点击“添加应用…”选择目标 `.app`，可重复添加多个应用。
2. 在每个应用右侧分别录制快捷键。
3. Esc 取消；Delete 或 Backspace 清除。
4. 每个应用可独立设置“未运行时自动打开”，也可单独移除。
5. 设置保存后立即生效，并通过 UserDefaults 保存在本机。

菜单栏包含：显示设置、启用/停用全部快捷键、申请辅助功能权限、退出。

## 两次按键行为

- 原本隐藏：第一次呼出；第二次重新隐藏。
- 目标已经在前台：按快捷键会直接安全隐藏，不关闭任何窗口。
- 原本全部窗口最小化：有辅助功能权限时只恢复一个窗口；第二次只重新最小化该窗口。
- 原本已显示：第一次激活；第二次不关闭窗口，只恢复之前的前台应用。
- 两次按键之间若用户切换了应用、目标进程重启或窗口状态改变，本次不做破坏性恢复。
- 没有辅助功能权限时，轻唤仍优先直接激活已有窗口；只有检测不到可用窗口时才使用系统“重新打开应用”语义。

辅助功能权限只在用户点击“开启精确恢复…”或菜单同名项目后请求。

## 快捷键规则

- 优先推荐未占用的 `⌘ + 任意数字（0–9）`。
- 使用字母、方向键或 F1–F12 时，至少两个修饰键，且必须包含 Command 或 Control。
- macOS 保留组合会被阻止；常见高风险组合会显示警告。
- 使用 Carbon 独占注册检测可检测的冲突。候选键先注册，失败时旧键保持有效。
- 每个应用必须使用不同组合；冲突项不会影响其他已注册快捷键。
- macOS 无法暴露所有应用的非独占快捷键，因此不能检测全部冲突。

设置页下方的“macOS 原生快捷键”和“应用内快捷键”都是只读参考，不会注册、导入或覆盖快捷键。

## 验证

```bash
bash selfcheck.sh
```

自检会执行：debug 重建、签名校验、快捷键规则、事务替换、多热键路由、旧配置迁移、状态机分支、菜单栏/设置窗口冒烟，以及五次空闲 CPU/RSS 采样。诊断模式不会读取或写入用户设置。

## 项目结构

- `QuickToggle.swift`：全部应用逻辑与自检入口。
- `build.sh`：无第三方依赖的 App Bundle 构建。
- `selfcheck.sh`：构建、自检、冒烟和资源测量。
- `Assets/QuickToggleIcon-0817v2.icns`：应用图标。

`build/` 是本机构建结果，不提交到仓库。

## 隐私与许可

QuickToggle 不联网、不上传数据、不包含遥测。应用选择、快捷键和主题仅保存在本机。源码采用 [MIT License](LICENSE)。

---

## English

QuickToggle is a lightweight, native macOS menu-bar utility for assigning global shortcuts to apps. Press once to reveal an app; press again to safely restore the previous state.

Current version: `0.0.3`

### Download and run

- Apple Silicon Mac with macOS 13 or later.
- Download `QuickToggle-0.0.3-macOS-arm64.zip` from [Releases](https://github.com/BLACKIELF/QuickToggle/releases/latest).
- The current build is ad-hoc signed and not Apple-notarized. It is not installed into `/Applications` automatically. If Gatekeeper blocks the first launch, explicitly allow it in System Settings > Privacy & Security, or build from source.

Building from source requires Xcode Command Line Tools:

```bash
bash build.sh
open "build/QuickToggle.app"
```

### Features

- Multiple app bindings with one independently recorded shortcut per app; unused `⌘0–9` combinations are recommended.
- Remembers whether the app was hidden, minimized, or visible and restores conservatively on the second press.
- Transactional hot-key replacement: a conflicting candidate never removes the working shortcut.
- The settings window defaults to `⌘3` and can be changed in place.
- Activation, hiding, and window reopening work without Accessibility access; exact minimized-window restoration is opt-in.
- Native Swift, AppKit, Carbon, and ApplicationServices only—no third-party dependencies, network requests, telemetry, login, or sync.

### How it behaves

- Hidden app: reveal it, then hide it again.
- Frontmost app: hide it safely without closing any window.
- Fully minimized app: with Accessibility permission, restore one window and minimize only that window again.
- Visible app: activate it, then return focus to the previous app without closing windows.
- If the user changes state between presses, QuickToggle avoids destructive restoration.
- Without Accessibility permission, existing windows are activated directly; system reopen semantics are used only when no usable window can be detected.

Accessibility permission is requested only after the user clicks the permission button or matching menu item.

### Shortcut rules

- Prefer an unused `⌘ + digit (0–9)`.
- Letters, arrow keys, and F1–F12 require at least two modifiers and must include Command or Control.
- Reserved macOS combinations are blocked; common high-risk combinations show a warning.
- Carbon exclusive registration detects conflicts that macOS exposes. It cannot detect every non-exclusive shortcut used inside other apps.

The macOS and in-app shortcut sections in Settings are read-only guides; QuickToggle never imports or overrides them.

### Verification

Run `bash selfcheck.sh` to rebuild, verify the ad-hoc signature, execute shortcut/transaction/state-machine checks, smoke-test the menu bar and settings window, and sample idle CPU/RSS. Diagnostic modes do not read or modify user preferences.

### Privacy and license

QuickToggle has no networking or telemetry. App selections, shortcuts, and theme preferences remain in local UserDefaults. Source code is available under the [MIT License](LICENSE).
