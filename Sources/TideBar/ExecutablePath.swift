import AppKit
import Darwin

extension NSRunningApplication {
    /// 进程可执行文件的真实路径（保留大小写）；解析失败返回 nil。
    /// 裸进程（无 bundle 的 regular GUI，如 .NET/Avalonia 调试目标）用它派生身份与文件操作。
    var executablePath: String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(processIdentifier, &buffer, UInt32(MAXPATHLEN))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
