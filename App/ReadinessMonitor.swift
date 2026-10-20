import AppKit
import IOKit.pwr_mgt
import Network
import os
import ShepherdrCore

/// Follows sleep, wake and the network for `Readiness`, looks agents' hosts up, and tells its
/// handlers when this Mac may have become ready. Logs what it sees, so a morning's start can be
/// checked afterwards: `/usr/bin/log show --last 1d --predicate 'subsystem == "com.theagilemonkeys.Shepherdr"'`.
@MainActor
final class ReadinessMonitor {
    private(set) var readiness = Readiness()
    private let path = NWPathMonitor()
    private var lookingUp: Set<String> = []
    private var handlers: [() -> Void] = []
    private var observers: [NSObjectProtocol] = []
    /// What the last check for each host found, so the log says each change once.
    private var logged: [String: Readiness.Blocker?] = [:]
    private static let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    static let log = Logger(subsystem: "com.theagilemonkeys.Shepherdr", category: "readiness")

    init() {
        let center = NSWorkspace.shared.notificationCenter
        observe(center, NSWorkspace.willSleepNotification, "going to sleep") { $0.willSleep(at: Date()) }
        observe(center, NSWorkspace.didWakeNotification, "woke") { $0.didWake(at: Date()) }
        observe(center, NSWorkspace.screensDidWakeNotification, "screens woke") { $0.didWake(at: Date()) }
        path.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.readiness.online != online { Self.log.notice("network \(online ? "has a path" : "has no path", privacy: .public)") }
                self.readiness.pathChanged(online: online, at: Date())
                self.changed()
            }
        }
        path.start(queue: .main)
    }

    /// Tells `handler` when this Mac may have become ready: it woke, the network changed or a lookup answered.
    func onChange(_ handler: @escaping () -> Void) { handlers.append(handler) }

    /// What keeps an agent that reaches `host` from starting on this Mac now, nil when nothing
    /// does. Looks `host` up when its answer is missing or old; handlers hear when it comes.
    func blocker(host: String?) -> Readiness.Blocker? {
        let now = Date()
        let graphics = Self.hasGraphics()
        var blocker = readiness.blocker(host: nil, hasGraphics: graphics, at: now)
        if blocker == nil, let host {
            if readiness.online == true, readiness.needsLookup(host, at: now) { lookUp(host) }
            blocker = readiness.blocker(host: host, hasGraphics: graphics, at: now)
        }
        let key = host ?? "-"
        if logged[key] != .some(blocker) {
            logged[key] = .some(blocker)
            Self.log.notice("agents for \(key, privacy: .public) \(blocker.map { "wait: \($0)" } ?? "may start", privacy: .public)")
        }
        return blocker
    }

    /// Returns once an agent that reaches `host` may start, checking every few seconds.
    func untilReady(host: String?) async {
        while blocker(host: host) != nil, !Task.isCancelled { try? await Task.sleep(for: .seconds(5)) }
    }

    /// Whether this Mac went to sleep or lost the network since `date`.
    func disrupted(since date: Date) -> Bool { readiness.disrupted(since: date) }

    /// Whether macOS gives the system graphics, as `pmset` shows: none during a dark wake. Nil where it doesn't say.
    private static func hasGraphics() -> Bool? {
        guard rootDomain != IO_OBJECT_NULL,
              let value = IORegistryEntryCreateCFProperty(rootDomain, "System Capabilities" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber else { return nil }
        return value.uint32Value & UInt32(kIOPMSystemCapabilityGraphics) != 0
    }

    private func lookUp(_ host: String) {
        guard !lookingUp.contains(host) else { return }
        lookingUp.insert(host)
        let asked = Date()
        Task {
            let resolved = await Self.resolves(host)
            lookingUp.remove(host)
            if !resolved { Self.log.notice("\(host, privacy: .public) doesn't resolve") }
            readiness.looked(up: host, resolved: resolved, asked: asked, at: Date())
            changed()
        }
    }

    /// Asks the system resolver, off the main thread, as the agent will.
    private nonisolated static func resolves(_ host: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var hints = addrinfo()
                hints.ai_socktype = SOCK_STREAM
                var found: UnsafeMutablePointer<addrinfo>?
                let status = getaddrinfo(host, "443", &hints, &found)
                if let found { freeaddrinfo(found) }
                continuation.resume(returning: status == 0)
            }
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ what: String,
                         _ change: @escaping @MainActor (inout Readiness) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Self.log.notice("\(what, privacy: .public)")
                change(&self.readiness)
                self.changed()
            }
        }
        observers.append(token)
    }

    private func changed() { handlers.forEach { $0() } }
}
