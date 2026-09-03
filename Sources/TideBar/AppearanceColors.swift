import AppKit
import CoreGraphics

/// 将 AppKit 语义色按指定外观解析为可安全存入 CALayer 的静态颜色。
@MainActor
enum AppearanceColors {
    static func cgColor(_ color: NSColor,
                        alpha: CGFloat? = nil,
                        for appearance: NSAppearance) -> CGColor {
        var resolved = NSColor.clear.cgColor
        appearance.performAsCurrentDrawingAppearance {
            let source = alpha.map(color.withAlphaComponent) ?? color
            resolved = source.cgColor
        }
        return resolved
    }
}
