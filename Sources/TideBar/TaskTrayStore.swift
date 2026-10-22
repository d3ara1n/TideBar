import AppKit
import Combine
import TideBarCore

@MainActor
enum TaskTrayText {
    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        let template = L10nManager.shared.current.string(key, table: .runtime)
        return arguments.isEmpty ? template : String(format: template, arguments: arguments)
    }

    static func operation(_ operation: TaskTrayOperation) -> String {
        string("tray.operation.\(operation.rawValue)")
    }
}

struct TaskTrayJobFailure: Sendable {
    let key: String?
    let detail: String
    let mayHavePartialChanges: Bool

    @MainActor
    var message: String {
        let description = key.map { TaskTrayText.string($0) } ?? detail
        return mayHavePartialChanges ? "\(description) \(TaskTrayText.string("tray.error.quarantine"))" : description
    }
}

struct TaskTrayJob: Identifiable {
    enum State {
        case queued, running, completed(URL, changed: Bool), failed(TaskTrayJobFailure)
        var isFinished: Bool {
            switch self {
            case .completed, .failed: true
            case .queued, .running: false
            }
        }
    }
    let id = UUID()
    let source: URL
    let recipe: TaskTrayRecipe
    var state: State = .queued
}

/// 生命周期独立于面板；只有有任务时运行，UI 用事件刷新，不增加轮询。
@MainActor
final class TaskTraySession {
    let changes = PassthroughSubject<Void, Never>()
    private(set) var jobs: [TaskTrayJob] = []
    private(set) var pending: [URL] = []
    private var runner: Task<Void, Never>?
    private(set) var waveTotal = 0
    private(set) var waveFinished = 0

    var unfinishedCount: Int { jobs.filter { !$0.state.isFinished }.count }
    var badgeCount: Int { unfinishedCount + pending.count }
    /// 多文件按完成个数显示，不代表耗时；单文件没有可观测的编码进度。
    var countProgress: Double? {
        unfinishedCount > 0 && waveTotal > 1 ? Double(waveFinished) / Double(waveTotal) : nil
    }

    func stage(_ urls: [URL]) {
        pending.append(contentsOf: urls)
        changes.send()
    }

    func clearPending() {
        pending.removeAll()
        changes.send()
    }

    func enqueue(_ urls: [URL], recipe: TaskTrayRecipe) throws {
        guard !urls.isEmpty, urls.allSatisfy({ TaskTrayWorker.accepts($0, recipe: recipe) }) else {
            throw ItemFailure("tray.error.unsupported")
        }
        if runner == nil { waveTotal = 0; waveFinished = 0 }
        jobs.append(contentsOf: urls.map { TaskTrayJob(source: $0, recipe: recipe) })
        waveTotal += urls.count
        changes.send()
        guard runner == nil else { return }
        runner = Task { [self] in
            while let index = jobs.firstIndex(where: {
                if case .queued = $0.state { return true }
                return false
            }) {
                let job = jobs[index]
                let source = job.source
                let recipe = job.recipe
                jobs[index].state = .running
                changes.send()
                let result = await Task.detached(priority: .userInitiated) {
                    Result { try TaskTrayWorker.run(source, recipe: recipe) }
                }.value
                // 清理记录不会删掉未结束任务，仍按稳定 ID 定位。
                if let current = jobs.firstIndex(where: { $0.id == job.id }) {
                    switch result {
                    case .success(let outcome):
                        jobs[current].state = .completed(outcome.url, changed: outcome.changed)
                    case .failure(let error):
                        jobs[current].state = .failed(TaskTrayJobFailure(
                            key: (error as? TaskTrayWorker.Failure)?.key,
                            detail: error.localizedDescription,
                            mayHavePartialChanges: recipe.operation == .removeQuarantine))
                        NSLog("TideBar task failed: %@", String(describing: error))
                    }
                }
                waveFinished += 1
                changes.send()
            }
            runner = nil
            changes.send()
        }
    }

    func clearFinished() {
        jobs.removeAll { $0.state.isFinished }
        changes.send()
    }
}

@MainActor
final class TaskTrayStore {
    static let shared = TaskTrayStore()
    private var sessions: [UUID: TaskTraySession] = [:]
    var onRequestOpen: ((UUID) -> Void)?

    func session(for instanceID: UUID) -> TaskTraySession {
        if let session = sessions[instanceID] { return session }
        let session = TaskTraySession()
        sessions[instanceID] = session
        return session
    }

    func receive(_ urls: [URL], instanceID: UUID, recipe: TaskTrayRecipe?) throws {
        let session = session(for: instanceID)
        if let recipe {
            try session.enqueue(urls, recipe: recipe)
        } else {
            session.stage(urls)
            // 原生拖放先完成，再显示选操作的面板。
            Task { @MainActor [weak self] in self?.onRequestOpen?(instanceID) }
        }
    }

    func validateRemoval(of reference: ItemReference) throws {
        guard let payload = WidgetReferences.payload(for: reference), payload.type == .taskTray else { return }
        if let session = sessions[payload.instanceID], session.badgeCount > 0 {
            throw ItemFailure("tray.error.busy")
        }
    }
}
