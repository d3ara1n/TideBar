import AppKit
import CoreGraphics

/// 全屏 Space 启发式检测（零权限）：普通层（layer 0）窗口几乎铺满整块显示器即视为全屏。
/// 覆盖 macOS 原生全屏；浏览器内嵌全屏视频仍处于 visibleFrame 内，检测不到（已知局限，手感验证期观察）。
enum FullscreenDetector {
    static func isFullscreen(screen: NSScreen) -> Bool {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        let displayBounds = CGDisplayBounds(id.uint32Value)
        let dockPID = NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == "com.apple.dock" }?
            .processIdentifier

        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        for window in list {
            guard let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0,
                  let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pid != dockPID,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let x = (bounds["X"] as? NSNumber)?.doubleValue,
                  let y = (bounds["Y"] as? NSNumber)?.doubleValue,
                  let w = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let h = (bounds["Height"] as? NSNumber)?.doubleValue else { continue }
            let rect = CGRect(x: x, y: y, width: w, height: h)
            if rect.insetBy(dx: -8, dy: -8).contains(displayBounds) {
                return true
            }
        }
        return false
    }
}
