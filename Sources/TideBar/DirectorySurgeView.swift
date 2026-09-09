import AppKit

// MARK: - 最近文件数据源

/// 目录最近文件：一次 `contentsOfDirectory` 批量预取修改时间（文件名与 stat 在同一次
/// 调用内完成，比逐条取 resourceValues 快一个量级），按修改时间降序截取。
/// 纯函数，可离主线程执行；病态目录按条目预算封顶，超限标记部分视图。
/// 目录迭代顺序与修改时间无关，「只取前几」拿不到最近项，必须全量取值后排序。
enum DirectoryRecentFiles {
    struct Outcome: Sendable, Equatable {
        enum State: Sendable, Equatable {
            /// 修改时间降序的最近条目（已截取到显示上限）
            case rows([URL])
            case empty
            /// 目录不可读、被移动或引用失效
            case failed
        }
        let state: State
        /// 条目超出预算：列表只是部分视图，由体呈现截断态
        let isPartial: Bool

        init(state: State, isPartial: Bool = false) {
            self.state = state
            self.isPartial = isPartial
        }
    }

    static func load(from directory: URL, limit: Int, entryBudget: Int) -> Outcome {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)
        } catch {
            return Outcome(state: .failed)
        }
        guard !children.isEmpty else { return Outcome(state: .empty) }
        let isPartial = children.count > entryBudget
        let candidates = isPartial ? children.prefix(entryBudget) : children[...]
        var dated: [(url: URL, date: Date)] = []
        dated.reserveCapacity(candidates.count)
        for url in candidates {
            // 预取键已在枚举时批量 stat，这里只读缓存值
            guard let date = (try? url.resourceValues(forKeys: Set(keys)))?.contentModificationDate else { continue }
            dated.append((url, date))
        }
        dated.sort { $0.date > $1.date }
        let rows = Array(dated.prefix(limit).map(\.url))
        return Outcome(state: rows.isEmpty ? .empty : .rows(rows), isPartial: isPartial)
    }
}

// MARK: - 状态行

/// 空态／错误态／截断脚注：居中暗显文字，draw 时解析词条（语言切换即时生效）。
@MainActor
final class SurgeStateRowView: NSView {
    private let key: String
    private let fontSize: CGFloat

    init(key: String, height: CGFloat, fontSize: CGFloat) {
        self.key = key
        self.fontSize = fontSize
        super.init(frame: NSRect(x: 0, y: 0, width: Layout.surgeWidth, height: height))
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let text = L10nManager.shared.current.string(key, table: .runtime)
        let onGlass = BarBackgroundFactory.usesGlass
        let color: NSColor = onGlass ? .secondaryLabelColor : NSColor.white.withAlphaComponent(0.55)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        let rect = bounds.insetBy(dx: 12, dy: 0)
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }
}

// MARK: - 目录潮涌体

/// 目录潮涌体：最近修改的文件行（图标 + 名称）；空、不可读与截断态自绘。
/// 每个类型有自己的潮涌体与状态呈现，容器不做统一空态。
@MainActor
final class DirectorySurgeView: NSView, SurgeBody {
    var onOpen: ((URL) -> Void)?

    private var rows: [SurgeRowView] = []
    /// 参与错峰动画的子视图（自上而下顺序：行 + 截断脚注）
    private var animatedRows: [NSView] = []
    private var urls: [Int: URL] = [:]
    private var contentHeight: CGFloat = 0
    var bodySize: NSSize {
        NSSize(width: Layout.surgeWidth, height: contentHeight + Layout.surgeVPadding * 2)
    }

    init(outcome: DirectoryRecentFiles.Outcome) {
        super.init(frame: .zero)
        wantsLayer = true
        var placed: [(view: NSView, height: CGFloat)] = []
        switch outcome.state {
        case .rows(let recent):
            for (index, url) in recent.enumerated() {
                let model = SurgeRowView.Model(identifier: index,
                                               title: FileManager.default.displayName(atPath: url.path),
                                               icon: NSWorkspace.shared.icon(forFile: url.path),
                                               badge: .none,
                                               isDimmed: false)
                let row = SurgeRowView(model: model)
                row.onPick = { [weak self] identifier in
                    guard let self, let url = self.urls[identifier] else { return }
                    self.onOpen?(url)
                }
                urls[index] = url
                rows.append(row)
                placed.append((row, Layout.surgeRowHeight))
            }
            if outcome.isPartial {
                placed.append((SurgeStateRowView(key: "surge.directory.truncated",
                                                  height: Layout.surgeFooterHeight,
                                                  fontSize: Layout.surgeFooterFontSize),
                               Layout.surgeFooterHeight))
            }
        case .empty:
            placed.append((SurgeStateRowView(key: "surge.directory.empty",
                                              height: Layout.surgeRowHeight, fontSize: 13),
                           Layout.surgeRowHeight))
        case .failed:
            placed.append((SurgeStateRowView(key: "surge.directory.unreadable",
                                              height: Layout.surgeRowHeight, fontSize: 13),
                           Layout.surgeRowHeight))
        }
        contentHeight = placed.reduce(0) { $0 + $1.height }
        // 自下而上放置：index 0 为顶行，底边从垂直留白起向上叠
        var bottom = Layout.surgeVPadding
        for entry in placed.reversed() {
            entry.view.frame = NSRect(x: 0, y: bottom, width: Layout.surgeWidth, height: entry.height)
            bottom += entry.height
            addSubview(entry.view)
        }
        animatedRows = placed.map(\.view)
        frame = NSRect(origin: .zero, size: bodySize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// 悬停轮询驱动（面板内容坐标）：命中行高亮，其余清悬停
    func setHover(at point: NSPoint) {
        let hit = hitTest(point) as? SurgeRowView
        for row in rows {
            row.setHovered(row === hit)
        }
    }

    func refreshLocalizedText() {
        for case let state as SurgeStateRowView in animatedRows {
            state.needsDisplay = true
        }
    }

    func rise() {
        SurgeMotion.rise(animatedRows)
    }

    @discardableResult
    func drop() -> TimeInterval {
        SurgeMotion.drop(animatedRows)
    }
}
