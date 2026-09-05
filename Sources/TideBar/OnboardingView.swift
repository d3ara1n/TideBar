import SwiftUI

// 引导向导视图：四步分页 + 底部导航条。
// 演示动画规划（当前以占位框标记，后续以代码生成动画填充，录制动图备选）：
//   1. 第 1 步主演示位：汐线 → 应用栏 → 潮涌 的三段式展开过程；
//   2. 第 3 步对比示意位：接管前后（系统 Dock 常驻 ↔ 汐线收于底部）。
// 替换占位时动画不得成为阅读前提：需遵循 AppConfiguration.reducedMotion，
// 减少动态效果下退化为静态示意。

struct OnboardingRootView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 44)
            Divider()
            navigationBar
        }
        .frame(width: 640, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .intro: IntroStep()
        case .permission: PermissionStep(model: model)
        case .takeover: TakeoverStep(model: model)
        case .finish: FinishStep(model: model)
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 8) {
            Group {
                if model.isLastStep {
                    EmptyView()
                } else {
                    Button("跳过引导", action: model.finish)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(model.dockOperation == .working)
                }
            }
            .frame(width: 110, alignment: .leading)

            Spacer()

            StepDots(step: model.step)

            Spacer()

            HStack(spacing: 8) {
                if model.canGoBack {
                    Button("返回", action: model.goBack)
                        .disabled(model.dockOperation == .working)
                }
                mainButton
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }

    private var mainButton: some View {
        Button {
            if model.isLastStep {
                model.finish()
            } else {
                model.goNext()
            }
        } label: {
            Text(model.isLastStep ? "开始使用" : "继续")
                .frame(minWidth: 84)
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(model.dockOperation == .working)
    }
}

// MARK: - 通用组件

/// 步骤圆点指示器。
private struct StepDots: View {
    let step: OnboardingModel.Step

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingModel.Step.allCases, id: \.self) { candidate in
                Circle()
                    .fill(candidate == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityLabel("第 \(step.rawValue + 1) 步，共 \(OnboardingModel.Step.allCases.count) 步")
    }
}

/// 每步共用的标题区。
private struct StepHeader: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title2.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 演示占位：标记后续填充代码生成动画（或录制动图）的位置。
private struct DemoPlaceholder: View {
    let title: String
    let caption: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.callout.weight(.medium))
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.03),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .foregroundStyle(.quaternary)
        )
    }
}

/// 向导内的状态卡：图标 + 标题 + 说明，动作按钮由各步骤独立放置。
private struct StatusCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - 第 1 步：认识汐

private struct IntroStep: View {
    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Image(systemName: "water.waves")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("欢迎使用汐 TideBar")
                    .font(.title.weight(.semibold))
                Text("汐是一条收在屏幕底部的细线，空闲时几乎不可见。鼠标靠近时它潮汐般展开为应用栏；长按图标还能直达该应用的任意窗口——包括最小化的。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 演示位 1：汐线 → 应用栏 → 潮涌（代码生成动画占位）
            DemoPlaceholder(
                title: "演示：汐线 → 应用栏 → 潮涌",
                caption: "鼠标靠近，细线展开为应用栏；长按（或 ⌥+点击）图标，潮涌列出该应用的全部窗口"
            )
            .padding(.horizontal, 44)
            .frame(height: 190)

            Text("汐不提供窗口内容缩略图，也不会请求屏幕录制权限。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - 第 2 步：窗口管理权限

private struct PermissionStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(title: "窗口管理权限",
                       message: "辅助功能权限用于读取窗口列表、识别最小化状态，并把选中的窗口还原置前。")

            if model.accessibilityTrusted {
                StatusCard(symbol: "checkmark.circle.fill", tint: .green,
                           title: "已授权",
                           message: "窗口管理已具备运行条件。若刚刚完成授权，重启汐后即可管理已打开的应用。")
            } else {
                StatusCard(symbol: "circle.dashed", tint: .orange,
                           title: "未授权",
                           message: "授权后汐才能列出并还原窗口。系统设置可能需要数秒刷新，可点击「重新检查」确认。")
            }

            if !model.accessibilityTrusted {
                HStack(spacing: 10) {
                    Button("打开系统设置", action: model.openAccessibilitySettings)
                    Button("重新检查", action: model.refreshPermissionNow)
                }
            }

            Spacer()

            Text("未授权也可以继续使用：汐线与应用栏不受影响，只是无法列出和还原窗口。稍后可在设置中心的「权限」页完成授权。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 44)
    }
}

// MARK: - 第 3 步：Dock 接管

private struct TakeoverStep: View {
    @ObservedObject var model: OnboardingModel
    @State private var showEnableConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(title: "Dock 接管",
                       message: "启用后，汐会隐藏系统 Dock 的可见入口，由屏幕底部的汐线接替。Dock 进程不会被关闭，已打开的应用不受影响。")

            statusArea

            if case .idle = model.dockOperation, !model.isTakeoverEnabled, isNormalDockState {
                HStack(spacing: 10) {
                    Button("启用 TideBar") { showEnableConfirmation = true }
                    Button("暂不启用", action: model.goNext)
                }
            }

            Spacer()

            Text("启用前会保存当前 Dock 配置；关闭 TideBar 或退出应用时都会自动恢复，设置中心的「Dock 与恢复」页也可随时手动恢复。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 44)
        .confirmationDialog("启用 TideBar？", isPresented: $showEnableConfirmation) {
            Button("启用 TideBar") { model.enableTakeover() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("汐会保存当前 Dock 设置、应用接管配置并重新启动系统 Dock。已打开的应用不会关闭。")
        }
    }

    private var isNormalDockState: Bool {
        switch model.dockState {
        case .notEnabled: return true
        default: return false
        }
    }

    @ViewBuilder
    private var statusArea: some View {
        switch model.dockOperation {
        case .working:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("正在启用 TideBar…")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        case .success(let message):
            StatusCard(symbol: "checkmark.circle.fill", tint: .green,
                       title: "TideBar 已启用",
                       message: message)
        case .failure(let message):
            StatusCard(symbol: "xmark.circle.fill", tint: .red,
                       title: "启用失败",
                       message: "\(message) Dock 设置已回滚到启用前状态，可以重试。")
            Button("重试", action: model.enableTakeover)
        case .idle:
            idleStatus
        }
    }

    @ViewBuilder
    private var idleStatus: some View {
        if model.isTakeoverEnabled {
            // 重看引导或中途关窗后重开：已是接管态，只展示现状，不重复执行
            StatusCard(symbol: "checkmark.circle.fill", tint: .green,
                       title: "TideBar 正在接管系统 Dock",
                       message: "系统 Dock 的可见入口已由汐接替，汐线正在屏幕底部待命。")
        } else {
            switch model.dockState {
            case .drifted:
                StatusCard(symbol: "exclamationmark.triangle.fill", tint: .orange,
                           title: "系统 Dock 设置已发生变化",
                           message: "汐检测到既有接管配置不一致。请到设置中心的「Dock 与恢复」页重新应用。")
            case .manualRecoveryRequired:
                StatusCard(symbol: "exclamationmark.octagon.fill", tint: .red,
                           title: "无法自动恢复 macOS Dock",
                           message: "缺少接管前保存的 Dock 配置。请到设置中心的「Dock 与恢复」页查看处理方式。")
            default:
                // 演示位 2：接管前后对比（代码生成动画或录制动图占位）
                DemoPlaceholder(
                    title: "演示：接管前后的底部变化",
                    caption: "启用前系统 Dock 常驻屏幕底部；启用后 Dock 收起，汐线在原位待命"
                )
                .frame(height: 150)
            }
        }
    }
}

// MARK: - 第 4 步：完成与快速提示

private struct FinishStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(title: "一切就绪",
                       message: "以下是当前的能力状态与常用操作，之后随时可在设置中心调整。")

            VStack(spacing: 8) {
                capabilityRow(symbol: model.isTakeoverEnabled ? "checkmark.circle.fill" : "circle.dashed",
                              tint: model.isTakeoverEnabled ? .green : .secondary,
                              title: "Dock 接管",
                              detail: model.isTakeoverEnabled ? "已启用，汐线在屏幕底部待命" : "未启用，可稍后在设置中心开启")
                capabilityRow(symbol: model.accessibilityTrusted ? "checkmark.circle.fill" : "circle.dashed",
                              tint: model.accessibilityTrusted ? .green : .secondary,
                              title: "窗口管理",
                              detail: model.accessibilityTrusted ? "已授权，可列出并还原窗口" : "待授权，稍后可在设置中心完成")
            }

            Text("常用操作")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 10)], spacing: 10) {
                GestureHint(symbol: "cursorarrow", title: "靠近", detail: "汐线自动展开")
                GestureHint(symbol: "cursorarrow.click", title: "点击", detail: "启动或切换应用")
                GestureHint(symbol: "cursorarrow.click.2", title: "长按", detail: "潮涌窗口列表")
                GestureHint(symbol: "option", title: "⌥+点击", detail: "直接弹出潮涌")
                GestureHint(symbol: "cursorarrow.rays", title: "右键", detail: "固定、隐藏与退出")
            }

            Spacer()

            Text("外观、全屏行为与快捷键都可在设置中心调整；菜单栏的汐图标随时可以打开设置。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 44)
    }

    private func capabilityRow(symbol: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title).font(.callout.weight(.medium))
            Spacer()
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct GestureHint: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title).font(.callout.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
