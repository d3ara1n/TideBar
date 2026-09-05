import Foundation

/// Dock 角标的展示值：可解析为正整数 → 计数；非空非数字 → 小圆点。
/// 原始串来自系统 Dock 进程 AX 树的 `AXStatusLabel`（接管态下仍实时更新）。
public enum BadgeValue: Equatable, Sendable {
    case count(Int)
    case dot

    /// 原始字符串 → 展示值；空、零或无法读取返回 nil（不显示角标）。
    public static func parse(_ raw: String?) -> BadgeValue? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let number = Int(trimmed) {
            return number > 0 ? .count(number) : nil
        }
        return .dot
    }
}
