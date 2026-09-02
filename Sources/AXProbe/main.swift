// AX 探针（M2 前置）：实测真实 app 集的 AX 窗口能力覆盖
//
// 用途见 plans/todo-2026-09-window-surge.md「前置探针」。
// 对所有运行中的常规 app 枚举 kAXWindows，逐窗口读取
// kAXTitle / kAXDocument / kAXMinimized / kAXPosition / kAXSize / AXFullScreen，
// 打印逐 app 覆盖表与汇总，判定 M2 可行性与降级名单。
//
// 需辅助功能权限；由终端运行时，授权对象是终端 App 本身。

import AppKit
import ApplicationServices

// MARK: - AX 读取封装

private func copyValue(_ element: AXUIElement, _ attribute: String) -> (AnyObject?, AXError) {
    var value: AnyObject?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    return (value, error)
}

private func readString(_ element: AXUIElement, _ attribute: String) -> String? {
    let (value, error) = copyValue(element, attribute)
    guard error == .success else { return nil }
    if let url = value as? URL { return url.path }
    return value as? String
}

private func readBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
    let (value, error) = copyValue(element, attribute)
    guard error == .success else { return nil }
    return (value as? NSNumber)?.boolValue
}

private func readPoint(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
    let (value, error) = copyValue(element, attribute)
    guard error == .success, let any = value else { return nil }
    // CF 引用无动态类型检查，实际类型由 AXValueGetType 校验
    let axValue = any as! AXValue
    guard AXValueGetType(axValue) == .cgPoint else { return nil }
    var point = CGPoint.zero
    return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
}

private func readSize(_ element: AXUIElement, _ attribute: String) -> CGSize? {
    let (value, error) = copyValue(element, attribute)
    guard error == .success, let any = value else { return nil }
    let axValue = any as! AXValue
    guard AXValueGetType(axValue) == .cgSize else { return nil }
    var size = CGSize.zero
    return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
}

/// 屏幕归属：窗口矩形中心落在哪块屏。返回 nil 表示不在任何屏内（最小化窗口常见）。
private func screenLabel(of rect: CGRect) -> String {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    for (index, screen) in NSScreen.screens.enumerated() {
        if screen.frame.contains(center) {
            return screen == NSScreen.main ? "main" : "s\(index)"
        }
    }
    return "off"
}

// MARK: - 数据模型

struct WindowProbe {
    var standard = false
    var subrole: String?
    var identifier: String?
    var desktopSuspect = false
    var title: String?
    var document: String?
    var minimized: Bool?
    var position: CGPoint?
    var size: CGSize?
    var fullscreen: Bool?
}

/// app 覆盖分级：
/// - ok：有标准窗口，且全部标准窗口的 min+pos 可读（点点与屏幕归属成立）
/// - partial：能列窗口，但 min/pos 有缺失，或只有非标准窗口（对话框等）
/// - nowindow：AX 正常但零窗口（运行中无窗口态）
/// - axfail：kAXWindows 都读不到（降级为 M1 行为）
enum AppClass: String {
    case ok, partial, nowindow, axfail
}

struct AppProbe {
    var name = ""
    var bundleID = "—"
    var pid: pid_t = 0
    var windowsError: String?
    var windows: [WindowProbe] = []

    var standardWindows: [WindowProbe] { windows.filter(\.standard) }

    var coverage: AppClass {
        if windowsError != nil { return .axfail }
        if windows.isEmpty { return .nowindow }
        let std = standardWindows
        if std.isEmpty { return .partial }
        let minPosOK = std.allSatisfy { $0.minimized != nil && $0.position != nil }
        return minPosOK ? .ok : .partial
    }
}

// MARK: - 探测

private func probeApp(_ app: NSRunningApplication) -> AppProbe {
    var probe = AppProbe()
    probe.name = app.localizedName ?? "?"
    probe.bundleID = app.bundleIdentifier ?? "—"
    probe.pid = app.processIdentifier

    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(appElement, 2.0)

    // kAXWindows 读两次：首次查询偶发 cannotComplete（app 冷启动 / 忙碌），重试一次降低假阴性
    var windows: [AXUIElement]?
    var lastError = AXError.cannotComplete
    for _ in 0..<2 where windows == nil {
        let (value, error) = copyValue(appElement, kAXWindowsAttribute as String)
        lastError = error
        if error == .success, let array = value as? [AnyObject] {
            windows = array.map { $0 as! AXUIElement }
        }
    }
    guard let windows else {
        probe.windowsError = String(describing: lastError)
        return probe
    }

    for window in windows {
        AXUIElementSetMessagingTimeout(window, 2.0)
        var w = WindowProbe()
        w.subrole = readString(window, kAXSubroleAttribute as String)
        w.standard = w.subrole == (kAXStandardWindowSubrole as String)
        w.identifier = readString(window, kAXIdentifierAttribute as String)
        w.title = readString(window, kAXTitleAttribute as String)
        w.document = readString(window, kAXDocumentAttribute as String)
        w.minimized = readBool(window, kAXMinimizedAttribute as String)
        w.position = readPoint(window, kAXPositionAttribute as String)
        w.size = readSize(window, kAXSizeAttribute as String)
        w.fullscreen = readBool(window, "AXFullScreen")
        // 桌面嫌疑：无标题 + 非标准 subrole + 非最小化 + 矩形盖满某块屏 ≥95%
        if w.title == nil, w.minimized != true, let p = w.position, let s = w.size {
            let frame = CGRect(origin: p, size: s)
            w.desktopSuspect = NSScreen.screens.contains { screen in
                let inset = screen.frame.insetBy(dx: screen.frame.width * 0.05,
                                                 dy: screen.frame.height * 0.05)
                return frame.contains(inset)
            }
        }
        probe.windows.append(w)
    }
    return probe
}

// MARK: - 输出

private func printApp(_ probe: AppProbe) {
    let tag = probe.coverage.rawValue.uppercased()
    print("\(probe.name)  pid=\(probe.pid)  \(probe.bundleID)")
    if let error = probe.windowsError {
        print("  [\(tag)] kAXWindows 读取失败: \(error)")
        print()
        return
    }
    print("  [\(tag)] windows=\(probe.windows.count) standard=\(probe.standardWindows.count)")
    for (i, w) in probe.windows.enumerated() {
        let kind = w.standard ? "std" : "dlg"
        var fields: [String] = ["#\(i + 1)", kind]
        if !w.standard { fields.append("sub=\(w.subrole ?? "∅")") }
        if let id = w.identifier, !id.isEmpty { fields.append("id=\"\(prefix(of: id, 20))\"") }
        if w.desktopSuspect { fields.append("DESKTOP?") }
        fields.append(w.minimized.map { "min=\($0 ? 1 : 0)" } ?? "!min")
        if let fs = w.fullscreen { fields.append("fs=\(fs ? 1 : 0)") }
        if let p = w.position, let s = w.size {
            let rect = CGRect(origin: p, size: s)
            fields.append("(\(Int(p.x)),\(Int(p.y)))\(Int(s.width))×\(Int(s.height))@\(screenLabel(of: rect))")
        } else if let p = w.position {
            fields.append("(\(Int(p.x)),\(Int(p.y)))@?")
        } else {
            fields.append("!pos")
        }
        let title = w.title.map { "\"\(prefix(of: $0, 40))\"" } ?? "!title"
        fields.append("title=\(title)")
        if let doc = w.document { fields.append("doc=\"\(prefix(of: doc, 40))\"") }
        print("    " + fields.joined(separator: "  "))
    }
    print()
}

private func prefix(of text: String, _ limit: Int) -> String {
    text.count <= limit ? text : String(text.prefix(limit)) + "…"
}

private func printSummary(_ probes: [AppProbe]) {
    let counts = Dictionary(grouping: probes, by: \.coverage)
        .mapValues(\.count)
    let fmt = { (c: AppClass) -> String in
        "\(c.rawValue)=\(counts[c] ?? 0)"
    }
    print("=== 汇总（app \(probes.count) 个）===")
    print("覆盖分级: \(fmt(.ok)) \(fmt(.partial)) \(fmt(.nowindow)) \(fmt(.axfail))")

    let stdWindows = probes.flatMap(\.standardWindows)
    if !stdWindows.isEmpty {
        let total = stdWindows.count
        func ratio(_ get: (WindowProbe) -> Any?) -> String {
            let hit = stdWindows.filter { get($0) != nil }.count
            return "\(hit)/\(total)"
        }
        print("属性覆盖（标准窗口 \(total) 个）:")
        print("  kAXTitle      \(ratio { $0.title })")
        print("  kAXDocument   \(ratio { $0.document })")
        print("  kAXMinimized  \(ratio { $0.minimized })")
        print("  kAXPosition   \(ratio { $0.position })")
        print("  kAXFullScreen \(ratio { $0.fullscreen })")
    }

    let degraded = probes.filter { $0.coverage != .ok }
    if !degraded.isEmpty {
        print("降级名单:")
        for p in degraded {
            let reason: String
            switch p.coverage {
            case .axfail: reason = "kAXWindows 失败(\(p.windowsError ?? "?"))"
            case .nowindow: reason = "运行中但零窗口"
            case .partial:
                let bad = p.standardWindows.filter { $0.minimized == nil || $0.position == nil }
                reason = bad.isEmpty ? "仅非标准窗口" : "min/pos 缺失 \(bad.count)/\(p.standardWindows.count)"
            case .ok: reason = ""
            }
            print("  \(p.name): \(reason)")
        }
    }
}

// MARK: - 主流程

if !AXIsProcessTrusted() {
    // kAXTrustedCheckOptionPrompt 是 C 全局变量，Swift 6 并发检查不通过，用字面值绕开
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
    FileHandle.standardError.write(
        """
        [!] 未获辅助功能权限。请在 系统设置 → 隐私与安全性 → 辅助功能
            勾选运行本探针的终端 App（Terminal / iTerm / Ghostty 等），然后重跑。
            注意：授权对象是终端本身，不是探针二进制。

        """.data(using: .utf8)!)
    exit(1)
}

let apps = NSWorkspace.shared.runningApplications
    .filter { $0.activationPolicy == .regular }
    .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

print("=== AX 窗口能力探针 | 常规 app \(apps.count) 个 | \(Date().formatted()) ===")
print("窗口行字段: #序号 std/dlg(标准窗口/非标准) sub(非标准时的原始 subrole，∅=属性缺失) id min fs (x,y)w×h@屏 title doc；! 前缀=读取失败；DESKTOP?=桌面窗口嫌疑")
print()

var probes: [AppProbe] = []
for app in apps {
    probes.append(probeApp(app))
}
for probe in probes {
    printApp(probe)
}
printSummary(probes)
