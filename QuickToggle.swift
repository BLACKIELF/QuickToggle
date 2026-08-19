import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import UniformTypeIdentifiers

// MARK: - Persisted model

private struct TargetApplication: Codable, Equatable {
    let bundleIdentifier: String
    let name: String
    let path: String
}

private struct AppBinding: Codable, Equatable {
    let id: UUID
    let target: TargetApplication
    var shortcut: Shortcut?
    var launchIfNeeded: Bool
}

private func shortcutIsUsed(_ shortcut: Shortcut, in bindings: [AppBinding], excluding id: UUID) -> Bool {
    bindings.contains { $0.id != id && $0.shortcut == shortcut }
}

private struct Shortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let label: String

    var displayName: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + label
    }

    var validationError: String? {
        let count = [cmdKey, controlKey, optionKey, shiftKey]
            .filter { modifiers & UInt32($0) != 0 }
            .count
        if count <= 1 { return settingsValidationError }
        return validationError(minimumModifierCount: 2)
    }

    var settingsValidationError: String? {
        let count = [cmdKey, controlKey, optionKey, shiftKey]
            .filter { modifiers & UInt32($0) != 0 }
            .count
        if count == 1,
           !(modifiers == UInt32(cmdKey) && Self.numberKeyCodes.contains(keyCode)) {
            return "单修饰键仅支持 Command + 数字；其他组合请至少使用两个修饰键。"
        }
        return validationError(minimumModifierCount: 1)
    }

    private func validationError(minimumModifierCount: Int) -> String? {
        let count = [cmdKey, controlKey, optionKey, shiftKey]
            .filter { modifiers & UInt32($0) != 0 }
            .count
        guard count >= minimumModifierCount else {
            return minimumModifierCount == 1
                ? "快捷键至少需要一个修饰键。"
                : "快捷键至少需要两个修饰键。"
        }
        guard modifiers & UInt32(cmdKey | controlKey) != 0 else {
            return "快捷键必须包含 Command 或 Control。"
        }
        guard Self.supportedKeyCodes.contains(keyCode) else {
            return "请选择字母、数字、方向键或 F1–F12。"
        }
        guard !isReserved else { return "该组合由 macOS 保留，请选择其他快捷键。" }
        return nil
    }

    var riskWarning: String? {
        if modifiers == UInt32(cmdKey), Self.numberKeyCodes.contains(keyCode) {
            return "⌘ + 数字在部分应用中用于切换标签页；已保存，但 macOS 无法检测所有非独占冲突。"
        }
        let commonKeys = Set([kVK_ANSI_X, kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_A,
                              kVK_ANSI_Z, kVK_ANSI_S, kVK_ANSI_W, kVK_ANSI_Q]
            .map(UInt32.init))
        guard modifiers & UInt32(cmdKey) != 0, commonKeys.contains(keyCode) else { return nil }
        return "这个组合常被应用使用，可能覆盖剪切、复制、保存、关闭或退出等操作。"
    }

    private var isReserved: Bool {
        let hasCommand = modifiers & UInt32(cmdKey) != 0
        let hasControl = modifiers & UInt32(controlKey) != 0
        let hasOption = modifiers & UInt32(optionKey) != 0
        let hasShift = modifiers & UInt32(shiftKey) != 0

        if hasControl && hasOption { return true }
        if hasCommand && (keyCode == UInt32(kVK_Tab) || keyCode == UInt32(kVK_Space)) { return true }
        if hasCommand && hasShift && [kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5]
            .map(UInt32.init).contains(keyCode) { return true }
        if hasCommand && hasOption && keyCode == UInt32(kVK_Escape) { return true }
        if hasCommand && hasControl && keyCode == UInt32(kVK_ANSI_Q) { return true }
        if hasCommand && hasShift && keyCode == UInt32(kVK_ANSI_Q) { return true }
        return false
    }

    static func from(event: NSEvent) -> Shortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }

        let keyCode = UInt32(event.keyCode)
        guard supportedKeyCodes.contains(keyCode) else { return nil }
        let label = keyLabels[keyCode] ?? event.charactersIgnoringModifiers?.uppercased()
        guard let label, !label.isEmpty else { return nil }
        return Shortcut(keyCode: keyCode, modifiers: modifiers, label: label)
    }

    private static let supportedKeyCodes = Set([
        kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E,
        kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J,
        kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O,
        kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T,
        kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Y,
        kVK_ANSI_Z, kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3,
        kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8,
        kVK_ANSI_9, kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow,
        kVK_DownArrow, kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5,
        kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12
    ].map(UInt32.init))

    private static let numberKeyCodes = Set([
        kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
        kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9
    ].map(UInt32.init))

    private static let keyLabels: [UInt32: String] = [
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12"
    ]
}

private final class PreferenceStore {
    private enum Key {
        static let bindings = "quickToggle.bindings"
        static let target = "quickToggle.target"
        static let shortcut = "quickToggle.shortcut"
        static let settingsShortcut = "quickToggle.settingsShortcut"
        static let enabled = "quickToggle.enabled"
        static let launchIfNeeded = "quickToggle.launchIfNeeded"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func loadBindings() -> [AppBinding] {
        defer { defaults.removeObject(forKey: Key.shortcut) }
        if let saved = decode([AppBinding].self, forKey: Key.bindings) { return saved }
        guard let target else { return [] }
        let migrated = [AppBinding(
            id: UUID(),
            target: target,
            shortcut: shortcut,
            launchIfNeeded: launchIfNeeded
        )]
        saveBindings(migrated)
        return migrated
    }

    func saveBindings(_ bindings: [AppBinding]) {
        encode(bindings, forKey: Key.bindings)
    }

    var target: TargetApplication? {
        get { decode(TargetApplication.self, forKey: Key.target) }
        set { encode(newValue, forKey: Key.target) }
    }

    var shortcut: Shortcut? {
        get { decode(Shortcut.self, forKey: Key.shortcut) }
        set { encode(newValue, forKey: Key.shortcut) }
    }

    var settingsShortcut: Shortcut? {
        get { decode(Shortcut.self, forKey: Key.settingsShortcut) }
        set { encode(newValue, forKey: Key.settingsShortcut) }
    }

    var enabled: Bool {
        get { defaults.object(forKey: Key.enabled) == nil ? true : defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    var launchIfNeeded: Bool {
        get { defaults.object(forKey: Key.launchIfNeeded) == nil ? true : defaults.bool(forKey: Key.launchIfNeeded) }
        set { defaults.set(newValue, forKey: Key.launchIfNeeded) }
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T?, forKey key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}

// MARK: - Visible app scan and confirmed shortcut help

private struct ScannedApplication: Equatable {
    let bundleIdentifier: String
    let name: String
    let path: String

    var url: URL { URL(fileURLWithPath: path) }
}

private enum ApplicationScanner {
    static func visibleApplications(excluding excludedBundleIDs: Set<String>) -> [ScannedApplication] {
        var seen = excludedBundleIDs
        var results: [ScannedApplication] = []
        for url in candidateAppURLs() {
            guard shouldInclude(url: url),
                  let bundle = Bundle(url: url),
                  let identifier = bundle.bundleIdentifier,
                  !identifier.isEmpty,
                  !seen.contains(identifier) else { continue }
            seen.insert(identifier)
            results.append(
                ScannedApplication(
                    bundleIdentifier: identifier,
                    name: displayName(for: url),
                    path: url.path
                )
            )
        }
        return results.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func shouldInclude(url: URL) -> Bool {
        guard url.pathExtension == "app",
              !isExcludedPath(url.path),
              let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier,
              !identifier.isEmpty else { return false }
        if identifier == Bundle.main.bundleIdentifier { return false }
        if isInvisibleInfo(bundle.infoDictionary ?? [:]) { return false }
        return !displayName(for: url).isEmpty
    }

    static func isExcludedPath(_ path: String) -> Bool {
        let markers = [
            "/Contents/Frameworks/",
            "/Contents/PlugIns/",
            "/XPCServices/",
            "/Helpers/",
            "/Library/LoginItems/"
        ]
        return markers.contains { path.contains($0) }
    }

    static func isInvisibleInfo(_ info: [String: Any]) -> Bool {
        isTruthy(info["LSBackgroundOnly"]) || isTruthy(info["LSUIElement"])
    }

    static func displayName(for url: URL) -> String {
        FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func candidateAppURLs() -> [URL] {
        let fileManager = FileManager.default
        var roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications", isDirectory: true)
        ]
        if let local = fileManager.urls(for: .applicationDirectory, in: .localDomainMask).first {
            roots.append(local)
        }
        var urls: [URL] = []
        var seenPaths = Set<String>()
        for root in roots {
            guard let items = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for item in items {
                if item.pathExtension == "app" {
                    appendApp(item, into: &urls, seen: &seenPaths)
                    continue
                }
                guard let nested = try? fileManager.contentsOfDirectory(
                    at: item,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                for child in nested where child.pathExtension == "app" {
                    appendApp(child, into: &urls, seen: &seenPaths)
                }
            }
        }
        return urls
    }

    private static func appendApp(_ url: URL, into urls: inout [URL], seen: inout Set<String>) {
        let resolved = url.resolvingSymlinksInPath()
        guard seen.insert(resolved.path).inserted else { return }
        urls.append(resolved)
    }

    private static func isTruthy(_ value: Any?) -> Bool {
        switch value {
        case let flag as Bool: return flag
        case let number as NSNumber: return number.boolValue
        case let text as String:
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == "1" || normalized == "true" || normalized == "yes"
        default: return false
        }
    }
}

private enum ConfirmedAppShortcuts {
    static func entries(for bundleIdentifier: String) -> [(String, String)] {
        switch bundleIdentifier {
        case "com.tencent.xinWeChat":
            return [("常见：呼出主窗口", "⇧⌘ W")]
        case "com.openai.codex":
            return [("命令菜单", "⌘ K"), ("新建对话", "⌘ N")]
        case "com.google.Chrome":
            return [("定位地址栏", "⌘ L"), ("重开关闭标签", "⇧⌘ T")]
        default:
            return []
        }
    }
}

private enum BindingHelpContent {
    static func view(for binding: AppBinding) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(section(
            title: "轻唤热键",
            body: binding.shortcut?.displayName ?? "尚未为这个应用录制轻唤热键。"
        ))

        let confirmed = ConfirmedAppShortcuts.entries(for: binding.target.bundleIdentifier)
        if confirmed.isEmpty {
            stack.addArrangedSubview(section(
                title: "已确认的应用快捷键",
                body: "未能确认该应用的原生快捷键。请查看菜单栏命令或应用设置。"
            ))
        } else {
            let rows = NSStackView()
            rows.orientation = .vertical
            rows.alignment = .leading
            rows.spacing = 4
            confirmed.forEach { rows.addArrangedSubview(keyRow(action: $0.0, keys: $0.1)) }
            let block = NSStackView(views: [heading("已确认的应用快捷键"), rows])
            block.orientation = .vertical
            block.alignment = .leading
            block.spacing = 4
            stack.addArrangedSubview(block)
        }

        stack.addArrangedSubview(section(
            title: "如何查看或修改",
            body: "打开该应用后，查看菜单栏命令或应用设置。轻唤不会读取、导入或覆盖应用自己的快捷键。"
        ))

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 10))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            stack.widthAnchor.constraint(equalToConstant: 252)
        ])
        container.frame.size = container.fittingSize
        container.setAccessibilityElement(true)
        container.setAccessibilityRole(.group)
        container.setAccessibilityLabel("\(binding.target.name) 的快捷键说明")
        return container
    }

    private static func section(title: String, body: String) -> NSView {
        let stack = NSStackView(views: [heading(title), paragraph(body)])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        return stack
    }

    private static func heading(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 11, weight: .semibold)
        field.textColor = .secondaryLabelColor
        return field
    }

    private static func paragraph(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: 12)
        field.preferredMaxLayoutWidth = 252
        return field
    }

    private static func keyRow(action: String, keys: String) -> NSView {
        let actionLabel = NSTextField(labelWithString: action)
        actionLabel.font = .systemFont(ofSize: 12)
        actionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let keyLabel = NSTextField(labelWithString: keys)
        keyLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        let row = NSStackView(views: [actionLabel, spacer, keyLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.widthAnchor.constraint(equalToConstant: 252).isActive = true
        row.setAccessibilityLabel("\(action)，\(keys)")
        return row
    }
}

private final class PendingApplicationPickerController: NSViewController, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var onPick: ((URL) -> Void)?
    var onChooseFromDisk: (() -> Void)?

    private var applications: [ScannedApplication] = []
    private var filtered: [ScannedApplication] = []
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 336))
        view = root

        searchField.placeholderString = "搜索已安装的应用"
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.setAccessibilityLabel("搜索待添加应用")
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        column.resizingMask = .autoresizingMask
        tableView.headerView = nil
        tableView.addTableColumn(column)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 30
        tableView.allowsEmptySelection = false
        tableView.allowsMultipleSelection = false
        tableView.target = self
        tableView.doubleAction = #selector(addSelected)
        tableView.setAccessibilityLabel("待添加应用列表")
        tableView.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.stringValue = "没有可添加的可视应用。"
        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: "双击添加，不会自动设置快捷键。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        let diskButton = NSButton(title: "从磁盘选择…", target: self, action: #selector(chooseFromDisk))
        diskButton.bezelStyle = .rounded
        diskButton.setAccessibilityLabel("从磁盘选择应用")
        diskButton.translatesAutoresizingMaskIntoConstraints = false

        let addButton = NSButton(title: "添加", target: self, action: #selector(addSelected))
        addButton.bezelStyle = .rounded
        addButton.keyEquivalent = "\r"
        addButton.setAccessibilityLabel("添加选中的应用")
        addButton.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(searchField)
        root.addSubview(scroll)
        root.addSubview(emptyLabel)
        root.addSubview(countLabel)
        root.addSubview(hint)
        root.addSubview(diskButton)
        root.addSubview(addButton)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            searchField.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -8),
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualTo: scroll.widthAnchor, constant: -24),
            hint.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: searchField.trailingAnchor),
            countLabel.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            countLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            diskButton.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -8),
            diskButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
            addButton.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),
            addButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
            hint.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -8)
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(searchField)
    }

    func reload(excluding excludedBundleIDs: Set<String>) {
        applications = ApplicationScanner.visibleApplications(excluding: excludedBundleIDs)
        applyFilter()
    }

    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = filtered[row]
        let identifier = NSUserInterfaceItemIdentifier("PendingAppCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? makeCell(identifier: identifier)
        let icon = NSWorkspace.shared.icon(forFile: item.path)
        icon.size = NSSize(width: 18, height: 18)
        cell.imageView?.image = icon
        cell.textField?.stringValue = item.name
        cell.setAccessibilityLabel(item.name)
        return cell
    }

    @objc private func addSelected() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard filtered.indices.contains(row) else { return }
        onPick?(filtered[row].url)
    }

    @objc private func chooseFromDisk() {
        onChooseFromDisk?()
    }

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filtered = applications
        } else {
            filtered = applications.filter { $0.name.localizedStandardContains(query) }
        }
        tableView.reloadData()
        if !filtered.isEmpty { tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        emptyLabel.isHidden = !filtered.isEmpty
        if applications.isEmpty {
            emptyLabel.stringValue = "没有可添加的可视应用。"
            countLabel.stringValue = "0 个待添加"
        } else if filtered.isEmpty {
            emptyLabel.stringValue = "没有匹配的应用。"
            countLabel.stringValue = "0 / \(applications.count)"
        } else {
            countLabel.stringValue = "\(filtered.count) 个待添加"
        }
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyUpOrDown
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12.5)
        label.lineBreakMode = .byTruncatingTail
        cell.addSubview(icon)
        cell.addSubview(label)
        cell.imageView = icon
        cell.textField = label
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }
}

// MARK: - Transactional Carbon hot key

private enum HotKeyFailure: Error, Equatable {
    case occupied
    case failed
}

private enum RegistrationTransaction {
    static func replace<Reference>(
        current: Reference?,
        registerCandidate: () -> Result<Reference, HotKeyFailure>,
        unregister: (Reference) -> Result<Void, HotKeyFailure>,
        rollbackCandidate: (Reference) -> Void
    ) -> Result<Reference, HotKeyFailure> {
        switch registerCandidate() {
        case .failure(let error):
            return .failure(error)
        case .success(let candidate):
            if let current {
                switch unregister(current) {
                case .success: break
                case .failure(let error):
                    rollbackCandidate(candidate)
                    return .failure(error)
                }
            }
            return .success(candidate)
        }
    }
}

private func carbonHotKeyCallback(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return noErr }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    return manager.handle(event)
}

private final class HotKeyManager {
    private static var signatureSeed: OSType = 0x51540000
    var onPress: (() -> Void)?
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var activeShortcut: Shortcut?
    private var nextIdentifier: UInt32 = 1
    private let signature: OSType

    init() {
        Self.signatureSeed &+= 1
        signature = Self.signatureSeed
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyCallback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        if status != noErr { handler = nil }
    }

    var isActive: Bool { reference != nil }
    var routingSignature: OSType { signature }

    static func routes(eventSignature: OSType, to managerSignature: OSType) -> Bool {
        eventSignature == managerSignature
    }

    func handle(_ event: EventRef?) -> OSStatus {
        guard let event else { return OSStatus(eventNotHandledErr) }
        var identifier = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &identifier
        )
        guard status == noErr, Self.routes(eventSignature: identifier.signature, to: signature) else {
            return OSStatus(eventNotHandledErr)
        }
        DispatchQueue.main.async { [weak self] in self?.onPress?() }
        return noErr
    }

    func replace(with shortcut: Shortcut) -> Result<Void, HotKeyFailure> {
        guard handler != nil else { return .failure(.failed) }
        if activeShortcut == shortcut, reference != nil { return .success(()) }

        let result: Result<EventHotKeyRef, HotKeyFailure> = RegistrationTransaction.replace(
            current: reference,
            registerCandidate: { [weak self] in
                guard let self else { return .failure(.failed) }
                return self.register(shortcut)
            },
            unregister: { ref in
                UnregisterEventHotKey(ref) == noErr ? .success(()) : .failure(.failed)
            },
            rollbackCandidate: { _ = UnregisterEventHotKey($0) }
        )

        switch result {
        case .failure(let error): return .failure(error)
        case .success(let newReference):
            reference = newReference
            activeShortcut = shortcut
            return .success(())
        }
    }

    func probe(_ shortcut: Shortcut) -> Result<Void, HotKeyFailure> {
        switch register(shortcut) {
        case .failure(let error): return .failure(error)
        case .success(let candidate):
            return UnregisterEventHotKey(candidate) == noErr ? .success(()) : .failure(.failed)
        }
    }

    func disable() -> Result<Void, HotKeyFailure> {
        guard let reference else { return .success(()) }
        guard UnregisterEventHotKey(reference) == noErr else { return .failure(.failed) }
        self.reference = nil
        activeShortcut = nil
        return .success(())
    }

    func rebind(_ shortcut: Shortcut) -> Result<Void, HotKeyFailure> {
        if let reference {
            _ = UnregisterEventHotKey(reference)
            self.reference = nil
        }
        activeShortcut = nil
        return replace(with: shortcut)
    }

    func close() {
        _ = disable()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    private func register(_ shortcut: Shortcut) -> Result<EventHotKeyRef, HotKeyFailure> {
        nextIdentifier &+= 1
        var candidate: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: signature, id: nextIdentifier)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            identifier,
            GetApplicationEventTarget(),
            UInt32(kEventHotKeyExclusive),
            &candidate
        )
        guard status == noErr, let candidate else {
            return .failure(status == eventHotKeyExistsErr ? .occupied : .failed)
        }
        return .success(candidate)
    }
}

// MARK: - Conservative two-press state machine

private enum OriginalStateKind: Equatable {
    case hidden
    case minimized
    case visible
    case degraded
    case launched
}

private enum RestoreDecision: Equatable {
    case hideTarget
    case minimizeExactWindow
    case activatePrevious
    case none
}

private enum RestorePlanner {
    static let freshSessionLimit: TimeInterval = 0.8

    static func decide(
        original: OriginalStateKind,
        sameProcess: Bool,
        targetIsFrontmost: Bool,
        targetIsActive: Bool,
        targetIsHidden: Bool,
        foreignAppIsFrontmost: Bool,
        sessionIsFresh: Bool,
        restoredWindowIsMinimized: Bool?
    ) -> RestoreDecision {
        guard sameProcess else { return .none }
        let stillOurs = targetIsFrontmost || targetIsActive || sessionIsFresh || !foreignAppIsFrontmost
        switch original {
        case .hidden, .degraded, .launched, .visible:
            if targetIsHidden { return .none }
            // Second press must hide when this session still owns the toggle.
            // Requiring frontmost alone drops Electron / menu-bar apps and
            // double-presses that arrive before activate() has settled.
            return stillOurs ? .hideTarget : .none
        case .minimized:
            if restoredWindowIsMinimized != false { return .none }
            return stillOurs ? .minimizeExactWindow : .none
        }
    }

    static func shouldRevealAfter(_ decision: RestoreDecision) -> Bool {
        decision == .none
    }
}

private enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func request() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func windows(for processIdentifier: pid_t) -> [AXUIElement] {
        let application = AXUIElementCreateApplication(processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &value
        ) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    static func isMinimized(_ window: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            kAXMinimizedAttribute as CFString,
            &value
        ) == .success else { return nil }
        return value as? Bool
    }

    static func setMinimized(_ minimized: Bool, window: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(
            window,
            kAXMinimizedAttribute as CFString,
            minimized ? kCFBooleanTrue : kCFBooleanFalse
        ) == .success
    }

    static func raise(_ window: AXUIElement) {
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
}

private enum CapturedState {
    case hidden
    case minimized(AXUIElement)
    case visible
    case degraded
    case launched

    var kind: OriginalStateKind {
        switch self {
        case .hidden: return .hidden
        case .minimized: return .minimized
        case .visible: return .visible
        case .degraded: return .degraded
        case .launched: return .launched
        }
    }
}

private struct ToggleSession {
    let targetProcessIdentifier: pid_t
    let previousProcessIdentifier: pid_t?
    let state: CapturedState
    let createdAt: Date
}

private enum LaunchPolicy {
    static func allowsReveal(isRunning: Bool, launchIfNeeded: Bool) -> Bool {
        isRunning || launchIfNeeded
    }
}

private enum RevealPolicy {
    static func shouldHideImmediately(targetIsFrontmost: Bool, onScreenWindowCount: Int) -> Bool {
        targetIsFrontmost && onScreenWindowCount > 0
    }

    static func shouldReopen(windowCount: Int) -> Bool {
        windowCount == 0
    }
}

private enum WindowPresence {
    static func isUsableWindow(_ info: [String: Any], pid: pid_t) -> Bool {
        let owner: pid_t?
        if let value = info[kCGWindowOwnerPID as String] as? pid_t {
            owner = value
        } else if let number = info[kCGWindowOwnerPID as String] as? NSNumber {
            owner = pid_t(truncating: number)
        } else {
            owner = nil
        }
        guard owner == pid,
              (info[kCGWindowLayer as String] as? Int) == 0,
              let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
        return (bounds["Width"] ?? 0) > 64 && (bounds["Height"] ?? 0) > 64
    }

    static func onScreenCount(for pid: pid_t) -> Int {
        let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
        return list.filter { isUsableWindow($0, pid: pid) }.count
    }
}

private final class ToggleEngine {
    var onStatus: ((String) -> Void)?
    private var session: ToggleSession?
    private var isLaunching = false
    private var launchGeneration = 0

    func cancelSession() {
        session = nil
        isLaunching = false
        launchGeneration += 1
    }

    func toggle(_ target: TargetApplication, launchIfNeeded: Bool) {
        guard !isLaunching else {
            onStatus?("目标应用正在启动，请稍候。")
            return
        }
        if let session {
            self.session = nil
            let decision = restore(target, session: session)
            if !RestorePlanner.shouldRevealAfter(decision) { return }
        }
        reveal(target, launchIfNeeded: launchIfNeeded)
    }

    private func reveal(_ target: TargetApplication, launchIfNeeded: Bool) {
        let workspace = NSWorkspace.shared
        let running = workspace.runningApplications.first {
            $0.bundleIdentifier == target.bundleIdentifier
        }
        guard LaunchPolicy.allowsReveal(isRunning: running != nil, launchIfNeeded: launchIfNeeded) else {
            onStatus?("\(target.name) 尚未运行，自动打开已关闭。")
            return
        }
        guard let running else {
            let resolvedURL = workspace.urlForApplication(withBundleIdentifier: target.bundleIdentifier)
                ?? URL(fileURLWithPath: target.path)
            guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
                onStatus?("找不到目标应用，请重新选择。")
                return
            }
            let previous = previousFrontmostProcessIdentifier(excluding: nil)
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.createsNewApplicationInstance = false
            beginLaunch()
            workspace.openApplication(at: resolvedURL, configuration: configuration) { [weak self] app, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isLaunching = false
                    guard let app, error == nil else {
                        self.onStatus?("目标应用启动失败。")
                        return
                    }
                    self.session = ToggleSession(
                        targetProcessIdentifier: app.processIdentifier,
                        previousProcessIdentifier: previous,
                        state: .launched,
                        createdAt: Date()
                    )
                    _ = app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
                    self.onStatus?("已启动并呼出 \(target.name)。")
                }
            }
            return
        }

        let current = refreshed(running)
        let previous = previousFrontmostProcessIdentifier(excluding: current.processIdentifier)
        let onScreenWindows = WindowPresence.onScreenCount(for: current.processIdentifier)
        if current.isHidden {
            _ = current.unhide()
            guard current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows]) else {
                onStatus?("无法激活目标应用。")
                return
            }
            if RevealPolicy.shouldReopen(windowCount: WindowPresence.onScreenCount(for: current.processIdentifier)) {
                reopenRunningApplication(current, previous: previous, target: target)
                return
            }
            session = ToggleSession(
                targetProcessIdentifier: current.processIdentifier,
                previousProcessIdentifier: previous,
                state: .hidden,
                createdAt: Date()
            )
            onStatus?("已呼出 \(target.name)；再次按键会恢复隐藏状态。")
            return
        }

        if RevealPolicy.shouldHideImmediately(
            targetIsFrontmost: appearsFront(current),
            onScreenWindowCount: onScreenWindows
        ) {
            guard current.hide() else {
                onStatus?("无法隐藏目标应用。")
                return
            }
            activatePrevious(previous)
            onStatus?("\(target.name) 已在前台，现已安全隐藏；没有关闭窗口。")
            return
        }

        if Accessibility.isTrusted {
            let windows = Accessibility.windows(for: current.processIdentifier)
            if RevealPolicy.shouldReopen(windowCount: windows.count) {
                reopenRunningApplication(current, previous: previous, target: target)
                return
            }
            let minimizedWindows = windows.filter { Accessibility.isMinimized($0) == true }
            let visibleWindowExists = windows.contains { Accessibility.isMinimized($0) == false }
            if !visibleWindowExists, let restoredWindow = minimizedWindows.first {
                guard Accessibility.setMinimized(false, window: restoredWindow) else {
                    reopenRunningApplication(current, previous: previous, target: target)
                    return
                }
                Accessibility.raise(restoredWindow)
                _ = current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
                if RevealPolicy.shouldReopen(windowCount: WindowPresence.onScreenCount(for: current.processIdentifier)) {
                    reopenRunningApplication(current, previous: previous, target: target)
                    return
                }
                session = ToggleSession(
                    targetProcessIdentifier: current.processIdentifier,
                    previousProcessIdentifier: previous,
                    state: .minimized(restoredWindow),
                    createdAt: Date()
                )
                onStatus?("已恢复一个最小化窗口；再次按键只会重新最小化这个窗口。")
                return
            }
        }

        if RevealPolicy.shouldReopen(windowCount: onScreenWindows) {
            reopenRunningApplication(current, previous: previous, target: target)
            return
        }
        guard current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows]) else {
            onStatus?("无法激活目标应用。")
            return
        }
        if RevealPolicy.shouldReopen(windowCount: WindowPresence.onScreenCount(for: current.processIdentifier)) {
            reopenRunningApplication(current, previous: previous, target: target)
            return
        }
        session = ToggleSession(
            targetProcessIdentifier: current.processIdentifier,
            previousProcessIdentifier: previous,
            state: .visible,
            createdAt: Date()
        )
        onStatus?("已呼出 \(target.name)；再次按键会安全隐藏。")
    }

    private func reopenRunningApplication(
        _ running: NSRunningApplication,
        previous: pid_t?,
        target: TargetApplication
    ) {
        let workspace = NSWorkspace.shared
        let resolvedURL = workspace.urlForApplication(withBundleIdentifier: target.bundleIdentifier)
            ?? URL(fileURLWithPath: target.path)
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            onStatus?("找不到目标应用，请重新选择。")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        beginLaunch()
        workspace.openApplication(at: resolvedURL, configuration: configuration) { [weak self] app, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLaunching = false
                let reopened = app ?? running
                guard error == nil,
                      reopened.activate(options: [.activateIgnoringOtherApps, .activateAllWindows]) else {
                    self.onStatus?("无法重新打开目标应用窗口。")
                    return
                }
                self.session = ToggleSession(
                    targetProcessIdentifier: reopened.processIdentifier,
                    previousProcessIdentifier: previous,
                    state: .degraded,
                    createdAt: Date()
                )
                self.onStatus?("已重新打开并呼出 \(target.name)；再次按键将安全隐藏。")
            }
        }
    }

    private func restore(_ target: TargetApplication, session: ToggleSession) -> RestoreDecision {
        let workspace = NSWorkspace.shared
        guard let running = workspace.runningApplications.first(where: {
            $0.bundleIdentifier == target.bundleIdentifier
        }) else {
            return .none
        }

        let current = refreshed(running)
        let sameProcess = current.processIdentifier == session.targetProcessIdentifier
        let windowMinimized: Bool?
        if case .minimized(let window) = session.state {
            windowMinimized = Accessibility.isMinimized(window)
        } else {
            windowMinimized = nil
        }

        let decision = RestorePlanner.decide(
            original: session.state.kind,
            sameProcess: sameProcess,
            targetIsFrontmost: workspace.frontmostApplication?.processIdentifier == current.processIdentifier,
            targetIsActive: current.isActive,
            targetIsHidden: current.isHidden,
            foreignAppIsFrontmost: foreignRegularAppIsFrontmost(excluding: current.processIdentifier),
            sessionIsFresh: Date().timeIntervalSince(session.createdAt) < RestorePlanner.freshSessionLimit,
            restoredWindowIsMinimized: windowMinimized
        )

        switch decision {
        case .hideTarget:
            guard current.hide() else {
                onStatus?("系统暂时无法隐藏目标应用；没有关闭任何窗口。")
                return decision
            }
            activatePrevious(session.previousProcessIdentifier)
            onStatus?("已恢复按键前状态；没有关闭任何窗口。")
        case .minimizeExactWindow:
            guard case .minimized(let window) = session.state,
                  Accessibility.isTrusted,
                  Accessibility.setMinimized(true, window: window) else {
                onStatus?("窗口状态已变化，本次未自动最小化。")
                return decision
            }
            activatePrevious(session.previousProcessIdentifier)
            onStatus?("已只重新最小化本次恢复的窗口。")
        case .activatePrevious:
            activatePrevious(session.previousProcessIdentifier)
            onStatus?("目标窗口保持显示，已恢复之前的前台应用。")
        case .none:
            return .none
        }
        return decision
    }

    private func previousFrontmostProcessIdentifier(excluding targetPID: pid_t?) -> pid_t? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              frontmost.processIdentifier != targetPID else { return nil }
        return frontmost.processIdentifier
    }

    private func runningApplication(_ processIdentifier: pid_t) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.processIdentifier == processIdentifier }
    }

    private func activatePrevious(_ processIdentifier: pid_t?) {
        guard let processIdentifier, let previous = runningApplication(processIdentifier) else { return }
        _ = previous.activate(options: .activateIgnoringOtherApps)
    }

    private func refreshed(_ running: NSRunningApplication) -> NSRunningApplication {
        NSRunningApplication(processIdentifier: running.processIdentifier) ?? running
    }

    private func appearsFront(_ running: NSRunningApplication) -> Bool {
        running.isActive
            || NSWorkspace.shared.frontmostApplication?.processIdentifier == running.processIdentifier
    }

    private func foreignRegularAppIsFrontmost(excluding targetPID: pid_t) -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return false }
        let pid = frontmost.processIdentifier
        if pid == targetPID { return false }
        if pid == ProcessInfo.processInfo.processIdentifier { return false }
        if frontmost.isHidden { return false }
        if frontmost.activationPolicy != .regular { return false }
        return true
    }

    private func beginLaunch() {
        isLaunching = true
        launchGeneration += 1
        let generation = launchGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.isLaunching, self.launchGeneration == generation else { return }
            self.isLaunching = false
            self.onStatus?("目标应用启动超时，可再试一次。")
        }
    }
}

// MARK: - Application model

private final class QuickToggleModel {
    var onChange: (() -> Void)?
    var onSettingsHotKey: (() -> Void)?
    private(set) var bindings: [AppBinding]
    private(set) var isEnabled: Bool
    private(set) var settingsShortcut: Shortcut
    private(set) var statusMessage = "请添加应用并录制快捷键。"

    private let preferences: PreferenceStore?
    private var hotKeys: [UUID: HotKeyManager] = [:]
    private var engines: [UUID: ToggleEngine] = [:]
    private let settingsHotKey = HotKeyManager()
    private static let defaultSettingsShortcut = Shortcut(
        keyCode: UInt32(kVK_ANSI_3),
        modifiers: UInt32(cmdKey),
        label: "3"
    )

    init(diagnosticMode: Bool) {
        if diagnosticMode {
            preferences = nil
            bindings = []
            isEnabled = false
            settingsShortcut = Self.defaultSettingsShortcut
            statusMessage = "诊断模式：未读取或写入用户设置。"
        } else {
            let store = PreferenceStore()
            preferences = store
            bindings = store.loadBindings()
            isEnabled = store.enabled
            settingsShortcut = store.settingsShortcut ?? Self.defaultSettingsShortcut
        }

        settingsHotKey.onPress = { [weak self] in self?.onSettingsHotKey?() }

        if isEnabled {
            let result = registerAll()
            if result.failed > 0 {
                statusMessage = "已启用 \(result.active) 个快捷键；\(result.failed) 个发生冲突。"
            } else if result.active > 0 {
                statusMessage = "已启用 \(result.active) 个应用快捷键。"
            }
        }

        if !diagnosticMode {
            switch settingsHotKey.replace(with: settingsShortcut) {
            case .success: break
            case .failure(.occupied): statusMessage = "设置快捷键 \(settingsShortcut.displayName) 已被其他应用占用。"
            case .failure(.failed): statusMessage = "系统无法注册设置快捷键 \(settingsShortcut.displayName)。"
            }
        }
    }

    var registeredShortcutCount: Int { hotKeys.values.filter(\.isActive).count }
    var accessibilityStatus: String {
        Accessibility.isTrusted
            ? "已授权：可以精确恢复最小化窗口。"
            : "未授权：仍可激活/隐藏；最小化窗口会降级为隐藏恢复。"
    }

    func addTarget(url: URL) -> Bool {
        guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else {
            statusMessage = "所选项目不是有效的 macOS 应用。"
            onChange?()
            return false
        }
        guard identifier != Bundle.main.bundleIdentifier else {
            statusMessage = "不能把轻唤本身设为目标应用。"
            onChange?()
            return false
        }
        guard !bindings.contains(where: { $0.target.bundleIdentifier == identifier }) else {
            statusMessage = "这个应用已经在列表里。"
            onChange?()
            return false
        }
        let displayName = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        bindings.append(AppBinding(
            id: UUID(),
            target: TargetApplication(
                bundleIdentifier: identifier,
                name: displayName,
                path: url.path
            ),
            shortcut: nil,
            launchIfNeeded: true
        ))
        saveBindings()
        statusMessage = "已添加 \(displayName)，请为它录制快捷键。"
        onChange?()
        return true
    }

    func applyShortcut(_ candidate: Shortcut, for bindingID: UUID) -> Bool {
        guard let index = bindings.firstIndex(where: { $0.id == bindingID }) else { return false }
        if let error = candidate.validationError {
            statusMessage = error
            onChange?()
            return false
        }
        if shortcutIsUsed(candidate, in: bindings, excluding: bindingID) {
            statusMessage = "该组合已用于其他应用，原快捷键仍然有效。"
            onChange?()
            return false
        }

        let manager = hotKeyManager(for: bindingID)
        let result = isEnabled ? manager.replace(with: candidate) : manager.probe(candidate)
        switch result {
        case .failure(.occupied):
            statusMessage = "该组合已被其他应用或轻唤中的其他目标占用，原快捷键仍然有效。"
            onChange?()
            return false
        case .failure(.failed):
            statusMessage = "系统无法注册该组合，原快捷键仍然有效。"
            onChange?()
            return false
        case .success:
            bindings[index].shortcut = candidate
            saveBindings()
            statusMessage = candidate.riskWarning
                ?? (isEnabled ? "\(bindings[index].target.name) 的快捷键已立即生效。" : "快捷键已保存，当前全部停用。")
            onChange?()
            return true
        }
    }

    func applySettingsShortcut(_ candidate: Shortcut) -> Bool {
        if let error = candidate.settingsValidationError {
            statusMessage = error
            onChange?()
            return false
        }
        if bindings.contains(where: { $0.shortcut == candidate }) {
            statusMessage = "该组合已用于应用快捷键，原设置快捷键仍然有效。"
            onChange?()
            return false
        }

        switch settingsHotKey.replace(with: candidate) {
        case .failure(.occupied):
            statusMessage = "该组合已被其他应用占用，原设置快捷键仍然有效。"
            onChange?()
            return false
        case .failure(.failed):
            statusMessage = "系统无法注册该组合，原设置快捷键仍然有效。"
            onChange?()
            return false
        case .success:
            settingsShortcut = candidate
            preferences?.settingsShortcut = candidate
            statusMessage = candidate.riskWarning
                ?? "设置窗口快捷键已改为 \(candidate.displayName)，保存并立即生效。"
            onChange?()
            return true
        }
    }

    func clearShortcut(for bindingID: UUID) -> Bool {
        guard let index = bindings.firstIndex(where: { $0.id == bindingID }) else { return false }
        if let manager = hotKeys[bindingID], manager.isActive, case .failure = manager.disable() {
            statusMessage = "系统无法停用当前快捷键，原快捷键仍然有效。"
            onChange?()
            return false
        }
        bindings[index].shortcut = nil
        saveBindings()
        statusMessage = "已清除 \(bindings[index].target.name) 的快捷键。"
        onChange?()
        return true
    }

    func toggleLaunchIfNeeded(for bindingID: UUID) {
        guard let index = bindings.firstIndex(where: { $0.id == bindingID }) else { return }
        bindings[index].launchIfNeeded.toggle()
        saveBindings()
        statusMessage = bindings[index].launchIfNeeded
            ? "\(bindings[index].target.name) 未运行时将自动打开。"
            : "已关闭自动打开；\(bindings[index].target.name) 未运行时不会启动。"
        onChange?()
    }

    func removeBinding(_ bindingID: UUID) {
        guard let index = bindings.firstIndex(where: { $0.id == bindingID }) else { return }
        let name = bindings[index].target.name
        hotKeys.removeValue(forKey: bindingID)?.close()
        engines.removeValue(forKey: bindingID)?.cancelSession()
        bindings.remove(at: index)
        saveBindings()
        statusMessage = "已移除 \(name)。"
        onChange?()
    }

    func toggleEnabled() {
        if isEnabled {
            for manager in hotKeys.values where manager.isActive {
                guard case .success = manager.disable() else {
                    _ = registerAll()
                    statusMessage = "系统无法完整停用快捷键，已恢复原状态。"
                    onChange?()
                    return
                }
            }
            isEnabled = false
            preferences?.enabled = false
            engines.values.forEach { $0.cancelSession() }
            statusMessage = "所有应用快捷键已停用；\(settingsShortcut.displayName) 仍可显示或隐藏设置。"
            onChange?()
            return
        }

        isEnabled = true
        preferences?.enabled = true
        let result = registerAll()
        if result.failed > 0 {
            statusMessage = "已启用 \(result.active) 个快捷键；\(result.failed) 个冲突项保持停用。"
        } else if result.active > 0 {
            statusMessage = "已启用 \(result.active) 个应用快捷键。"
        } else {
            statusMessage = "尚未录制应用快捷键。"
        }
        onChange?()
    }

    func requestAccessibility() {
        Accessibility.request()
        statusMessage = "已请求辅助功能权限；授权后返回轻唤即可刷新状态。"
        onChange?()
    }

    func close() {
        hotKeys.values.forEach { $0.close() }
        settingsHotKey.close()
    }

    func recoverHotKeys() {
        guard preferences != nil else { return }
        var failed = 0
        if case .failure = settingsHotKey.rebind(settingsShortcut) { failed += 1 }
        if isEnabled {
            failed += rebindAll().failed
        }
        if failed > 0 {
            statusMessage = "快捷键注册已失效，已尝试恢复；仍有 \(failed) 个未成功。"
            onChange?()
        }
    }

    private func saveBindings() {
        preferences?.saveBindings(bindings)
    }

    private func hotKeyManager(for bindingID: UUID) -> HotKeyManager {
        if let manager = hotKeys[bindingID] { return manager }
        let manager = HotKeyManager()
        manager.onPress = { [weak self] in self?.handleHotKey(bindingID) }
        hotKeys[bindingID] = manager
        return manager
    }

    private func toggleEngine(for bindingID: UUID) -> ToggleEngine {
        if let engine = engines[bindingID] { return engine }
        let engine = ToggleEngine()
        engine.onStatus = { [weak self] message in
            self?.statusMessage = message
            self?.onChange?()
        }
        engines[bindingID] = engine
        return engine
    }

    private func registerAll() -> (active: Int, failed: Int) {
        var active = 0
        var failed = 0
        for binding in bindings {
            guard let shortcut = binding.shortcut else { continue }
            switch hotKeyManager(for: binding.id).replace(with: shortcut) {
            case .success: active += 1
            case .failure: failed += 1
            }
        }
        return (active, failed)
    }

    private func rebindAll() -> (active: Int, failed: Int) {
        var active = 0
        var failed = 0
        for binding in bindings {
            guard let shortcut = binding.shortcut else { continue }
            switch hotKeyManager(for: binding.id).rebind(shortcut) {
            case .success: active += 1
            case .failure: failed += 1
            }
        }
        return (active, failed)
    }

    private func handleHotKey(_ bindingID: UUID) {
        guard let binding = bindings.first(where: { $0.id == bindingID }) else { return }
        toggleEngine(for: bindingID).toggle(
            binding.target,
            launchIfNeeded: binding.launchIfNeeded
        )
    }
}

// MARK: - Shortcut recorder

private final class ShortcutRecorderButton: NSButton {
    var shortcut: Shortcut? { didSet { updateTitle() } }
    var onRecord: ((Shortcut) -> Bool)?
    var onClear: (() -> Bool)?
    var onInvalid: ((String) -> Void)?

    private var isRecording = false
    private var monitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = "未设置"
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        controlSize = .large
        font = .monospacedSystemFont(ofSize: 14, weight: .semibold)
        bezelColor = .systemOrange
        contentTintColor = .white
        target = self
        action = #selector(beginRecording)
        focusRingType = .default
        setAccessibilityLabel("全局快捷键录制")
        setAccessibilityHelp("按下按钮后输入组合键；Esc 取消，Delete 或 Backspace 清除。")
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    deinit { removeMonitor() }

    static func shouldCapture(isRecording: Bool, windowIsKey: Bool) -> Bool {
        isRecording && windowIsKey
    }

    @objc private func beginRecording() {
        guard let window, window.makeFirstResponder(self) else { return }
        isRecording = true
        title = "请按组合键…"
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, Self.shouldCapture(
                isRecording: self.isRecording,
                windowIsKey: self.window?.isKeyWindow == true
            ) else { return event }
            self.handle(event)
            return nil
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        handle(event)
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { finish() }
        return result
    }

    private func handle(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        if event.keyCode == UInt16(kVK_Escape) {
            finish()
            return
        }
        if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
            if onClear?() == true { shortcut = nil }
            finish()
            return
        }
        guard let candidate = Shortcut.from(event: event) else {
            onInvalid?("请选择字母、数字、方向键或 F1–F12。")
            NSSound.beep()
            return
        }
        guard onRecord?(candidate) == true else {
            NSSound.beep()
            finish()
            return
        }
        shortcut = candidate
        finish()
    }

    private func finish() {
        isRecording = false
        removeMonitor()
        updateTitle()
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func updateTitle() {
        title = isRecording ? "请按组合键…" : shortcut?.displayName ?? "未设置"
        setAccessibilityValue(title)
    }
}

// MARK: - Native single-page settings

private final class GlassCardView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        updateColors()
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let fill: NSColor
        if reduced {
            fill = dark ? NSColor(calibratedWhite: 0.14, alpha: 1) : NSColor(calibratedWhite: 0.96, alpha: 1)
        } else {
            fill = dark ? NSColor(calibratedWhite: 0.17, alpha: 0.62) : NSColor.white.withAlphaComponent(0.55)
        }
        layer?.backgroundColor = fill.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = (dark
            ? NSColor.white.withAlphaComponent(0.13)
            : NSColor.black.withAlphaComponent(0.10)).cgColor
    }
}

private enum ColorTheme: String {
    case aurora
    case ember

    var primary: NSColor { self == .aurora ? .systemBlue : .systemOrange }
    var recorder: NSColor { self == .aurora ? .systemPurple : .systemOrange }
}

private final class AccentRailView: NSView {
    var theme = ColorTheme.aurora { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.separatorColor.withAlphaComponent(0.30).setFill()
        path.fill()
        if theme == .aurora {
            NSGradient(colors: [.systemPurple, .systemBlue])?.draw(in: path, angle: 0)
        } else {
            NSColor.systemOrange.setFill()
            path.fill()
        }
    }
}

private final class StatusDotView: NSView {
    var color = NSColor.systemOrange { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        color.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
    }
}

private final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

private final class SettingsController: NSObject {
    let window: NSWindow
    private let model: QuickToggleModel
    private let bindingsStack = FlippedStackView()
    private let listScroll = NSScrollView()
    private let countLabel = NSTextField(labelWithString: "")
    private let permissionStatus = NSTextField(wrappingLabelWithString: "")
    private let generalStatus = NSTextField(wrappingLabelWithString: "")
    private let addButton = NSButton()
    private let enableButton = NSButton()
    private let permissionButton = NSButton()
    private let permissionIcon = NSImageView()
    private let settingsShortcutRecorder = ShortcutRecorderButton(frame: .zero)
    private let themeControl = NSSegmentedControl()
    private let guideButton = NSButton()
    private let guideCard = GlassCardView(frame: .zero)
    private let appGuideButton = NSButton()
    private let appGuideCard = GlassCardView(frame: .zero)
    private let statusDot = StatusDotView(frame: .zero)
    private let accentRail = AccentRailView(frame: .zero)
    private var guideAccentIcons: [NSImageView] = []
    private var lastRenderedBindings: [AppBinding]?
    private var guideExpanded = false
    private var appGuideExpanded = false
    private var colorTheme = ColorTheme.aurora
    private let helpPopover = NSPopover()
    private let addPopover = NSPopover()
    private let pendingPicker = PendingApplicationPickerController()

    init(model: QuickToggleModel) {
        self.model = model
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let height = min(640, max(500, visible.height - 48))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: height),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        colorTheme = ColorTheme(
            rawValue: UserDefaults.standard.string(forKey: "quickToggle.colorTheme") ?? ""
        ) ?? .aurora
        window.title = "轻唤 · QuickToggle"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 600, height: 500)
        window.maxSize = NSSize(width: 720, height: max(visible.height - 24, 560))
        window.isReleasedWhenClosed = false
        applyAccessibilityChrome()
        window.center()
        buildInterface()
        refresh()
    }

    func show() {
        applyAccessibilityChrome()
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.recalculateKeyViewLoop()
    }

    func refresh() {
        if lastRenderedBindings != model.bindings {
            lastRenderedBindings = model.bindings
            rebuildBindingRows()
        }

        countLabel.stringValue = "\(model.bindings.count) 个应用"
        permissionStatus.stringValue = model.accessibilityStatus
        generalStatus.stringValue = model.statusMessage
        settingsShortcutRecorder.shortcut = model.settingsShortcut
        enableButton.title = model.isEnabled ? "全部已启用" : "启用全部"
        enableButton.bezelColor = model.isEnabled ? colorTheme.primary : nil
        enableButton.contentTintColor = model.isEnabled ? .white : nil
        statusDot.color = model.registeredShortcutCount > 0 ? .systemGreen : .systemOrange
        accentRail.alphaValue = model.isEnabled ? 1 : 0.38
        permissionButton.title = Accessibility.isTrusted ? "已授权" : "开启精确恢复…"
        permissionButton.isEnabled = !Accessibility.isTrusted
    }

    private func buildInterface() {
        let material = NSVisualEffectView(frame: window.contentView?.bounds ?? .zero)
        material.autoresizingMask = [.width, .height]
        material.material = .underWindowBackground
        material.blendingMode = .behindWindow
        material.state = .active
        window.contentView = material

        let title = NSTextField(labelWithString: "轻唤")
        title.font = .systemFont(ofSize: 27, weight: .bold)
        let productIdentity = NSTextField(labelWithString: "QuickToggle")
        productIdentity.textColor = .secondaryLabelColor
        productIdentity.font = .systemFont(ofSize: 11.5, weight: .medium)
        settingsShortcutRecorder.shortcut = model.settingsShortcut
        settingsShortcutRecorder.controlSize = .small
        settingsShortcutRecorder.font = .monospacedSystemFont(ofSize: 11.5, weight: .semibold)
        settingsShortcutRecorder.bezelColor = colorTheme.recorder
        settingsShortcutRecorder.onRecord = { [weak self] shortcut in
            self?.model.applySettingsShortcut(shortcut) == true
        }
        settingsShortcutRecorder.onClear = { [weak self] in
            self?.generalStatus.stringValue = "设置窗口快捷键不能清除，请直接录制新组合。"
            self?.generalStatus.textColor = .systemOrange
            return false
        }
        settingsShortcutRecorder.onInvalid = { [weak self] message in
            self?.generalStatus.stringValue = message
            self?.generalStatus.textColor = .systemRed
        }
        settingsShortcutRecorder.widthAnchor.constraint(equalToConstant: 72).isActive = true
        settingsShortcutRecorder.heightAnchor.constraint(equalToConstant: 26).isActive = true
        settingsShortcutRecorder.setAccessibilityLabel("轻唤设置窗口快捷键")
        settingsShortcutRecorder.setAccessibilityHelp("点击后录制新的显示或隐藏设置窗口快捷键；推荐 Command 加任意数字，Esc 取消。")
        settingsShortcutRecorder.toolTip = "点击更换；推荐 ⌘0–9，也可用 ⌘⌥K / ⌘⇧K"
        let titleRow = horizontalStack([title, productIdentity, settingsShortcutRecorder], spacing: 9)
        titleRow.alignment = .lastBaseline
        let subtitle = NSTextField(labelWithString: "每个应用一组快捷键。按一下呼出，再按一次安全恢复。")
        subtitle.textColor = .secondaryLabelColor
        subtitle.font = .systemFont(ofSize: 12.5)
        let titleStack = verticalStack([titleRow, subtitle], spacing: 3)
        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        enableButton.target = self
        enableButton.action = #selector(toggleEnabled)
        enableButton.bezelStyle = .rounded
        enableButton.controlSize = .large
        enableButton.font = .systemFont(ofSize: 13, weight: .semibold)
        enableButton.setAccessibilityLabel("启用或停用全部应用快捷键")
        enableButton.widthAnchor.constraint(equalToConstant: 112).isActive = true
        enableButton.heightAnchor.constraint(equalToConstant: 34).isActive = true

        themeControl.segmentCount = 2
        themeControl.setLabel("极光", forSegment: 0)
        themeControl.setLabel("火焰", forSegment: 1)
        themeControl.selectedSegment = colorTheme == .aurora ? 0 : 1
        themeControl.target = self
        themeControl.action = #selector(selectTheme)
        themeControl.controlSize = .small
        themeControl.widthAnchor.constraint(equalToConstant: 112).isActive = true
        themeControl.heightAnchor.constraint(equalToConstant: 28).isActive = true
        themeControl.setAccessibilityLabel("配色主题")

        let header = horizontalStack([titleStack, headerSpacer, themeControl, enableButton], spacing: 12)
        header.alignment = .centerY

        let applicationsCard = GlassCardView(frame: .zero)
        applicationsCard.setAccessibilityLabel("应用快捷键列表")
        applicationsCard.setContentHuggingPriority(.defaultLow, for: .vertical)
        applicationsCard.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let listTitle = NSTextField(labelWithString: "应用快捷键")
        listTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabelColor
        let listHeaderSpacer = NSView()
        listHeaderSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        addButton.title = "添加应用…"
        addButton.target = self
        addButton.action = #selector(chooseApplication)
        addButton.bezelStyle = .rounded
        addButton.controlSize = .large
        addButton.font = .systemFont(ofSize: 13, weight: .semibold)
        addButton.bezelColor = colorTheme.primary
        addButton.contentTintColor = .white
        addButton.widthAnchor.constraint(equalToConstant: 112).isActive = true
        addButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
        addButton.setAccessibilityLabel("添加目标应用")
        addButton.setAccessibilityHelp("打开已安装可视应用列表；也可从磁盘选择。添加后不会自动设置快捷键。")
        let listHeader = horizontalStack([listTitle, countLabel, listHeaderSpacer, addButton], spacing: 8)
        listHeader.alignment = .centerY

        accentRail.heightAnchor.constraint(equalToConstant: 5).isActive = true

        bindingsStack.orientation = .vertical
        bindingsStack.alignment = .leading
        bindingsStack.distribution = .fill
        bindingsStack.spacing = 6
        bindingsStack.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        listScroll.documentView = bindingsStack
        listScroll.hasVerticalScroller = true
        listScroll.autohidesScrollers = true
        listScroll.borderType = .noBorder
        listScroll.drawsBackground = false
        listScroll.setContentHuggingPriority(.init(1), for: .vertical)
        listScroll.setContentCompressionResistancePriority(.init(1), for: .vertical)
        listScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 168).isActive = true

        statusDot.widthAnchor.constraint(equalToConstant: 10).isActive = true
        statusDot.heightAnchor.constraint(equalToConstant: 10).isActive = true
        generalStatus.textColor = .secondaryLabelColor
        generalStatus.font = .systemFont(ofSize: 12.2, weight: .medium)
        generalStatus.lineBreakMode = .byTruncatingTail
        generalStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        generalStatus.setAccessibilityLabel("当前状态")
        let statusRow = horizontalStack([statusDot, generalStatus], spacing: 8)
        statusRow.alignment = .centerY

        let applicationsStack = verticalStack([listHeader, accentRail, listScroll, statusRow], spacing: 8)
        pin(applicationsStack, inside: applicationsCard, insets: NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14))
        [listHeader, accentRail, listScroll, statusRow].forEach {
            $0.widthAnchor.constraint(equalTo: applicationsStack.widthAnchor).isActive = true
        }

        permissionIcon.image = NSImage(
            systemSymbolName: "lock.shield",
            accessibilityDescription: "窗口恢复能力"
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .medium))
        permissionIcon.contentTintColor = colorTheme.primary
        permissionIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        permissionIcon.heightAnchor.constraint(equalToConstant: 18).isActive = true

        permissionStatus.font = .systemFont(ofSize: 11.5)
        permissionStatus.textColor = .secondaryLabelColor
        permissionStatus.lineBreakMode = .byTruncatingTail
        permissionStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let permissionSpacer = NSView()
        permissionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        permissionButton.title = "开启精确恢复…"
        permissionButton.target = self
        permissionButton.action = #selector(requestAccessibility)
        permissionButton.bezelStyle = .rounded
        permissionButton.controlSize = .small
        permissionButton.widthAnchor.constraint(equalToConstant: 118).isActive = true
        permissionButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
        permissionButton.setAccessibilityHelp("只在点击后请求系统辅助功能权限。")
        let permissionRow = horizontalStack(
            [permissionIcon, permissionStatus, permissionSpacer, permissionButton],
            spacing: 8
        )
        permissionRow.alignment = .centerY
        permissionRow.setAccessibilityLabel("辅助功能权限")
        permissionRow.setContentHuggingPriority(.required, for: .vertical)

        guideButton.title = "macOS 原生快捷键"
        guideButton.target = self
        guideButton.action = #selector(toggleGuide)
        guideButton.bezelStyle = .inline
        guideButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        guideButton.imagePosition = .imageLeading
        guideButton.contentTintColor = .secondaryLabelColor
        guideButton.font = .systemFont(ofSize: 13, weight: .medium)
        guideButton.alignment = .left
        guideButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
        guideButton.setAccessibilityLabel("展开或收起 macOS 原生快捷键")

        let nativeShortcuts = [
            ("magnifyingglass", "聚焦搜索", "⌘ Space"),
            ("rectangle.stack", "切换应用", "⌘ Tab"),
            ("camera.viewfinder", "截图与录屏", "⇧⌘ 5"),
            ("face.smiling", "表情与符号", "⌃⌘ Space"),
            ("exclamationmark.octagon", "强制退出", "⌥⌘ Esc"),
            ("note.text", "快速备忘录", "fn Q")
        ]
        let leftColumn = verticalStack(nativeShortcuts.prefix(3).map(makeSystemShortcutItem), spacing: 10)
        let rightColumn = verticalStack(nativeShortcuts.suffix(3).map(makeSystemShortcutItem), spacing: 10)
        let shortcutGrid = horizontalStack([leftColumn, rightColumn], spacing: 28)
        shortcutGrid.distribution = .fillEqually

        let nativeNote = NSTextField(wrappingLabelWithString:
            "这些由 macOS 自己处理，轻唤不会注册或覆盖。可在“系统设置 > 键盘 > 键盘快捷键”中修改。"
        )
        nativeNote.font = .systemFont(ofSize: 11.5)
        nativeNote.textColor = .secondaryLabelColor
        nativeNote.maximumNumberOfLines = 2

        let customGuide = NSTextField(wrappingLabelWithString:
            "优先推荐未占用的 ⌘0–9。其他可用：⌘⌥K、⌘⇧K、⌃⇧K、⌘⌥←/→、⌃⇧F1–F12。字母、方向键或 F 键至少两个修饰键，并包含 Command 或 Control。系统保留和高风险组合仍会阻止或警告。"
        )
        customGuide.font = .systemFont(ofSize: 11.5)
        customGuide.textColor = .tertiaryLabelColor
        customGuide.maximumNumberOfLines = 2

        let guideContent = verticalStack([shortcutGrid, nativeNote, customGuide], spacing: 10)
        [shortcutGrid, nativeNote, customGuide].forEach {
            $0.widthAnchor.constraint(equalTo: guideContent.widthAnchor).isActive = true
        }
        guideCard.heightAnchor.constraint(equalToConstant: 168).isActive = true
        guideCard.setAccessibilityLabel("macOS 原生快捷键指南")
        pin(guideContent, inside: guideCard, insets: NSEdgeInsets(top: 14, left: 18, bottom: 14, right: 18))

        appGuideButton.title = "应用内快捷键"
        appGuideButton.target = self
        appGuideButton.action = #selector(toggleAppGuide)
        appGuideButton.bezelStyle = .inline
        appGuideButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        appGuideButton.imagePosition = .imageLeading
        appGuideButton.contentTintColor = .secondaryLabelColor
        appGuideButton.font = .systemFont(ofSize: 13, weight: .medium)
        appGuideButton.alignment = .left
        appGuideButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
        appGuideButton.setAccessibilityLabel("展开或收起应用内快捷键")

        let applicationRows = [
            ("com.tencent.xinWeChat", "微信"),
            ("com.openai.codex", "Codex"),
            ("com.google.Chrome", "Chrome")
        ].compactMap { identifier, name in
            makeApplicationShortcutRow(
                bundleIdentifier: identifier,
                name: name,
                shortcuts: ConfirmedAppShortcuts.entries(for: identifier)
            )
        }
        let applicationList: NSView
        if applicationRows.isEmpty {
            let empty = NSTextField(wrappingLabelWithString: "暂未检测到支持的常用应用。")
            empty.textColor = .secondaryLabelColor
            empty.alignment = .center
            applicationList = empty
        } else {
            applicationList = verticalStack(applicationRows, spacing: 8)
        }

        let applicationNote = NSTextField(wrappingLabelWithString:
            "这些快捷键由对应应用提供，轻唤不会注册、修改或覆盖。可能因应用版本、语言或个人设置不同，请以应用菜单与设置为准。"
        )
        applicationNote.font = .systemFont(ofSize: 11.5)
        applicationNote.textColor = .secondaryLabelColor
        applicationNote.maximumNumberOfLines = 2

        let applicationGuideContent = verticalStack([applicationList, applicationNote], spacing: 10)
        [applicationList, applicationNote].forEach {
            $0.widthAnchor.constraint(equalTo: applicationGuideContent.widthAnchor).isActive = true
        }
        appGuideCard.heightAnchor.constraint(equalToConstant: 148).isActive = true
        appGuideCard.isHidden = true
        guideCard.isHidden = true
        appGuideCard.setAccessibilityLabel("已安装应用的快捷键参考")
        pin(
            applicationGuideContent,
            inside: appGuideCard,
            insets: NSEdgeInsets(top: 12, left: 18, bottom: 12, right: 18)
        )

        pendingPicker.onPick = { [weak self] url in
            self?.addPopover.performClose(nil)
            _ = self?.model.addTarget(url: url)
        }
        pendingPicker.onChooseFromDisk = { [weak self] in
            self?.addPopover.performClose(nil)
            self?.chooseApplicationFromDisk()
        }
        addPopover.contentViewController = pendingPicker
        addPopover.behavior = .transient
        helpPopover.behavior = .transient
        applyColorTheme(rebuildRows: false)
        applyAccessibilityChrome()

        let rootStack = verticalStack(
            [header, applicationsCard, permissionRow, guideButton, guideCard, appGuideButton, appGuideCard],
            spacing: 10
        )
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(rootStack)
        header.setContentHuggingPriority(.required, for: .vertical)
        guideButton.setContentHuggingPriority(.required, for: .vertical)
        appGuideButton.setContentHuggingPriority(.required, for: .vertical)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 20),
            rootStack.trailingAnchor.constraint(equalTo: material.trailingAnchor, constant: -20),
            rootStack.topAnchor.constraint(equalTo: material.topAnchor, constant: 36),
            rootStack.bottomAnchor.constraint(equalTo: material.bottomAnchor, constant: -14),
            header.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            applicationsCard.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            permissionRow.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            guideButton.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            guideCard.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            appGuideButton.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            appGuideCard.widthAnchor.constraint(equalTo: rootStack.widthAnchor)
        ])
        window.initialFirstResponder = addButton
    }

    private func rebuildBindingRows() {
        helpPopover.performClose(nil)
        addPopover.performClose(nil)
        bindingsStack.arrangedSubviews.forEach {
            bindingsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        if model.bindings.isEmpty {
            let empty = NSTextField(wrappingLabelWithString: "还没有应用。点击右上角“添加应用…”开始。")
            empty.alignment = .center
            empty.textColor = .secondaryLabelColor
            empty.font = .systemFont(ofSize: 13, weight: .medium)
            empty.heightAnchor.constraint(equalToConstant: 56).isActive = true
            empty.setAccessibilityLabel("尚未添加应用")
            bindingsStack.addArrangedSubview(empty)
        } else {
            model.bindings.forEach { bindingsStack.addArrangedSubview(makeBindingRow($0)) }
        }

        let width = max(listScroll.contentSize.width, 560)
        bindingsStack.frame = NSRect(x: 0, y: 0, width: width, height: 1)
        bindingsStack.layoutSubtreeIfNeeded()
        bindingsStack.frame.size.height = max(bindingsStack.fittingSize.height, listScroll.contentSize.height)
        bindingsStack.arrangedSubviews.forEach {
            $0.widthAnchor.constraint(equalTo: bindingsStack.widthAnchor).isActive = true
        }
    }

    private func makeBindingRow(_ binding: AppBinding) -> NSView {
        let row = NSBox()
        row.boxType = .custom
        row.cornerRadius = 8
        row.borderWidth = 1
        row.borderColor = .separatorColor.withAlphaComponent(0.45)
        row.fillColor = .controlBackgroundColor.withAlphaComponent(0.34)
        row.heightAnchor.constraint(equalToConstant: 52).isActive = true
        row.setAccessibilityLabel("\(binding.target.name) 快捷键设置")

        let icon = NSImageView()
        let image = NSWorkspace.shared.icon(forFile: binding.target.path)
        image.size = NSSize(width: 28, height: 28)
        icon.image = image
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 28).isActive = true
        icon.setAccessibilityLabel("\(binding.target.name) 图标")

        let name = NSTextField(labelWithString: binding.target.name)
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let autoOpen = NSButton(checkboxWithTitle: "未运行时自动打开", target: self, action: #selector(toggleLaunchIfNeeded(_:)))
        autoOpen.identifier = NSUserInterfaceItemIdentifier(binding.id.uuidString)
        autoOpen.state = binding.launchIfNeeded ? .on : .off
        autoOpen.controlSize = .mini
        autoOpen.font = .systemFont(ofSize: 11)
        autoOpen.setAccessibilityLabel("\(binding.target.name) 未运行时自动打开")
        let labels = verticalStack([name, autoOpen], spacing: 1)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let recorder = ShortcutRecorderButton(frame: .zero)
        recorder.bezelColor = colorTheme.recorder
        recorder.shortcut = binding.shortcut
        recorder.onRecord = { [weak self] shortcut in
            self?.model.applyShortcut(shortcut, for: binding.id) == true
        }
        recorder.onClear = { [weak self] in
            self?.model.clearShortcut(for: binding.id) == true
        }
        recorder.onInvalid = { [weak self] message in
            self?.generalStatus.stringValue = message
            self?.generalStatus.textColor = .systemRed
        }
        recorder.controlSize = .small
        recorder.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        recorder.widthAnchor.constraint(equalToConstant: 108).isActive = true
        recorder.heightAnchor.constraint(equalToConstant: 26).isActive = true
        recorder.setAccessibilityLabel("\(binding.target.name) 快捷键录制")
        recorder.toolTip = "推荐 ⌘0–9、⌘⌥K、⌘⇧K、⌃⇧K；冲突时保留原快捷键"

        let helpButton = NSButton()
        helpButton.image = NSImage(
            systemSymbolName: "questionmark.circle",
            accessibilityDescription: "说明"
        )
        helpButton.bezelStyle = .inline
        helpButton.isBordered = false
        helpButton.contentTintColor = .secondaryLabelColor
        helpButton.target = self
        helpButton.action = #selector(showBindingHelp(_:))
        helpButton.identifier = NSUserInterfaceItemIdentifier(binding.id.uuidString)
        helpButton.widthAnchor.constraint(equalToConstant: 22).isActive = true
        helpButton.heightAnchor.constraint(equalToConstant: 22).isActive = true
        helpButton.setAccessibilityLabel("\(binding.target.name) 的快捷键说明")
        helpButton.setAccessibilityHelp("查看轻唤热键、已确认的应用快捷键，以及如何自行查看。")
        helpButton.setAccessibilityRole(.button)
        helpButton.toolTip = "查看这个应用的快捷键说明"

        let deleteButton = NSButton()
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "删除")
        deleteButton.bezelStyle = .inline
        deleteButton.contentTintColor = .secondaryLabelColor
        deleteButton.target = self
        deleteButton.action = #selector(deleteBinding(_:))
        deleteButton.identifier = NSUserInterfaceItemIdentifier(binding.id.uuidString)
        deleteButton.widthAnchor.constraint(equalToConstant: 32).isActive = true
        deleteButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
        deleteButton.setAccessibilityLabel("移除 \(binding.target.name)")

        let rowStack = horizontalStack([icon, labels, spacer, recorder, helpButton, deleteButton], spacing: 10)
        rowStack.alignment = .centerY
        pin(
            rowStack,
            inside: row.contentView ?? row,
            insets: NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 8)
        )
        return row
    }

    private func makeSystemShortcutItem(_ item: (String, String, String)) -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: item.0, accessibilityDescription: item.1)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .medium))
        icon.contentTintColor = colorTheme.primary
        guideAccentIcons.append(icon)
        icon.widthAnchor.constraint(equalToConstant: 22).isActive = true

        let title = NSTextField(labelWithString: item.1)
        title.font = .systemFont(ofSize: 12.5, weight: .medium)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let keys = NSTextField(labelWithString: item.2)
        keys.font = .monospacedSystemFont(ofSize: 11.5, weight: .semibold)
        keys.textColor = .secondaryLabelColor

        let row = horizontalStack([icon, title, spacer, keys], spacing: 8)
        row.alignment = .centerY
        row.heightAnchor.constraint(equalToConstant: 28).isActive = true
        row.setAccessibilityLabel("\(item.1)，\(item.2)")
        return row
    }

    private func makeApplicationShortcutRow(
        bundleIdentifier: String,
        name: String,
        shortcuts: [(String, String)]
    ) -> NSView? {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else { return nil }

        let icon = NSImageView()
        let image = NSWorkspace.shared.icon(forFile: applicationURL.path)
        image.size = NSSize(width: 34, height: 34)
        icon.image = image
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 34).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 34).isActive = true
        icon.setAccessibilityLabel("\(name) 图标")

        let appName = NSTextField(labelWithString: name)
        appName.font = .systemFont(ofSize: 13, weight: .semibold)
        appName.widthAnchor.constraint(equalToConstant: 76).isActive = true

        let tipViews = shortcuts.map { action, keys -> NSView in
            let actionLabel = NSTextField(labelWithString: action)
            actionLabel.font = .systemFont(ofSize: 11.5)
            actionLabel.textColor = .secondaryLabelColor
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let keyLabel = NSTextField(labelWithString: keys)
            keyLabel.font = .monospacedSystemFont(ofSize: 11.5, weight: .semibold)
            let tip = horizontalStack([actionLabel, spacer, keyLabel], spacing: 8)
            tip.alignment = .centerY
            tip.setAccessibilityLabel("\(name)，\(action)，\(keys)")
            return tip
        }
        let tips = horizontalStack(tipViews, spacing: 18)
        tips.distribution = .fillEqually
        let row = horizontalStack([icon, appName, tips], spacing: 10)
        row.alignment = .centerY
        row.heightAnchor.constraint(equalToConstant: 42).isActive = true
        return row
    }

    private func horizontalStack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = spacing
        stack.distribution = .fill
        return stack
    }

    private func verticalStack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.distribution = .fill
        return stack
    }

    private func pin(_ view: NSView, inside container: NSView, insets: NSEdgeInsets) {
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: insets.left),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -insets.right),
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: insets.top),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -insets.bottom)
        ])
    }

    @objc private func chooseApplication() {
        if addPopover.isShown {
            addPopover.performClose(nil)
            return
        }
        var excluded = Set(model.bindings.map(\.target.bundleIdentifier))
        if let selfID = Bundle.main.bundleIdentifier { excluded.insert(selfID) }
        pendingPicker.reload(excluding: excluded)
        addPopover.contentSize = NSSize(width: 300, height: 336)
        addPopover.show(relativeTo: addButton.bounds, of: addButton, preferredEdge: .maxY)
    }

    private func chooseApplicationFromDisk() {
        let panel = NSOpenPanel()
        panel.title = "添加要呼出的应用"
        panel.prompt = "添加"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = model.addTarget(url: url)
    }

    @objc private func showBindingHelp(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue,
              let id = UUID(uuidString: rawValue),
              let binding = model.bindings.first(where: { $0.id == id }) else { return }
        if helpPopover.isShown {
            helpPopover.performClose(nil)
            return
        }
        let controller = NSViewController()
        controller.view = BindingHelpContent.view(for: binding)
        helpPopover.contentViewController = controller
        helpPopover.contentSize = controller.view.fittingSize
        helpPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minX)
    }

    @objc private func toggleLaunchIfNeeded(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue, let id = UUID(uuidString: rawValue) else { return }
        model.toggleLaunchIfNeeded(for: id)
    }

    @objc private func deleteBinding(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue,
              let id = UUID(uuidString: rawValue),
              let binding = model.bindings.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "移除 \(binding.target.name)？"
        alert.informativeText = "会删除这个应用的快捷键设置，不会退出或删除应用。"
        alert.addButton(withTitle: "移除")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        model.removeBinding(id)
    }

    @objc private func toggleEnabled() { model.toggleEnabled() }
    @objc private func requestAccessibility() { model.requestAccessibility() }

    @objc private func selectTheme() {
        colorTheme = themeControl.selectedSegment == 1 ? .ember : .aurora
        UserDefaults.standard.set(colorTheme.rawValue, forKey: "quickToggle.colorTheme")
        applyColorTheme(rebuildRows: true)
    }

    private func applyColorTheme(rebuildRows: Bool) {
        accentRail.theme = colorTheme
        addButton.bezelColor = colorTheme.primary
        settingsShortcutRecorder.bezelColor = colorTheme.recorder
        permissionIcon.contentTintColor = colorTheme.primary
        guideAccentIcons.forEach { $0.contentTintColor = colorTheme.primary }
        enableButton.bezelColor = model.isEnabled ? colorTheme.primary : nil
        applyAccessibilityChrome()
        if rebuildRows { rebuildBindingRows() }
    }

    private func applyAccessibilityChrome() {
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        window.isOpaque = reduced
        window.backgroundColor = reduced ? .windowBackgroundColor : .clear
        if let material = window.contentView as? NSVisualEffectView {
            material.state = reduced ? .inactive : .active
            material.material = reduced ? .contentBackground : .underWindowBackground
        }
    }

    @objc private func toggleGuide() {
        guideExpanded.toggle()
        if guideExpanded { appGuideExpanded = false }
        updateGuideVisibility()
    }

    @objc private func toggleAppGuide() {
        appGuideExpanded.toggle()
        if appGuideExpanded { guideExpanded = false }
        updateGuideVisibility()
    }

    private func updateGuideVisibility() {
        guideCard.isHidden = !guideExpanded
        appGuideCard.isHidden = !appGuideExpanded
        guideButton.image = NSImage(
            systemSymbolName: guideExpanded ? "chevron.down" : "chevron.right",
            accessibilityDescription: nil
        )
        appGuideButton.image = NSImage(
            systemSymbolName: appGuideExpanded ? "chevron.down" : "chevron.right",
            accessibilityDescription: nil
        )
        window.recalculateKeyViewLoop()
    }
}
// MARK: - Menu bar application

private enum LaunchMode {
    case normal
    case smoke
    case idleMeasure
}

private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let mode: LaunchMode
    private let model: QuickToggleModel
    private var statusItem: NSStatusItem?
    private var settings: SettingsController?
    private var previousApplication: NSRunningApplication?
    private var lastHotKeyRecovery = Date.distantPast

    init(mode: LaunchMode) {
        self.mode = mode
        model = QuickToggleModel(diagnosticMode: mode != .normal)
        super.init()
        model.onChange = { [weak self] in self?.refreshInterface() }
        model.onSettingsHotKey = { [weak self] in
            self?.recoverHotKeysIfNeeded()
            self?.toggleSettings()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        observeWorkspaceRecovery()

        switch mode {
        case .normal:
            if model.bindings.isEmpty || model.bindings.allSatisfy({ $0.shortcut == nil }) {
                DispatchQueue.main.async { [weak self] in self?.showSettings() }
            }
        case .smoke:
            showSettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self else { exit(1) }
                let shown = self.statusItem?.button != nil && self.settings?.window.isVisible == true
                self.toggleSettings()
                let passed = shown && self.settings?.window.isVisible == false
                print(passed ? "GUI smoke passed" : "GUI smoke failed")
                exit(passed ? 0 : 1)
            }
        case .idleMeasure:
            break
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        recoverHotKeysIfNeeded()
        refreshInterface()
    }
    func applicationWillTerminate(_ notification: Notification) { model.close() }

    func menuWillOpen(_ menu: NSMenu) {
        recoverHotKeysIfNeeded()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: "轻唤")
            button.image?.isTemplate = true
            button.toolTip = "轻唤"
        }
        statusItem = item
        refreshMenu()
    }

    private func refreshInterface() {
        settings?.refresh()
        refreshMenu()
    }

    private func refreshMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        let state = NSMenuItem(title: model.statusMessage, action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)

        for binding in model.bindings {
            let shortcut = binding.shortcut?.displayName ?? "未设置"
            let item = NSMenuItem(title: "\(binding.target.name)：\(shortcut)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        let settingsShortcut = NSMenuItem(
            title: "显示/隐藏设置：\(model.settingsShortcut.displayName)",
            action: nil,
            keyEquivalent: ""
        )
        settingsShortcut.isEnabled = false
        menu.addItem(settingsShortcut)

        menu.addItem(.separator())
        addMenuItem("显示设置", action: #selector(showSettingsAction), key: ",", to: menu)
        addMenuItem(model.isEnabled ? "停用全部快捷键" : "启用全部快捷键", action: #selector(toggleEnabledAction), to: menu)
        addMenuItem("申请辅助功能权限", action: #selector(requestAccessibilityAction), to: menu)
        menu.addItem(.separator())
        addMenuItem("退出", action: #selector(quitAction), key: "q", to: menu)
        menu.delegate = self
        statusItem.menu = menu
    }

    private func addMenuItem(
        _ title: String,
        action: Selector,
        key: String = "",
        to menu: NSMenu
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    private func showSettings() {
        if settings?.window.isVisible != true,
           let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = frontmost
        }
        if settings == nil { settings = SettingsController(model: model) }
        settings?.show()
    }

    private func toggleSettings() {
        guard let window = settings?.window, window.isVisible else {
            showSettings()
            return
        }

        let shouldRestoreFocus = NSApp.isActive
        window.orderOut(nil)
        if shouldRestoreFocus,
           let previousApplication,
           !previousApplication.isTerminated {
            _ = previousApplication.activate(options: .activateIgnoringOtherApps)
        }
        previousApplication = nil
    }

    @objc private func showSettingsAction() {
        recoverHotKeysIfNeeded()
        showSettings()
    }
    @objc private func toggleEnabledAction() { model.toggleEnabled() }
    @objc private func requestAccessibilityAction() { model.requestAccessibility() }
    @objc private func quitAction() { NSApp.terminate(nil) }

    private func observeWorkspaceRecovery() {
        guard mode == .normal else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            self,
            selector: #selector(handleWorkspaceRecovery),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        workspace.addObserver(
            self,
            selector: #selector(handleWorkspaceRecovery),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        workspace.addObserver(
            self,
            selector: #selector(handleWorkspaceRecovery),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleWorkspaceRecovery),
            name: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
    }

    @objc private func handleWorkspaceRecovery() {
        recoverHotKeysIfNeeded(force: true)
    }

    private func recoverHotKeysIfNeeded(force: Bool = false) {
        guard mode == .normal else { return }
        if relaunchIfOnDiskBuildIsNewer() { return }
        if !force, Date().timeIntervalSince(lastHotKeyRecovery) < 2 { return }
        lastHotKeyRecovery = Date()
        model.recoverHotKeys()
    }

    private func relaunchIfOnDiskBuildIsNewer() -> Bool {
        guard let launched = NSRunningApplication.current.launchDate,
              let executable = Bundle.main.executableURL,
              let modified = try? executable.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              modified.timeIntervalSince(launched) > 2 else { return false }
        let appPath = Bundle.main.bundleURL.path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "sleep 0.4; /usr/bin/open \"\(appPath)\""]
        do {
            try process.run()
        } catch {
            return false
        }
        NSApp.terminate(nil)
        return true
    }
}

// MARK: - Runnable self-test

private enum SelfTest {
    static func run() -> Bool {
        var failures: [String] = []
        checkShortcutRules(&failures)
        checkTransaction(&failures)
        checkStateMachine(&failures)
        checkLaunchPolicy(&failures)
        checkRevealPolicy(&failures)
        checkWindowPresence(&failures)
        checkHotKeyRouting(&failures)
        checkHotKeyRebind(&failures)
        checkMultiBindingPreferences(&failures)
        checkRecorderGate(&failures)
        checkApplicationScanner(&failures)
        checkConfirmedShortcuts(&failures)

        if failures.isEmpty {
            print("QuickToggle self-test passed")
            return true
        }
        failures.forEach { print("QuickToggle self-test failed: \($0)") }
        return false
    }

    private static func checkShortcutRules(_ failures: inout [String]) {
        let valid = Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | shiftKey), label: "K")
        let validOption = Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | optionKey), label: "K")
        let validControl = Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | shiftKey), label: "K")
        let validOpenDisplay = Shortcut(keyCode: UInt32(kVK_ANSI_O), modifiers: UInt32(cmdKey | shiftKey), label: "O")
        let validArrow = Shortcut(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(cmdKey | optionKey), label: "←")
        let validFunction = Shortcut(keyCode: UInt32(kVK_F1), modifiers: UInt32(controlKey | shiftKey), label: "F1")
        let tooFew = Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey), label: "K")
        let noCommandOrControl = Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(optionKey | shiftKey), label: "K")
        let screenCapture = Shortcut(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(cmdKey | shiftKey), label: "3")
        let voiceOver = Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | optionKey), label: "K")
        let settingsDefault = Shortcut(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(cmdKey), label: "3")
        let appNumber = Shortcut(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey), label: "4")
        let unsafeSingleModifier = Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey), label: "K")
        let firstID = UUID()
        let bound = AppBinding(
            id: firstID,
            target: TargetApplication(bundleIdentifier: "test.one", name: "One", path: "/One.app"),
            shortcut: valid,
            launchIfNeeded: true
        )

        if [valid, validOption, validControl, validOpenDisplay, validArrow, validFunction]
            .contains(where: { $0.validationError != nil }) {
            failures.append("recommended shortcuts were rejected")
        }
        if tooFew.validationError == nil { failures.append("single modifier was accepted") }
        if noCommandOrControl.validationError == nil { failures.append("shortcut without Command or Control was accepted") }
        if screenCapture.validationError == nil { failures.append("screen capture shortcut was accepted") }
        if voiceOver.validationError == nil { failures.append("VoiceOver shortcut was accepted") }
        if appNumber.validationError != nil { failures.append("Command-number app shortcut was rejected") }
        if settingsDefault.settingsValidationError != nil { failures.append("default settings shortcut was rejected") }
        if unsafeSingleModifier.settingsValidationError == nil { failures.append("unsafe single-modifier settings shortcut was accepted") }
        if !shortcutIsUsed(valid, in: [bound], excluding: UUID()) {
            failures.append("duplicate app shortcut was not detected")
        }
        if shortcutIsUsed(valid, in: [bound], excluding: firstID) {
            failures.append("binding conflicted with its own shortcut")
        }
    }

    private static func checkTransaction(_ failures: inout [String]) {
        var unregistered: [Int] = []
        var rolledBack: [Int] = []
        let occupied: Result<Int, HotKeyFailure> = RegistrationTransaction.replace(
            current: 1,
            registerCandidate: { .failure(.occupied) },
            unregister: { unregistered.append($0); return .success(()) },
            rollbackCandidate: { rolledBack.append($0) }
        )
        if occupied != .failure(.occupied) || !unregistered.isEmpty || !rolledBack.isEmpty {
            failures.append("candidate failure removed the old hot key")
        }

        let success: Result<Int, HotKeyFailure> = RegistrationTransaction.replace(
            current: 1,
            registerCandidate: { .success(2) },
            unregister: { unregistered.append($0); return .success(()) },
            rollbackCandidate: { rolledBack.append($0) }
        )
        if success != .success(2) || unregistered != [1] || !rolledBack.isEmpty {
            failures.append("successful replacement was not transactional")
        }

        let unregisterFailure: Result<Int, HotKeyFailure> = RegistrationTransaction.replace(
            current: 3,
            registerCandidate: { .success(4) },
            unregister: { _ in .failure(.failed) },
            rollbackCandidate: { rolledBack.append($0) }
        )
        if unregisterFailure != .failure(.failed) || rolledBack != [4] {
            failures.append("candidate was not rolled back after old unregistration failed")
        }
    }

    private static func checkStateMachine(_ failures: inout [String]) {
        func decide(
            original: OriginalStateKind,
            sameProcess: Bool = true,
            frontmost: Bool = false,
            active: Bool = false,
            hidden: Bool = false,
            foreign: Bool = false,
            fresh: Bool = false,
            minimized: Bool? = nil
        ) -> RestoreDecision {
            RestorePlanner.decide(
                original: original,
                sameProcess: sameProcess,
                targetIsFrontmost: frontmost,
                targetIsActive: active,
                targetIsHidden: hidden,
                foreignAppIsFrontmost: foreign,
                sessionIsFresh: fresh,
                restoredWindowIsMinimized: minimized
            )
        }

        let hidden = decide(original: .hidden, frontmost: true)
        let minimized = decide(original: .minimized, frontmost: true, minimized: false)
        let visible = decide(original: .visible, frontmost: true)
        let userChangedState = decide(original: .hidden, foreign: true)
        let activateRace = decide(original: .hidden, foreign: true, fresh: true)
        let accessory = decide(original: .visible)
        let processRestarted = decide(original: .hidden, sameProcess: false, frontmost: true)
        let alreadyHidden = decide(original: .hidden, hidden: true)
        let hideFailedShouldNotReveal = RestorePlanner.shouldRevealAfter(.hideTarget)
        let minimizeFailedShouldNotReveal = RestorePlanner.shouldRevealAfter(.minimizeExactWindow)

        if hidden != .hideTarget { failures.append("hidden branch did not restore hiding") }
        if minimized != .minimizeExactWindow { failures.append("minimized branch did not target the restored window") }
        if visible != .hideTarget { failures.append("visible branch did not hide on the second press") }
        if userChangedState != .none { failures.append("manual state change was not protected") }
        if !RestorePlanner.shouldRevealAfter(userChangedState) {
            failures.append("manual state change did not fall through to a fresh reveal")
        }
        if RestorePlanner.shouldRevealAfter(hidden) {
            failures.append("valid restore unexpectedly fell through to reveal")
        }
        if activateRace != .hideTarget {
            failures.append("fresh second press did not hide before activate settled")
        }
        if accessory != .hideTarget {
            failures.append("non-frontmost session did not hide accessory-style apps")
        }
        if processRestarted != .none || !RestorePlanner.shouldRevealAfter(processRestarted) {
            failures.append("restarted target did not fall through to a fresh reveal")
        }
        if alreadyHidden != .none || !RestorePlanner.shouldRevealAfter(alreadyHidden) {
            failures.append("already-hidden target did not fall through to a fresh reveal")
        }
        if hideFailedShouldNotReveal {
            failures.append("failed hide unexpectedly fell through to reveal")
        }
        if minimizeFailedShouldNotReveal {
            failures.append("failed minimize unexpectedly fell through to reveal")
        }
    }

    private static func checkApplicationScanner(_ failures: inout [String]) {
        if !ApplicationScanner.isExcludedPath("/Applications/Foo.app/Contents/Helpers/Bar.app") {
            failures.append("helper path was accepted")
        }
        if !ApplicationScanner.isExcludedPath("/Applications/Foo.app/Contents/XPCServices/Service.app") {
            failures.append("xpc path was accepted")
        }
        if !ApplicationScanner.isExcludedPath("/Applications/Foo.app/Contents/Frameworks/Plug.app") {
            failures.append("framework path was accepted")
        }
        if ApplicationScanner.isExcludedPath("/Applications/Safari.app") {
            failures.append("normal app path was excluded")
        }
        if !ApplicationScanner.isInvisibleInfo(["LSUIElement": true]) {
            failures.append("LSUIElement app was accepted")
        }
        if !ApplicationScanner.isInvisibleInfo(["LSBackgroundOnly": 1]) {
            failures.append("LSBackgroundOnly app was accepted")
        }
        if ApplicationScanner.isInvisibleInfo(["CFBundleName": "Safari"]) {
            failures.append("visible app info was treated as invisible")
        }
        if let safariURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari"),
           ApplicationScanner.shouldInclude(url: safariURL) {
            let scanned = ApplicationScanner.visibleApplications(excluding: [])
            if !scanned.contains(where: { $0.bundleIdentifier == "com.apple.Safari" }) {
                failures.append("installed Safari was not scanned")
            }
            if ApplicationScanner.visibleApplications(excluding: ["com.apple.Safari"])
                .contains(where: { $0.bundleIdentifier == "com.apple.Safari" }) {
                failures.append("excluded bundle was not filtered")
            }
        }
    }

    private static func checkConfirmedShortcuts(_ failures: inout [String]) {
        if !ConfirmedAppShortcuts.entries(for: "com.unknown.madeup").isEmpty {
            failures.append("unknown app shortcuts were invented")
        }
        if ConfirmedAppShortcuts.entries(for: "com.google.Chrome").isEmpty {
            failures.append("confirmed Chrome shortcuts were missing")
        }
        if ConfirmedAppShortcuts.entries(for: "com.openai.codex").isEmpty {
            failures.append("confirmed Codex shortcuts were missing")
        }
    }

    private static func checkLaunchPolicy(_ failures: inout [String]) {
        if !LaunchPolicy.allowsReveal(isRunning: true, launchIfNeeded: false) {
            failures.append("running target was blocked by launch preference")
        }
        if !LaunchPolicy.allowsReveal(isRunning: false, launchIfNeeded: true) {
            failures.append("automatic launch was not allowed")
        }
        if LaunchPolicy.allowsReveal(isRunning: false, launchIfNeeded: false) {
            failures.append("disabled automatic launch was ignored")
        }
    }

    private static func checkRevealPolicy(_ failures: inout [String]) {
        if !RevealPolicy.shouldHideImmediately(targetIsFrontmost: true, onScreenWindowCount: 1) {
            failures.append("frontmost app with a visible window was not hidden immediately")
        }
        if RevealPolicy.shouldHideImmediately(targetIsFrontmost: true, onScreenWindowCount: 0) {
            failures.append("frontmost app without an on-screen window was hidden instead of reopened")
        }
        if !RevealPolicy.shouldReopen(windowCount: 0) {
            failures.append("windowless running app did not use application reopen")
        }
        if RevealPolicy.shouldReopen(windowCount: 1) {
            failures.append("visible app was reopened unnecessarily")
        }
    }

    private static func checkWindowPresence(_ failures: inout [String]) {
        let pid: pid_t = 4242
        let usable: [String: Any] = [
            kCGWindowOwnerPID as String: pid,
            kCGWindowLayer as String: 0,
            kCGWindowBounds as String: ["Width": CGFloat(800), "Height": CGFloat(600)]
        ]
        let tiny: [String: Any] = [
            kCGWindowOwnerPID as String: pid,
            kCGWindowLayer as String: 0,
            kCGWindowBounds as String: ["Width": CGFloat(16), "Height": CGFloat(16)]
        ]
        let menuLayer: [String: Any] = [
            kCGWindowOwnerPID as String: pid,
            kCGWindowLayer as String: 25,
            kCGWindowBounds as String: ["Width": CGFloat(800), "Height": CGFloat(600)]
        ]
        if !WindowPresence.isUsableWindow(usable, pid: pid) {
            failures.append("on-screen app window was ignored")
        }
        if WindowPresence.isUsableWindow(tiny, pid: pid) {
            failures.append("tiny helper surface was treated as a usable window")
        }
        if WindowPresence.isUsableWindow(menuLayer, pid: pid) {
            failures.append("menu/status surface was treated as a usable window")
        }
        if WindowPresence.isUsableWindow(usable, pid: pid + 1) {
            failures.append("another process window was attributed to the target")
        }
    }

    private static func checkHotKeyRouting(_ failures: inout [String]) {
        let first = HotKeyManager()
        let second = HotKeyManager()
        defer {
            first.close()
            second.close()
        }
        if first.routingSignature == second.routingSignature {
            failures.append("hot key managers reused the same routing signature")
        }
        if !HotKeyManager.routes(eventSignature: first.routingSignature, to: first.routingSignature) {
            failures.append("hot key event did not reach its owner")
        }
        if HotKeyManager.routes(eventSignature: first.routingSignature, to: second.routingSignature) {
            failures.append("hot key event leaked to another manager")
        }
    }

    private static func checkRecorderGate(_ failures: inout [String]) {
        if !ShortcutRecorderButton.shouldCapture(isRecording: true, windowIsKey: true) {
            failures.append("key window recording was rejected")
        }
        if ShortcutRecorderButton.shouldCapture(isRecording: true, windowIsKey: false) {
            failures.append("background window captured a shortcut")
        }
    }

    private static func checkHotKeyRebind(_ failures: inout [String]) {
        let manager = HotKeyManager()
        defer { manager.close() }
        let shortcut = Shortcut(
            keyCode: UInt32(kVK_F12),
            modifiers: UInt32(controlKey | shiftKey),
            label: "F12"
        )
        switch manager.replace(with: shortcut) {
        case .failure(.occupied):
            return
        case .failure(.failed):
            failures.append("hot key rebind setup failed")
            return
        case .success:
            break
        }
        if case .failure = manager.rebind(shortcut) {
            failures.append("rebinding the same hot key failed")
        }
        if !manager.isActive {
            failures.append("rebound hot key was not active")
        }
    }

    private static func checkMultiBindingPreferences(_ failures: inout [String]) {
        let suiteName = "com.quicktoggle.selftest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            failures.append("could not create isolated defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PreferenceStore(defaults: defaults)
        let target = TargetApplication(bundleIdentifier: "test.one", name: "One", path: "/Applications/One.app")
        let shortcut = Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | shiftKey), label: "K")
        let settingsShortcut = Shortcut(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey), label: "4")
        store.target = target
        store.shortcut = shortcut
        store.settingsShortcut = settingsShortcut
        store.launchIfNeeded = false

        if store.settingsShortcut != settingsShortcut {
            failures.append("settings shortcut was not persisted")
        }

        let migrated = store.loadBindings()
        if migrated.count != 1 || migrated[0].target != target || migrated[0].shortcut != shortcut || migrated[0].launchIfNeeded {
            failures.append("single-app preferences were not migrated")
            return
        }
        if store.shortcut != nil {
            failures.append("legacy shortcut was not removed after migration")
        }

        let second = AppBinding(
            id: UUID(),
            target: TargetApplication(bundleIdentifier: "test.two", name: "Two", path: "/Applications/Two.app"),
            shortcut: nil,
            launchIfNeeded: true
        )
        store.saveBindings([migrated[0], second])
        if store.loadBindings().count != 2 {
            failures.append("multiple app bindings were not persisted")
        }
    }
}

private let arguments = Set(CommandLine.arguments.dropFirst())
if arguments.contains("--self-test") {
    exit(SelfTest.run() ? 0 : 1)
}

private let launchMode: LaunchMode = arguments.contains("--smoke-test")
    ? .smoke
    : (arguments.contains("--idle-measure") ? .idleMeasure : .normal)
private let application = NSApplication.shared
private let delegate = AppDelegate(mode: launchMode)
application.delegate = delegate
application.run()
