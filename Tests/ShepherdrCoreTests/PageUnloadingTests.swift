import Foundation
import Testing
@testable import ShepherdrCore

struct PageUnloadingTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func page(_ minutesAgo: Double, loaded: Bool = true, shown: Bool = false, canUnload: Bool = true) -> PageUnloading.Page {
        PageUnloading.Page(id: UUID(), isLoaded: loaded, isShown: shown, canUnload: canUnload,
                           lastShown: now.addingTimeInterval(-minutesAgo * 60))
    }

    @Test func pagesOutOfSightForAWhileGo() {
        let stale = page(11), recent = page(9), onScreen = page(60, shown: true), pinned = page(60, canUnload: false),
            waiting = page(60, loaded: false)
        let unloading = PageUnloading.pages(toUnload: [recent, onScreen, stale, pinned, waiting], now: now)
        #expect(unloading == [stale.id])
    }

    @Test func beyondTheLimitTheLeastRecentlySeenGoFirst() {
        // Five loaded pages, two of them on screen, and room for three.
        let shown = [page(30, shown: true), page(40, shown: true)]
        let oldest = page(5), older = page(3), newest = page(1)
        let unloading = PageUnloading.pages(toUnload: shown + [newest, oldest, older], now: now, limit: 3)
        #expect(unloading == [oldest.id, older.id])
        // Pages that must stay don't make room, however many there are.
        let kept = (0..<5).map { _ in page(2, canUnload: false) }
        #expect(PageUnloading.pages(toUnload: kept + [page(1)], now: now, limit: 3).count == 1)
    }

    @Test func idlePagesCountTowardTheLimitOnlyOnce() {
        let idle = page(20), fresh = [page(1), page(2)]
        let unloading = PageUnloading.pages(toUnload: [idle] + fresh, now: now, limit: 2)
        #expect(unloading == [idle.id])
    }
}
