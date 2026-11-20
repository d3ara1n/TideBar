# 启动 Bitwarden 时系统 Dock 露出

暂缓。用户报告启动 Bitwarden 时可稳定复现：接管态下系统 Dock 出现在底部，展开 TideBar 后不可见。是否由 macOS 自身、应用激活或其他系统行为触发尚未证实。TideBar 的展开逻辑不写入 Dock 偏好，也不重载 Dock。

恢复排查时，使用固定启动方式复现，并对照其他 App；区分系统 Dock 真正隐藏与被 TideBar 面板遮住。这次保留 Dock 大小的变更不处理露出行为，不引入轮询或 Bitwarden 特判。
