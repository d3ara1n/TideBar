import AppKit
import Testing
@testable import TideBar

/// 名字文本三态：写得下静止、写不下且允许时跑马灯、写不下但不滚时中截断。
/// 「跑马灯在跑」的断言依赖系统未开减弱动态，开启时跳过。
@MainActor
struct ItemNameLabelViewTests {
    private func makeLabel(name: String, viewportWidth: CGFloat) -> ItemNameLabelView {
        let label = ItemNameLabelView(name: name,
                                      font: NSFont.systemFont(ofSize: Layout.nameBubbleFontSize),
                                      color: .labelColor)
        label.setFrameSize(NSSize(width: viewportWidth, height: 20))
        label.layoutSubtreeIfNeeded()
        return label
    }

    @Test func fitsWithoutScrolling() {
        let label = makeLabel(name: "Notes", viewportWidth: 46)
        #expect(!label.isMarqueeRunning)
    }

    @Test func overflowScrollsWhenAllowed() throws {
        guard !Motion.shouldReduceMotion else { return }
        let label = makeLabel(name: "A Very Long Directory Name.xlsx", viewportWidth: 46)
        label.setScrollingAllowed(true)
        #expect(label.isMarqueeRunning)
    }

    @Test func overflowStaysIdleWhenNotAllowed() {
        let label = makeLabel(name: "A Very Long Directory Name.xlsx", viewportWidth: 46)
        #expect(!label.isMarqueeRunning)
    }

    @Test func dismissalStopsMarquee() throws {
        guard !Motion.shouldReduceMotion else { return }
        let label = makeLabel(name: "A Very Long Directory Name.xlsx", viewportWidth: 46)
        label.setScrollingAllowed(true)
        #expect(label.isMarqueeRunning)
        label.setScrollingAllowed(false)
        #expect(!label.isMarqueeRunning)
    }
}

/// 气泡几何：宽度随文字自适应、超长封顶
@MainActor
struct NameBubbleViewTests {
    @Test func widthFollowsText() {
        let short = NameBubbleView.preferredWidth(for: "Notes")
        let long = NameBubbleView.preferredWidth(for: "A Somewhat Longer Name")
        #expect(long > short)
    }

    @Test func widthCapsAtMaximum() {
        let width = NameBubbleView.preferredWidth(for: "An Extremely Long Directory Name That Cannot Possibly Fit.xlsx")
        #expect(width == Layout.nameBubbleMaxWidth)
    }
}
