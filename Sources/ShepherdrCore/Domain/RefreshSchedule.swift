import Foundation

/// When each machine is asked for a snapshot, and when Herdr's catalog of machines is read again.
/// While Shepherdr is on screen, every machine answers at the user's interval. Off screen (the
/// window hidden or minimized, the displays asleep, the screen locked) this Mac keeps that pace,
/// so its agents still notify on time, and other machines answer every 30 seconds: each of their
/// refreshes is a round trip over SSH. The catalog rarely changes: it is read about once a minute,
/// and again on the next refresh after it failed.
public struct RefreshSchedule: Equatable, Sendable {
    public static let offScreenInterval: TimeInterval = 30
    public static let catalogInterval: TimeInterval = 60

    /// When each machine was last asked, by machine ID.
    public private(set) var asked: [String: Date] = [:]
    public private(set) var catalogRead: Date?
    /// The last catalog read failed, so the next refresh reads it again.
    public var catalogFailed = false

    public init() {}

    /// What a regular refresh asks now: the enabled machines that are due, by ID, and whether it
    /// reads the catalog. `interval` is the user's refresh interval.
    public func due(_ machines: [Machine], interval: TimeInterval, onScreen: Bool,
                    now: Date = Date()) -> (machines: Set<String>, catalog: Bool) {
        var due = Set<String>()
        for machine in machines where machine.isEnabled {
            let every = onScreen || machine.isLocal ? interval : max(interval, Self.offScreenInterval)
            if Self.isDue(since: asked[machine.id], every: every, now: now) { due.insert(machine.id) }
        }
        return (due, catalogFailed || Self.isDue(since: catalogRead, every: Self.catalogInterval, now: now))
    }

    public mutating func didAsk(_ ids: some Sequence<String>, catalog: Bool, at now: Date = Date()) {
        for id in ids { asked[id] = now }
        if catalog { catalogRead = now }
    }

    /// Ticks come a refresh's length after the interval, or a hair before it: a fifth of the
    /// interval, up to a second, still counts. A clock set back counts as time gone by.
    private static func isDue(since last: Date?, every: TimeInterval, now: Date) -> Bool {
        guard let last, now >= last else { return true }
        return now.timeIntervalSince(last) >= every - min(1, every / 5)
    }
}
