import AppKit

/// 实现层参数（决策边界内 agent 自主，调手感时改这里）
@MainActor
enum Layout {
    // 汐线（收起态随亮暗模式自适应的胶囊）
    static let capsuleWidth: CGFloat = 160
    static let capsuleHeight: CGFloat = 3
    /// 全屏点击入口：只在汐线周围提供少量容错，窗口底边贴屏幕底边。
    static let tidelineClickWidth: CGFloat = capsuleWidth + 24
    static let tidelineClickHeight: CGFloat = 16

    // 图标栏（窗口恒为展开尺寸，收起态透明且点击穿透）
    static var expandedHeight: CGFloat { CGFloat(AppConfiguration.shared.iconSize.expandedHeight) }
    static var iconSize: CGFloat { CGFloat(AppConfiguration.shared.iconSize.iconSide) }
    static var iconSlot: CGFloat { CGFloat(AppConfiguration.shared.iconSize.iconSlot) }
    static var iconVisualSide: CGFloat { max(iconSize + 6, iconSlot - 6) }
    static let barHPadding: CGFloat = 10

    // 点点（窗口状态）：颜色=聚焦（强调色）/普通，实心=未最小化、空心=最小化，别屏降透明度；>5 收敛为数字
    static let dotSize: CGFloat = 4.5
    static let dotPitch: CGFloat = 7
    static let dotBaseline: CGFloat = 4.5
    /// 别屏窗口圆点的整体不透明度（实心填充与空心描边同时生效）
    static let dotDimmedOpacity: Float = 0.55
    /// 无可显示窗口点时的运行态短线，与圆点共用基线。
    static let runningDashWidth: CGFloat = 10
    static let runningDashHeight: CGFloat = 3

    // 角标（通知数）：图标右上角红色胶囊 / 小圆点，计数上限显示为 99+
    static let badgeDotSize: CGFloat = 8
    static let badgeCapsuleHeight: CGFloat = 13
    static let badgeCapsuleMinWidth: CGFloat = 13
    static let badgeTextHInset: CGFloat = 5
    static let badgeFontSize: CGFloat = 9.5
    static let badgeCountCap = 99

    // 角标轮询：展开态加速（盯着看要新鲜），收起态降频（脉冲均值延迟 2s）
    static let badgePollExpanded: TimeInterval = 1
    static let badgePollCollapsed: TimeInterval = 4

    // 名字气泡（悬停名，所有条目通用；替代系统 tooltip）：玻璃小泡浮于图标上方
    static let nameBubbleFontSize: CGFloat = 13
    static let nameBubbleMaxWidth: CGFloat = 240
    static let nameBubblePaddingX: CGFloat = 12
    static let nameBubblePaddingY: CGFloat = 6
    /// 与图标栏上缘的间隙（同潮涌）
    static let nameBubbleGap: CGFloat = 8
    static let nameBubbleShowDelay: TimeInterval = 0.35
    static let nameBubbleFadeDuration: TimeInterval = 0.12
    // 跑马灯（气泡内文本超宽时）：匀速是可读性参数（不随动画速度系数缩放），两端停留，溢出过小不值得滚
    static let nameScrollSpeed: CGFloat = 18
    static let nameScrollDwell: TimeInterval = 1.2
    static let nameScrollMinOverflow: CGFloat = 4
    static let nameFadeWidth: CGFloat = 6

    // 手势：先越过拖动阈值则取消长按潮涌；已触发潮涌不再切换成拖拽。
    static let itemDragThreshold: CGFloat = 6

    // 潮涌（二级展开）
    static let surgePressDelay: TimeInterval = 0.4
    static let surgeWidth: CGFloat = 260
    static let surgeRowHeight: CGFloat = 28
    static let surgeVPadding: CGFloat = 6
    static let surgeGap: CGFloat = 8
    // 最小化行尾「已最小化」圆角标签：字号、标签高、水平内边、圆角、标题间隙与右缘留白
    static let surgeMinimizedBadgeFontSize: CGFloat = 10.5
    static let surgeMinimizedBadgeHeight: CGFloat = 16
    static let surgeMinimizedBadgePaddingX: CGFloat = 7
    static let surgeMinimizedBadgeCornerRadius: CGFloat = 5
    static let surgeMinimizedBadgeGap: CGFloat = 8
    static let surgeMinimizedBadgeTrailing: CGFloat = 12
    static var surgeStaggerStep: TimeInterval {
        0.025 / AppConfiguration.shared.animation.speedFactor
    }
    // 目录潮涌体：最近文件显示上限、病态目录条目预算与截断脚注
    static let surgeRecentLimit = 8
    static let surgeRecentEntryBudget = 20_000
    static let surgeFooterHeight: CGFloat = 18
    static let surgeFooterFontSize: CGFloat = 10.5

    // 应用收藏夹潮涌体：面板尺寸固定、网格内部滚动；header 改名、footer 提示
    static let launcherWidth: CGFloat = 300
    static let launcherColumns = 4
    static let launcherCellWidth: CGFloat = 72
    static let launcherCellHeight: CGFloat = 68
    static let launcherIconSide: CGFloat = 40
    static let launcherVisibleRows = 3
    static let launcherHeaderHeight: CGFloat = 34
    static let launcherFooterHeight: CGFloat = 22

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
    static let fullscreenPollInterval: TimeInterval = 0.5
    static let fullscreenFailureGracePeriod: TimeInterval = 2
}
