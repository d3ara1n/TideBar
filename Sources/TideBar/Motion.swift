import QuartzCore

/// 潮汐动画语言——所有动效参数的唯一真值。
///
/// 语言三律：
/// 1. **涌潮带弹性，退潮走加速**：展开的形变用 CASpring（~6% 过冲一次回弹 = 水的重量感）；
///    收起一律 easeIn 加速离场且更短——潮来得从容，退得利落。
/// 2. **波扫封顶**：错峰总波窗固定，图标越多步长越密——观感是「一道波扫过」而非逐个排队。
/// 3. **方向感**：展开波自中心（汐线）向两侧发散，收起波向中心汇聚。
///
/// 位移一律走 layer transform，不改 frame——不与布局打架，随时可被反向打断。
enum Motion {
    // MARK: 潮体不透明度编排
    /// 涌潮峰值（玻璃路径下，水体在玻璃凝成前承担视觉主体）
    static let swellPeakOpacity: Float = 0.85
    /// 退潮时水体归来亮度（玻璃退场后接管退潮动画）
    static let retreatOpacity: Float = 0.8

    /// 水体调色：涌起时向玻璃色调过渡（亮色模式变白，「黑矩形消失」因此隐形）
    static let waterTintDelay = 0.06
    static let waterTintDuration = 0.32

    // MARK: 涌潮（展开，总长约 0.4s）

    /// 汐线感应：轻微增厚（预告，让展开不突兀）
    static let senseDuration = 0.14
    /// 潮体胶囊 → bar 的弹性形变
    static let swellDuration = 0.38
    static let swellStiffness: CGFloat = 320
    static let swellDamping: CGFloat = 24
    /// 玻璃显影：潮体胀开的同时玻璃凝成，随后潮体淡出
    static let glassFadeDelay = 0.08
    static let glassFadeDuration = 0.22
    /// 图标波
    static let waveDelay = 0.10
    static let waveWindow = 0.18
    static let iconRiseDuration = 0.26
    static let iconRiseOffset: CGFloat = -14
    static let iconRiseStiffness: CGFloat = 340
    static let iconRiseDamping: CGFloat = 26

    // MARK: 图标轻浮潮（悬停与按压）

    /// hover 在独立视觉层完成，不占用图标按钮根层的整栏波浪 transform。
    static let hoverLift: CGFloat = 3
    static let hoverScale: CGFloat = 1.06
    static let hoverEnterDuration = 0.17
    static let hoverStiffness: CGFloat = 520
    static let hoverDamping: CGFloat = 34
    static let hoverExitDuration = 0.11
    static let pressOffset: CGFloat = -0.5
    static let pressScale: CGFloat = 0.98
    static let pressDuration = 0.07

    // MARK: 潮涌（二级展开，复用涌潮弹性）

    /// 列表行升起位移（从图标栏背后起跳）
    static let surgeRowRiseOffset: CGFloat = -12

    // MARK: 退潮（收起，总长约 0.22s）

    static let collapseDuration = 0.22
    static let dropDuration = 0.16
    static let dropWindow = 0.10
    static let iconDropOffset: CGFloat = 10
    static let glassFadeOut = 0.12
    /// 汐线回归轻弹（潮合上的一下）
    static let capsulePopScale: CGFloat = 1.18
    static let capsulePopDuration = 0.30
    static let capsulePopStiffness: CGFloat = 520
    static let capsulePopDamping: CGFloat = 17

    // MARK: 派生

    /// 发散波步长：最远图标（两端）在 waveWindow 内被波扫到
    static func waveStep(count: Int) -> TimeInterval {
        guard count > 1 else { return 0 }
        return min(0.025, waveWindow * 2 / Double(count - 1))
    }

    /// 汇聚波步长：外圈先离场，中心最后
    static func convergeStep(count: Int) -> TimeInterval {
        guard count > 1 else { return 0 }
        return min(0.02, dropWindow * 2 / Double(count - 1))
    }

    // MARK: 动画工具
    // 模型值先行置为终态，动画从当前 presentation 值出发——
    // 任何时刻反向切换状态都从「现在的样子」继续，无跳变。

    static func spring(_ layer: CALayer, keyPath: String, from: Any? = nil, to: Any,
                       stiffness: CGFloat, damping: CGFloat,
                       minDuration: TimeInterval, delay: TimeInterval = 0) {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.fromValue = from ?? layer.presentation()?.value(forKeyPath: keyPath)
            ?? layer.value(forKeyPath: keyPath)
        animation.toValue = to
        animation.stiffness = stiffness
        animation.damping = damping
        animation.mass = 1
        animation.duration = max(minDuration, animation.settlingDuration)
        animation.beginTime = CACurrentMediaTime() + delay
        animation.fillMode = .backwards
        layer.setValue(to, forKeyPath: keyPath)
        layer.add(animation, forKey: "motion.\(keyPath)")
    }

    static func basic(_ layer: CALayer, keyPath: String, from: Any? = nil, to: Any,
                      duration: TimeInterval, curve: CAMediaTimingFunctionName = .easeOut,
                      delay: TimeInterval = 0) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from ?? layer.presentation()?.value(forKeyPath: keyPath)
            ?? layer.value(forKeyPath: keyPath)
        animation.toValue = to
        animation.duration = duration
        animation.beginTime = CACurrentMediaTime() + delay
        animation.timingFunction = CAMediaTimingFunction(name: curve)
        animation.fillMode = .backwards
        layer.setValue(to, forKeyPath: keyPath)
        layer.add(animation, forKey: "motion.\(keyPath)")
    }
}
