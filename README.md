# TideBar · 汐

macOS Dock 替代：平时缩成屏幕底部一条细线，鼠标靠近时如潮汐般展开。

## 架构决策

- 系统 Dock 进程保留，仅配置级隐藏（`autohide-delay` 极大值），不禁用进程
- 本体为无边框 `NSPanel`（`.nonactivatingPanel` + `.canJoinAllSpaces` + `.fullScreenAuxiliary`）悬浮于所有 Space 底部
- Cmd-Tab / Mission Control / 最小化动画由系统继续提供，不自绘

## 开发

```bash
swift build    # 编译
swift run      # 本地运行（期间终端会话被占用）
```

- 权限：骨架阶段零权限
- 打包 `.app` 与签名公证流程后续补充
- bundle id 占位 `dev.tidebar.TideBar`，发布前更换
