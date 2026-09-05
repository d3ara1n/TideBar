import TideBarCore

/// 偏好枚举的界面标签。标签属 UI 概念，统一走词条；
/// Settings 界面的 `Text(value.title)` 调用点因此无需感知语言切换机制。
@MainActor
extension IconSizePreset {
    var title: String { L10n.string("iconSize.\(rawValue)", table: .labels) }
}

@MainActor
extension TideLineBrightness {
    var title: String { L10n.string("brightness.\(rawValue)", table: .labels) }
}

@MainActor
extension AnimationPreset {
    var title: String { L10n.string("animation.\(rawValue)", table: .labels) }
}

@MainActor
extension ReducedMotionPreference {
    var title: String { L10n.string("reducedMotion.\(rawValue)", table: .labels) }
}

@MainActor
extension FullscreenBehavior {
    var title: String { L10n.string("fullscreen.\(rawValue)", table: .labels) }
}

@MainActor
extension ApplicationTheme {
    var title: String { L10n.string("theme.\(rawValue)", table: .labels) }
}
