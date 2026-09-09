import AppKit
import Foundation

/// 把任意 block 回调桥接到 MainActor。
/// 事件监视器/通知/定时器的 block 在 SDK 中无隔离标注，实际派发都在主线程；
/// @unchecked Sendable 的责任边界 = call() 只会落在主线程或经 Task @MainActor 转发。
final class MainThreadBridge: @unchecked Sendable {
    private let handler: @MainActor () -> Void

    init(_ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    func call() {
        if Thread.isMainThread {
            MainActor.assumeIsolated { handler() }
        } else {
            Task { @MainActor in handler() }
        }
    }

    func callAsFunction() { call() }
}

/// 携带一枚 NSEvent 过主线程桥：monitor 回调无法直接把非 Sendable 事件
/// 传入 MainActor 方法；monitor 派发本身在主线程，存取串行无竞争。
final class NSEventBox: @unchecked Sendable {
    private var event: NSEvent?
    func store(_ event: NSEvent) { self.event = event }
    func take() -> NSEvent? {
        defer { event = nil }
        return event
    }
}
