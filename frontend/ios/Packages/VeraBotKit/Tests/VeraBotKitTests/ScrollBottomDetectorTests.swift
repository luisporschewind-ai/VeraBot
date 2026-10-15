import CoreGraphics
import Testing
@testable import VeraBotCore

/// 数值取自 iPhone 17 模拟器实测（全局坐标）：视口 y 116…780，贴底时锚点约在 763。
private let viewport = CGRect(x: 0, y: 116, width: 402, height: 664)
private func anchor(at y: CGFloat) -> CGRect { CGRect(x: 16, y: y, width: 370, height: 1) }

@Test func scrollBottomAtBottomIsNearBottom() {
    #expect(ScrollBottomDetector.isNearBottom(anchor: anchor(at: 763), viewport: viewport))
    #expect(ScrollBottomDetector.isNearBottom(anchor: anchor(at: 779), viewport: viewport))
}

@Test func scrollBottomSlightlyAboveWithinToleranceIsNearBottom() {
    #expect(ScrollBottomDetector.isNearBottom(anchor: anchor(at: 792), viewport: viewport))
    #expect(ScrollBottomDetector.isNearBottom(anchor: anchor(at: 780 + 40), viewport: viewport))
}

@Test func scrollBottomScrolledFarUpIsNotNearBottom() {
    #expect(!ScrollBottomDetector.isNearBottom(anchor: anchor(at: 5876), viewport: viewport))
}

@Test func scrollBottomAnchorBelowViewportBeyondToleranceIsNotNearBottom() {
    #expect(!ScrollBottomDetector.isNearBottom(anchor: anchor(at: 780 + 41), viewport: viewport))
    #expect(!ScrollBottomDetector.isNearBottom(anchor: anchor(at: 1008), viewport: viewport))
    #expect(ScrollBottomDetector.isNearBottom(anchor: anchor(at: 1008), viewport: viewport, tolerance: 300))
}

@Test func scrollBottomOverscrollPastBottomIsNearBottom() {
    #expect(ScrollBottomDetector.isNearBottom(anchor: anchor(at: 60), viewport: viewport))
}

/// 回归：测量失败时视口为 `.zero`、锚点被 LazyVStack 回收后退回 `.zero`，曾让按钮完全反转。
@Test func scrollBottomUnmeasuredKeepsCurrentState() {
    #expect(ScrollBottomDetector.followsBottom(anchor: anchor(at: 763), viewport: .zero, current: true))
    #expect(!ScrollBottomDetector.followsBottom(anchor: anchor(at: 763), viewport: .zero, current: false))
    #expect(!ScrollBottomDetector.followsBottom(anchor: .zero, viewport: viewport, current: false))
    #expect(ScrollBottomDetector.followsBottom(anchor: .zero, viewport: viewport, current: true))
    #expect(ScrollBottomDetector.followsBottom(anchor: anchor(at: 763), viewport: viewport, current: false))
    #expect(!ScrollBottomDetector.followsBottom(anchor: anchor(at: 5876), viewport: viewport, current: true))
}
