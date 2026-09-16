import SwiftUI
import AVFoundation

// 引导向导视图：四步分页 + 底部导航条。
// 演示素材：第 1 步为实机录屏循环（onboarding-demo.mp4，1670×640，网站演示位共用同一条素材与比例）；
// 第 3 步为代码绘制的接管前后静态对比，不用视频。
// 动效不得成为阅读前提：AppConfiguration.reducedMotion 生效时第 1 步退化为静态占位示意。

/// 演示录屏素材比例（onboarding-demo.mp4）；软件内容器与网站演示位共用。
private enum OnboardingViewConstants {
    static let demoAspectRatio = 1670.0 / 640.0
}

/// 内容区底部的呼吸边距；满宽视频以负 padding 抵消，底边与分割线重合。
private let onboardingContentBottomPadding: CGFloat = 20

struct OnboardingRootView: View {
    @ObservedObject var model: OnboardingModel
    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 44)
                .padding(.bottom, onboardingContentBottomPadding)
                .overlay(alignment: .topTrailing) {
                    // 语言切换只放首步：进入向导时语言未定，这是切换的入口
                    if model.step == .intro {
                        LanguagePicker()
                            .labelsHidden()
                            .controlSize(.small)
                            .fixedSize()
                            .accessibilityLabel(l10n.string("nav.language", table: .onboarding))
                            .padding(.top, 6)
                            .padding(.trailing, 28)
                    }
                }
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
                    Button(l10n.string("nav.skip", table: .onboarding), action: model.finish)
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
                    Button(l10n.string("nav.back", table: .onboarding), action: model.goBack)
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
            Text(model.isLastStep
                 ? l10n.string("nav.getStarted", table: .onboarding)
                 : l10n.string("nav.continue", table: .onboarding))
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
    @Environment(\.l10n) private var l10n
    let step: OnboardingModel.Step

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingModel.Step.allCases, id: \.self) { candidate in
                Circle()
                    .fill(candidate == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityLabel(l10n.string(
            "nav.stepProgress", table: .onboarding,
            arguments: step.rawValue + 1, OnboardingModel.Step.allCases.count))
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

/// 演示占位：reducedMotion 下第 1 步演示视频的静态退化视图。
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

/// 实机录屏无缝循环播放：静音自动播放，AVPlayerLooper 驱动；
/// 视图离开窗口（切步/关窗）即暂停，不后台空转。
private struct DemoLoopVideo: NSViewRepresentable {
    /// App Bundle 内的素材名（不含扩展名）。
    let resource: String

    func makeNSView(context: Context) -> LoopLayerView {
        let view = LoopLayerView()
        view.load(resource: resource)
        return view
    }

    func updateNSView(_ nsView: LoopLayerView, context: Context) {}

    final class LoopLayerView: NSView {
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func makeBackingLayer() -> CALayer { AVPlayerLayer() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let player else { return }
            if window != nil { player.play() } else { player.pause() }
        }

        func load(resource: String) {
            guard let url = Bundle.module.url(forResource: resource, withExtension: "mp4") else { return }
            let queue = AVQueuePlayer()
            queue.isMuted = true
            looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
            guard let layer = layer as? AVPlayerLayer else { return }
            layer.videoGravity = .resizeAspect
            layer.player = queue
            player = queue
            if window != nil { queue.play() }
        }
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
    @Environment(\.l10n) private var l10n
    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                BrandMark()
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)
                Text(l10n.string("intro.title", table: .onboarding))
                    .font(.title.weight(.semibold))
                Text(l10n.string("intro.message", table: .onboarding))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(l10n.string("intro.privacyNote", table: .onboarding))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if Motion.shouldReduceMotion {
                // 减少动态效果：退化为静态占位示意，不自动播放
                DemoPlaceholder(
                    title: l10n.string("intro.demoTitle", table: .onboarding),
                    caption: l10n.string("intro.demoCaption", table: .onboarding)
                )
                .padding(.horizontal, 44)
                .aspectRatio(OnboardingViewConstants.demoAspectRatio, contentMode: .fit)
            } else {
                DemoLoopVideo(resource: "onboarding-demo")
                    .aspectRatio(OnboardingViewConstants.demoAspectRatio, contentMode: .fit)
                    // 满宽无边框：左右边与窗口边重合，底边与内容区分割线重合
                    .padding(.bottom, -onboardingContentBottomPadding)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - 第 2 步：窗口管理权限

private struct PermissionStep: View {
    @Environment(\.l10n) private var l10n
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(title: l10n.string("permission.title", table: .onboarding),
                       message: l10n.string("permission.message", table: .onboarding))

            if model.accessibilityTrusted {
                StatusCard(symbol: "checkmark.circle.fill", tint: .green,
                           title: l10n.string("permission.grantedTitle", table: .onboarding),
                           message: l10n.string("permission.grantedMessage", table: .onboarding))
            } else {
                StatusCard(symbol: "circle.dashed", tint: .orange,
                           title: l10n.string("permission.deniedTitle", table: .onboarding),
                           message: l10n.string("permission.deniedMessage", table: .onboarding))
            }

            if !model.accessibilityTrusted {
                HStack(spacing: 10) {
                    Button(l10n.string("permission.openSettings", table: .onboarding), action: model.openAccessibilitySettings)
                    Button(l10n.string("permission.recheck", table: .onboarding), action: model.refreshPermissionNow)
                }
            }

            Spacer()

            Text(l10n.string("permission.degradedNote", table: .onboarding))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 44)
    }
}

// MARK: - 第 3 步：Dock 接管

private struct TakeoverStep: View {
    @Environment(\.l10n) private var l10n
    @ObservedObject var model: OnboardingModel
    @State private var showEnableConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(title: l10n.string("takeover.title", table: .onboarding),
                       message: l10n.string("takeover.message", table: .onboarding))

            statusArea

            Spacer()

            Text(l10n.string("takeover.persistenceNote", table: .onboarding))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 44)
        .confirmationDialog(l10n.string("takeover.confirmTitle", table: .onboarding),
                            isPresented: $showEnableConfirmation) {
            Button(l10n.string("takeover.confirmEnable", table: .onboarding)) { model.enableTakeover() }
            Button(l10n.string("takeover.cancel", table: .onboarding), role: .cancel) {}
        } message: {
            Text(l10n.string("takeover.confirmMessage", table: .onboarding))
        }
    }

    /// 接管前后选择卡：点击即选中，选中即所选的底部形态；代码绘制，不引入视频素材。
    private struct TakeoverComparison: View {
        @Environment(\.l10n) private var l10n
        /// 当前生效的是否为「接管后」；未接管时选中「接管前」。
        let afterSelected: Bool
        /// 点击「接管后」：请求启用（弹出系统修改确认）。
        let onSelectAfter: () -> Void
        /// 点击「接管前」：保持系统 Dock（向导阶段未接管时无额外操作）。
        let onSelectBefore: () -> Void

        var body: some View {
            HStack(spacing: 12) {
                panel(
                    title: l10n.string("takeover.compare.before", table: .onboarding),
                    caption: l10n.string("takeover.compare.beforeDetail", table: .onboarding),
                    isSelected: !afterSelected,
                    action: onSelectBefore
                ) {
                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(.secondary.opacity(0.55))
                                .frame(width: 15, height: 15)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.bar, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                panel(
                    title: l10n.string("takeover.compare.after", table: .onboarding),
                    caption: l10n.string("takeover.compare.afterDetail", table: .onboarding),
                    isSelected: afterSelected,
                    action: onSelectAfter
                ) {
                    Capsule()
                        .fill(Color.primary.opacity(0.75))
                        .frame(width: 64, height: 3)
                }
            }
        }

        private func panel<Graphic: View>(title: String, caption: String, isSelected: Bool,
                                          action: @escaping () -> Void,
                                          @ViewBuilder graphic: () -> Graphic) -> some View {
            Button(action: action) {
                VStack(spacing: 10) {
                    HStack(spacing: 5) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.caption)
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        Text(title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    }
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.quaternary.opacity(0.5))
                        graphic()
                            .padding(.bottom, 8)
                    }
                    .frame(height: 52)
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear,
                                      lineWidth: isSelected ? 1.5 : 0)
                )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
    }

    @ViewBuilder
    private var statusArea: some View {
        switch model.dockOperation {
        case .working:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(l10n.string("takeover.working", table: .onboarding))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        case .success:
            StatusCard(symbol: "checkmark.circle.fill", tint: .green,
                       title: l10n.string("takeover.successTitle", table: .onboarding),
                       message: l10n.string("takeover.successMessage", table: .onboarding))
        case .failure(.dock(let failure)):
            StatusCard(symbol: "xmark.circle.fill", tint: .red,
                       title: l10n.string("takeover.failureTitle", table: .onboarding),
                       message: l10n.string("takeover.failureMessage", table: .onboarding,
                                            arguments: failure.message(in: l10n)))
            Button(l10n.string("takeover.retry", table: .onboarding), action: model.enableTakeover)
        case .failure(.generic):
            StatusCard(symbol: "xmark.circle.fill", tint: .red,
                       title: l10n.string("takeover.failureTitle", table: .onboarding),
                       message: l10n.string("takeover.failureGenericMessage", table: .onboarding))
            Button(l10n.string("takeover.retry", table: .onboarding), action: model.enableTakeover)
        case .idle:
            idleStatus
        }
    }

    @ViewBuilder
    private var idleStatus: some View {
        if model.isTakeoverEnabled {
            // 重看引导或中途关窗后重开：已是接管态，只展示现状，不重复执行
            StatusCard(symbol: "checkmark.circle.fill", tint: .green,
                       title: l10n.string("takeover.activeTitle", table: .onboarding),
                       message: l10n.string("takeover.activeMessage", table: .onboarding))
        } else {
            switch model.dockState {
            case .drifted:
                StatusCard(symbol: "exclamationmark.triangle.fill", tint: .orange,
                           title: l10n.string("takeover.driftedTitle", table: .onboarding),
                           message: l10n.string("takeover.driftedMessage", table: .onboarding))
            case .manualRecoveryRequired:
                StatusCard(symbol: "exclamationmark.octagon.fill", tint: .red,
                           title: l10n.string("takeover.recoveryTitle", table: .onboarding),
                           message: l10n.string("takeover.recoveryMessage", table: .onboarding))
            default:
                TakeoverComparison(
                    afterSelected: model.isTakeoverEnabled,
                    onSelectAfter: { showEnableConfirmation = true },
                    onSelectBefore: {}
                )
            }
        }
    }
}

// MARK: - 第 4 步：完成与快速提示

private struct FinishStep: View {
    @Environment(\.l10n) private var l10n
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(title: l10n.string("finish.title", table: .onboarding),
                       message: l10n.string("finish.message", table: .onboarding))

            VStack(spacing: 8) {
                capabilityRow(symbol: model.isTakeoverEnabled ? "checkmark.circle.fill" : "circle.dashed",
                              tint: model.isTakeoverEnabled ? .green : .secondary,
                              title: l10n.string("finish.takeoverTitle", table: .onboarding),
                              detail: l10n.string(model.isTakeoverEnabled ? "finish.takeoverOn" : "finish.takeoverOff",
                                                  table: .onboarding))
                capabilityRow(symbol: model.accessibilityTrusted ? "checkmark.circle.fill" : "circle.dashed",
                              tint: model.accessibilityTrusted ? .green : .secondary,
                              title: l10n.string("finish.windowTitle", table: .onboarding),
                              detail: l10n.string(model.accessibilityTrusted ? "finish.windowsOn" : "finish.windowsPending",
                                                  table: .onboarding))
            }

            if model.canManageLoginItem {
                Toggle(l10n.string("finish.launchAtLogin", table: .onboarding), isOn: $model.launchAtLogin)
            } else {
                Text(l10n.string("finish.launchAtLoginDevNote", table: .onboarding))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(l10n.string("finish.gesturesTitle", table: .onboarding))
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                GestureHint(symbol: "cursorarrow",
                            title: l10n.string("finish.gesture.approachTitle", table: .onboarding),
                            detail: l10n.string("finish.gesture.approachDetail", table: .onboarding))
                GestureHint(symbol: "cursorarrow.click",
                            title: l10n.string("finish.gesture.clickTitle", table: .onboarding),
                            detail: l10n.string("finish.gesture.clickDetail", table: .onboarding))
                GestureHint(symbol: "cursorarrow.click.2",
                            title: l10n.string("finish.gesture.holdTitle", table: .onboarding),
                            detail: l10n.string("finish.gesture.holdDetail", table: .onboarding))
                GestureHint(symbol: "option",
                            title: l10n.string("finish.gesture.optionClickTitle", table: .onboarding),
                            detail: l10n.string("finish.gesture.optionClickDetail", table: .onboarding))
                GestureHint(symbol: "cursorarrow.rays",
                            title: l10n.string("finish.gesture.rightClickTitle", table: .onboarding),
                            detail: l10n.string("finish.gesture.rightClickDetail", table: .onboarding))
            }

            Spacer()

            Text(l10n.string("finish.settingsNote", table: .onboarding))
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
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption.weight(.medium))
            }
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(.quaternary.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
