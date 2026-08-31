# TideBar 项目规范

进入本仓库工作前，先完整阅读 `docs/HANDOFF.md`——它包含产品定位、已定架构决策（勿推翻重议）、调研结论、路线图与当前进度。

- 技术栈：Swift 6 + SPM + AppKit，零第三方依赖，不用 Xcode 工程
- bash 冒烟测试 GUI 进程必须「启动→验证→kill」同一条命令完成
- 系统级命令（如隐藏系统 Dock 的 defaults 写入）只输出给用户执行，或经确认后执行，不静默改
