import Foundation

/// Which browser pages to let go of: a loaded page keeps its scripts, timers and connections
/// running, and its web process's memory, even while nobody looks at it. A page not on screen for
/// a while is unloaded, and beyond a number of loaded pages, the ones seen least recently are too.
/// An unloaded tab keeps its address and title, and loads again when shown.
public enum PageUnloading {
    /// A browser tab as the policy sees it.
    public struct Page: Equatable, Sendable {
        public let id: UUID
        /// It holds a page: not a tab waiting to load, nor an empty one.
        public let isLoaded: Bool
        /// On screen now.
        public let isShown: Bool
        /// Pages that must stay, such as Compass's, or one still loading, never go.
        public let canUnload: Bool
        /// When it was last on screen, or opened if it never was.
        public let lastShown: Date

        public init(id: UUID, isLoaded: Bool, isShown: Bool, canUnload: Bool, lastShown: Date) {
            self.id = id
            self.isLoaded = isLoaded
            self.isShown = isShown
            self.canUnload = canUnload
            self.lastShown = lastShown
        }
    }

    /// How long a page stays loaded out of sight.
    public static let idleTime: TimeInterval = 10 * 60
    /// How many loaded pages there may be, the ones on screen included, before the least recently
    /// seen go early.
    public static let limit = 12

    /// The pages to unload now, least recently seen first.
    public static func pages(toUnload pages: [Page], now: Date = Date(), idleTime: TimeInterval = idleTime,
                             limit: Int = limit) -> [UUID] {
        let candidates = pages.filter { $0.isLoaded && !$0.isShown && $0.canUnload }.sorted { $0.lastShown < $1.lastShown }
        var unloading = candidates.filter { now.timeIntervalSince($0.lastShown) >= idleTime }
        var loaded = pages.filter(\.isLoaded).count - unloading.count
        for page in candidates where loaded > limit && !unloading.contains(page) {
            unloading.append(page)
            loaded -= 1
        }
        return unloading.sorted { $0.lastShown < $1.lastShown }.map(\.id)
    }
}
