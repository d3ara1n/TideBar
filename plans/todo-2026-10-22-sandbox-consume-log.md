# 启动与固定项刷新时的 sandbox consume 日志

## 状态与证据

非阻塞观察项。用户确认不影响软件使用，不阻塞任务托盘提交。具体系统调用来源仍待定位，不能仅凭日志判定文件操作失败。

2026-10-22 读取本机 unified log，按进程路径和 Mach-O UUID 对照：

- 已安装程序 `/Applications/TideBar.app/Contents/MacOS/TideBar`，文件修改时间 2026-10-12，也输出 `sandbox_extension_consume failed: 22 (Invalid argument)`；日志中的 Mach-O UUID 与该旧程序一致。
- 开发程序 `.build/arm64-apple-macosx/debug/TideBar` 多次运行均有相同日志；日志 UUID 与包含书签选项变更的最新编译产物一致，排除运行旧产物的误判。
- 因此本次任务托盘不是出现该日志的必要条件；现有记录不能确定首次出现的版本或日期。
- 日志中的 `senderProgramCounter` 和 backtrace offset 均为 0，没有可用于定位调用方的栈信息。
- 保存任务托盘默认值经过固定项通知与注册表刷新，会调用应用定位、图标获取、书签解析等公共路径。未确定其中哪一项触发错误。
- 禁用自有书签的隐式临时授权创建与自动消费，未消除日志；不得把该项变更描述为已修复日志。

## 需要定位时

仅在日志影响功能、诊断或明显持续刷屏时恢复排查。现阶段保留正常错误输出。

GUI 由用户运行，不自动启动或附加到正常使用的进程。可在开发程序下使用 LLDB 捕获授权消费调用栈：

```text
lldb .build/debug/TideBar
(lldb) settings set frame-format "frame #${frame.index}: ${module.file.basename} ${function.name-without-args}\n"
(lldb) breakpoint set --name sandbox_extension_consume
(lldb) run
(lldb) thread backtrace -c 24
```

只收集调用栈，不打印函数参数、寄存器内容或授权 token。该断点在调用入口，命中本身不代表失败；需继续执行并与错误出现时点关联。先根据栈确认应用定位／图标读取／书签等具体来源，再决定修复或保留为系统行为观察项。

验收：启动与点击默认星标分别检查日志，同时核对默认设置与实际任务结果；不得通过隐藏 stderr、关闭系统日志或放宽系统权限来掩盖问题。
