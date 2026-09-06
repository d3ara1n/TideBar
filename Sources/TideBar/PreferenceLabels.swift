import TideBarCore

/// 偏好枚举只提供稳定词条 key；消费标签的视图负责读取语言环境。
extension IconSizePreset {
    var titleKey: String { "iconSize.\(rawValue)" }
}

extension TideLineBrightness {
    var titleKey: String { "brightness.\(rawValue)" }
}

extension AnimationPreset {
    var titleKey: String { "animation.\(rawValue)" }
}

extension ReducedMotionPreference {
    var titleKey: String { "reducedMotion.\(rawValue)" }
}

extension FullscreenBehavior {
    var titleKey: String { "fullscreen.\(rawValue)" }
}

extension ApplicationTheme {
    var titleKey: String { "theme.\(rawValue)" }
}
