import AppKit

/// 实现层参数（决策边界内 agent 自主，调手感时改这里）
enum Layout {
    // 汐线（收起态随亮暗模式自适应的胶囊）
    static let capsuleWidth: CGFloat = 160
    static let capsuleHeight: CGFloat = 3

    // 图标栏（窗口恒为展开尺寸，收起态透明且点击穿透）
    static let expandedHeight: CGFloat = 64
    static let iconSize: CGFloat = 40
    static let iconSlot: CGFloat = 52
    static let barHPadding: CGFloat = 10

    // 点点（窗口状态）：实心=活跃、空心=最小化，>5 收敛为数字
    static let dotSize: CGFloat = 4.5
    static let dotPitch: CGFloat = 7
    static let dotBaseline: CGFloat = 4.5

    // 潮涌（二级展开）
    static let surgePressDelay: TimeInterval = 0.4
    static let surgeWidth: CGFloat = 260
    static let surgeRowHeight: CGFloat = 28
    static let surgeVPadding: CGFloat = 6
    static let surgeGap: CGFloat = 8
    static let surgeStaggerStep: TimeInterval = 0.025
    static let surgeDismissDebounce: TimeInterval = 0.3

    // 接近热区（收起态触发展开）：胶囊外扩范围
    static let hotMarginX: CGFloat = 120
    static let hotMarginBelow: CGFloat = 18
    static let hotMarginAbove: CGFloat = 26

    // 滞留热区（展开态维持）：panel frame 外扩
    static let keepMargin: CGFloat = 14

    // 防抖与采样（动画参数见 Motion.swift）
    static let collapseDebounce: TimeInterval = 0.3

    // 采样与兜底
    static let mouseSampleThrottle: TimeInterval = 0.04
    static let pollInterval: TimeInterval = 0.25
    static let fullscreenCacheTTL: TimeInterval = 0.5
}
