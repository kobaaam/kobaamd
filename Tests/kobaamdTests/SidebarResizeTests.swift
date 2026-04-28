import Foundation
import Testing
@testable import kobaamd

@Suite("SidebarResizeLogic")
struct SidebarResizeTests {

    // resizeHandle の計算式: newRatio = startRatio - translationHeight / availableHeight
    private func computeRatio(startRatio: Double, translationHeight: Double, availableHeight: Double) -> Double {
        let newRatio = startRatio - translationHeight / availableHeight
        return min(0.9, max(0.1, newRatio))
    }

    @Test("ドラッグ開始時の ratio が基準として使われること")
    func startRatioIsBaseline() {
        let result = computeRatio(startRatio: 0.35, translationHeight: 0, availableHeight: 600)
        #expect(result == 0.35)
    }

    @Test("下方向ドラッグでアウトラインが縮小すること")
    func dragDownReducesOutlineRatio() {
        // translationHeight > 0 はハンドルを下に引く → アウトラインが縮小
        let result = computeRatio(startRatio: 0.5, translationHeight: 60, availableHeight: 600)
        #expect(result < 0.5)
    }

    @Test("上方向ドラッグでアウトラインが拡大すること")
    func dragUpIncreasesOutlineRatio() {
        // translationHeight < 0 はハンドルを上に引く → アウトラインが拡大
        let result = computeRatio(startRatio: 0.5, translationHeight: -60, availableHeight: 600)
        #expect(result > 0.5)
    }

    @Test("ratio は 0.1 以下にならないこと（最小値クランプ）")
    func ratioIsClampedAtMin() {
        let result = computeRatio(startRatio: 0.5, translationHeight: 1000, availableHeight: 600)
        #expect(result == 0.1)
    }

    @Test("ratio は 0.9 以上にならないこと（最大値クランプ）")
    func ratioIsClampedAtMax() {
        let result = computeRatio(startRatio: 0.5, translationHeight: -1000, availableHeight: 600)
        #expect(result == 0.9)
    }
}
