import SwiftUI

// 引导向导视图：四步分页 + 底部导航条。
// 演示动画规划（当前以占位框标记，后续以代码生成动画填充，录制动图备选）：
//   1. 第 1 步主演示位：汐线 → 应用栏 → 潮涌 的三段式展开过程；
//   2. 第 3 步对比示意位：接管前后（系统 Dock 常驻 ↔ 汐线收于底部）。
// 替换占位时动画不得成为阅读前提：需遵循 AppConfiguration.reducedMotion，
// 减少动态效果下退化为静态示意。

struct OnboardingRootView: View {
    @ObservedObject var model: OnboardingModel
    // 持有语言管理器：切换语言时本视图重算，整树文案随词条更新。
    @ObservedObject private var l10n = L10nManager.shared

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 44)
                .overlay(alignment: .topTrailing) {
                    // 语言切换只放首步：进入向导时语言未定，这是切换的入口
                    if model.step == .intro {
                        LanguagePicker()
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
                    Button(L10n.string("nav.skip", table: .onboarding), action: model.finish)
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
                    Button(L10n.string("nav.back", table: .onboarding), action: model.goBack)
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
                 ? L10n.string("nav.getStarted", table: .onboarding)
                 : L10n.string("nav.continue", table: .onboarding))
                .frame(minWidth: 84)
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(model.dockOperation == .working)
    }
}

/// 应用语言切换：三选（跟随系统 / English / 简体中文）。
/// 语言名按自身语言显示，仅「跟随系统」项随词条翻译。
private struct LanguagePicker: View {
    var body: some View {
        Picker(selection: Binding(
            get: { L10nManager.shared.language },
            set: { L10nManager.shared.setLanguage($0) }
        )) {
            ForEach(AppLanguage.allCases) { language in
                Text(language.displayName).tag(language)
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .accessibilityLabel(L10n.string("nav.language", table: .onboarding))
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
        .accessibilityLabel(L10n.string(
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
                Text(L10n.string("intro.title", table: .onboarding))
                    .font(.title.weight(.semibold))
                Text(L10n.string("intro.message", table: .onboarding))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 演示位 1：汐线 → 应用栏 → 潮涌（代码生成动画占位）
            DemoPlaceholder(
                title: L10n.string("intro.demoTitle", table: .onboarding),
                caption: L10n.string("intro.demoCaption", table: .onboarding)
            )
            .padding(.horizontal, 44)
            .frame(height: 190)

            Text(L10n.string("intro.privacyNote", table: .onboarding))
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
            StepHeader(title: L10n.string("permission.title", table: .onboarding),
                       message: L10n.string("permission.message", table: .onboarding))

            if model.accessibilityTrusted {
                StatusCard(symbol: "checkmark.circle.fill", tint: .green,
                           title: L10n.string("permission.grantedTitle", table: .onboarding),
                           message: L10n.string("permission.grantedMessage", table: .onboarding))
            } else {
                StatusCard(symbol: "circle.dashed", tint: .orange,
                           title: L10n.string("permission.deniedTitle", table: .onboarding),
                           message: L10n.string("permission.deniedMessage", table: .onboarding))
            }

            if !model.accessibilityTrusted {
                HStack(spacing: 10) {
                    Button(L10n.string("permission.openSettings", table: .onboarding), action: model.openAccessibilitySettings)
                    Button(L10n.string("permission.recheck", table: .onboarding), action: model.refreshPermissionNow)
                }
            }

            Spacer()

            Text(L10n.string("permission.degradedNote", table: .onboarding))
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
            StepHeader(title: L10n.string("takeover.title", table: .onboarding),
                       message: L10n.string("takeover.message", table: .onboarding))

            statusArea

            if case .idle = model.dockOperation, !model.isTakeoverEnabled, isNormalDockState {
                HStack(spacing: 10) {
                    Button(L10n.string("takeover.enable", table: .onboarding)) { showEnableConfirmation = true }
                    Button(L10n.string("takeover.notNow", table: .onboarding), action: model.goNext)
                }
            }

            Spacer()

            Text(L10n.string("takeover.persistenceNote", table: .onboarding))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 44)
        .confirmationDialog(L10n.string("takeover.confirmTitle", table: .onboarding),
                            isPresented: $showEnableConfirmation) {
            Button(L10n.string("takeover.confirmEnable", table: .onboarding)) { model.enableTakeover() }
            Button(L10n.string("takeover.cancel", table: .onboarding), role: .cancel) {}
        } message: {
            Text(L10n.string("takeover.confirmMessage", table: .onboarding))
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
                Text(L10n.string("takeover.working", table: .onboarding))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        case .success:
            StatusCard(symbol: "checkmark.circle.fill", tint: .green,
                       title: L10n.string("takeover.successTitle", table: .onboarding),
                       message: L10n.string("takeover.successMessage", table: .onboarding))
        case .failure(.system(let message)):
            StatusCard(symbol: "xmark.circle.fill", tint: .red,
                       title: L10n.string("takeover.failureTitle", table: .onboarding),
                       message: L10n.string("takeover.failureMessage", table: .onboarding, arguments: message))
            Button(L10n.string("takeover.retry", table: .onboarding), action: model.enableTakeover)
        case .failure(.generic):
            StatusCard(symbol: "xmark.circle.fill", tint: .red,
                       title: L10n.string("takeover.failureTitle", table: .onboarding),
                       message: L10n.string("takeover.failureGenericMessage", table: .onboarding))
            Button(L10n.string("takeover.retry", table: .onboarding), action: model.enableTakeover)
        case .idle:
            idleStatus
        }
    }

    @ViewBuilder
    private var idleStatus: some View {
        if model.isTakeoverEnabled {
            // 重看引导或中途关窗后重开：已是接管态，只展示现状，不重复执行
            StatusCard(symbol: "checkmark.circle.fill", tint: .green,
                       title: L10n.string("takeover.activeTitle", table: .onboarding),
                       message: L10n.string("takeover.activeMessage", table: .onboarding))
        } else {
            switch model.dockState {
            case .drifted:
                StatusCard(symbol: "exclamationmark.triangle.fill", tint: .orange,
                           title: L10n.string("takeover.driftedTitle", table: .onboarding),
                           message: L10n.string("takeover.driftedMessage", table: .onboarding))
            case .manualRecoveryRequired:
                StatusCard(symbol: "exclamationmark.octagon.fill", tint: .red,
                           title: L10n.string("takeover.recoveryTitle", table: .onboarding),
                           message: L10n.string("takeover.recoveryMessage", table: .onboarding))
            default:
                // 演示位 2：接管前后对比（代码生成动画或录制动图占位）
                DemoPlaceholder(
                    title: L10n.string("takeover.demoTitle", table: .onboarding),
                    caption: L10n.string("takeover.demoCaption", table: .onboarding)
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
            StepHeader(title: L10n.string("finish.title", table: .onboarding),
                       message: L10n.string("finish.message", table: .onboarding))

            VStack(spacing: 8) {
                capabilityRow(symbol: model.isTakeoverEnabled ? "checkmark.circle.fill" : "circle.dashed",
                              tint: model.isTakeoverEnabled ? .green : .secondary,
                              title: L10n.string("finish.takeoverTitle", table: .onboarding),
                              detail: L10n.string(model.isTakeoverEnabled ? "finish.takeoverOn" : "finish.takeoverOff",
                                                  table: .onboarding))
                capabilityRow(symbol: model.accessibilityTrusted ? "checkmark.circle.fill" : "circle.dashed",
                              tint: model.accessibilityTrusted ? .green : .secondary,
                              title: L10n.string("finish.windowTitle", table: .onboarding),
                              detail: L10n.string(model.accessibilityTrusted ? "finish.windowsOn" : "finish.windowsPending",
                                                  table: .onboarding))
            }

            Text(L10n.string("finish.gesturesTitle", table: .onboarding))
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 10)], spacing: 10) {
                GestureHint(symbol: "cursorarrow",
                            title: L10n.string("finish.gesture.approachTitle", table: .onboarding),
                            detail: L10n.string("finish.gesture.approachDetail", table: .onboarding))
                GestureHint(symbol: "cursorarrow.click",
                            title: L10n.string("finish.gesture.clickTitle", table: .onboarding),
                            detail: L10n.string("finish.gesture.clickDetail", table: .onboarding))
                GestureHint(symbol: "cursorarrow.click.2",
                            title: L10n.string("finish.gesture.holdTitle", table: .onboarding),
                            detail: L10n.string("finish.gesture.holdDetail", table: .onboarding))
                GestureHint(symbol: "option",
                            title: L10n.string("finish.gesture.optionClickTitle", table: .onboarding),
                            detail: L10n.string("finish.gesture.optionClickDetail", table: .onboarding))
                GestureHint(symbol: "cursorarrow.rays",
                            title: L10n.string("finish.gesture.rightClickTitle", table: .onboarding),
                            detail: L10n.string("finish.gesture.rightClickDetail", table: .onboarding))
            }

            Spacer()

            Text(L10n.string("finish.settingsNote", table: .onboarding))
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
