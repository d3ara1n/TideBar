import AppKit

/// 实现层参数（决策边界内 agent 自主，调手感时改这里）
enum Layout {
    /// 测试期悬浮高度：暂不隐藏系统 Dock，TideBar 浮于屏幕底边上方避免重叠。
    /// UserDefaults 键 `tidebar.offsetY`（pt），缺省 140；M3 接管向导后归零。
    static var offsetY: CGFloat {
        let raw = UserDefaults.standard.double(forKey: "tidebar.offsetY")
        return raw > 0 ? raw : 140
    }

    // 汐线（收起态白色胶囊）
    static let capsuleWidth: CGFloat = 160
    static let capsuleHeight: CGFloat = 3
    static let collapsedPanelWidth: CGFloat = 200
    static let collapsedPanelHeight: CGFloat = 14

    // 展开态图标栏
    static let expandedHeight: CGFloat = 64
    static let iconSize: CGFloat = 40
    static let iconSlot: CGFloat = 52
    static let barHPadding: CGFloat = 10

    // 接近热区（收起态触发展开）：胶囊外扩范围
    static let hotMarginX: CGFloat = 120
    static let hotMarginBelow: CGFloat = 18
    static let hotMarginAbove: CGFloat = 26

    // 滞留热区（展开态维持）：panel frame 外扩
    static let keepMargin: CGFloat = 14

    // 动画与防抖
    static let expandDuration: TimeInterval = 0.42
    static let collapseDuration: TimeInterval = 0.3
    static let staggerStep: TimeInterval = 0.025
    static let staggerDuration: TimeInterval = 0.28
    static let collapseDebounce: TimeInterval = 0.3

    // 采样与兜底
    static let mouseSampleThrottle: TimeInterval = 0.04
    static let pollInterval: TimeInterval = 0.25
    static let fullscreenCacheTTL: TimeInterval = 0.5
}
