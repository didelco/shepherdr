import Foundation

/// Whether this Mac can start an agent, or hand one work, while nobody may be watching. A Mac
/// asleep on battery keeps waking for a few seconds at a time with its screen off, a dark wake:
/// Shepherdr's timers run then, but DNS doesn't, and the Mac sleeps again before an agent is
/// done starting. An agent started then misses what it loads only at launch, such as Claude
/// Code's connectors from claude.ai, for the rest of its life.
///
/// So agents start, and get prompts, only while this Mac is fully awake: macOS reports the
/// graphics capability (it has none in a dark wake), and it hasn't said it is going to sleep.
/// For an agent whose service Shepherdr knows, the network must have a path and that service's
/// host must resolve on it. Sleeping and losing the network are disruptions: an agent that
/// started across one is started again before its first prompt (see `AgentStartup`).
public struct Readiness: Equatable, Sendable {
    /// What keeps an agent from starting now.
    public enum Blocker: Equatable, Sendable {
        /// macOS said it is going to sleep, and hasn't said it woke.
        case sleeping
        /// Awake with the screen off and no graphics: a dark wake, a few seconds long.
        case darkWake
        /// The network has no path.
        case offline
        /// The host hasn't been looked up on this network since it last changed.
        case lookingUp(String)
        /// The host didn't resolve: DNS doesn't work yet.
        case unresolved(String)

        /// What the run waits for, after "waits for".
        public var summary: String {
            switch self {
            case .sleeping, .darkWake: "this Mac to wake up"
            case .offline, .lookingUp: "the network"
            case .unresolved(let host): "the network: \(host) doesn't resolve"
            }
        }
    }

    public struct Lookup: Equatable, Sendable {
        public var resolved: Bool
        public var at: Date
    }

    /// A host that resolved counts as resolving for this long, while nothing changed.
    public static let lookupLifetime: TimeInterval = 60
    /// A host that didn't resolve is looked up again after this long.
    public static let retryInterval: TimeInterval = 10
    /// "Going to sleep" with no "woke" since counts for this long while macOS reports graphics:
    /// sleep comes within seconds of it, so a Mac with its screen that long after missed the wake.
    public static let sleepGrace: TimeInterval = 60

    /// When macOS last said it is going to sleep, until it says it woke.
    public private(set) var sleptAt: Date?
    /// Whether the network has a path; nil until it first says.
    public private(set) var online: Bool?
    /// The last lookup of each host since the Mac woke or the network changed.
    public private(set) var lookups: [String: Lookup] = [:]
    /// When this Mac last went to sleep or lost the network.
    public private(set) var lastDisruption: Date?
    /// When the Mac last slept, woke or changed networks: lookups asked before don't count.
    public private(set) var lastChange = Date.distantPast

    public init() {}

    /// The host an agent kind reaches first, when Shepherdr knows it.
    public static func host(forAgent kind: String) -> String? {
        switch kind {
        case "claude": "api.anthropic.com"
        case "codex": "api.openai.com"
        case "gemini": "generativelanguage.googleapis.com"
        default: nil
        }
    }

    public mutating func willSleep(at now: Date) {
        sleptAt = now
        lastDisruption = now
        reset(at: now)
    }

    /// macOS said it woke, or that the screens did.
    public mutating func didWake(at now: Date) {
        sleptAt = nil
        reset(at: now)
    }

    public mutating func pathChanged(online: Bool, at now: Date) {
        if !online, self.online != false { lastDisruption = now }
        self.online = online
        reset(at: now)
    }

    /// The answer to a lookup asked at `asked`, ignored when the Mac slept, woke or changed networks since.
    public mutating func looked(up host: String, resolved: Bool, asked: Date, at now: Date) {
        guard asked >= lastChange else { return }
        lookups[host] = Lookup(resolved: resolved, at: now)
    }

    /// What keeps an agent that reaches `host` from starting now, nil when nothing does. With no
    /// host, only sleep counts. `hasGraphics` is macOS's answer, nil where Shepherdr can't read it.
    public func blocker(host: String?, hasGraphics: Bool?, at now: Date) -> Blocker? {
        if hasGraphics == false { return .darkWake }
        if let sleptAt, hasGraphics == nil || now < sleptAt || now.timeIntervalSince(sleptAt) < Self.sleepGrace { return .sleeping }
        guard let host else { return nil }
        guard online == true else { return .offline }
        guard let lookup = lookups[host] else { return .lookingUp(host) }
        if !lookup.resolved { return .unresolved(host) }
        return Self.isFresh(lookup, for: Self.lookupLifetime, at: now) ? nil : .lookingUp(host)
    }

    /// Whether to look `host` up now: never looked up on this network, or the answer is old.
    public func needsLookup(_ host: String, at now: Date) -> Bool {
        guard let lookup = lookups[host] else { return true }
        return !Self.isFresh(lookup, for: lookup.resolved ? Self.lookupLifetime : Self.retryInterval, at: now)
    }

    /// Whether this Mac went to sleep or lost the network since `date`.
    public func disrupted(since date: Date) -> Bool {
        lastDisruption.map { $0 >= date } ?? false
    }

    private mutating func reset(at now: Date) {
        lookups = [:]
        lastChange = now
    }

    /// A clock set back makes an answer old.
    private static func isFresh(_ lookup: Lookup, for lifetime: TimeInterval, at now: Date) -> Bool {
        now >= lookup.at && now.timeIntervalSince(lookup.at) < lifetime
    }
}

/// An agent Shepherdr started with nobody necessarily watching, such as Compass's, until its first
/// prompt. A sleep or a lost network while it started can leave it without what it loads only at
/// launch, so before that prompt it is started again, which loses nothing: it has no conversation
/// yet. Never once you typed to it, and at most `maxRestarts` times.
public struct AgentStartup: Equatable, Sendable {
    /// What an agent reads at launch, such as Claude Code's connectors, may still be loading this
    /// long after Herdr reports it ready: its first prompt waits that long, so a sleep then counts.
    public static let settling: TimeInterval = 15
    public static let maxRestarts = 2

    public enum Decision: Equatable, Sendable {
        /// Too soon after it started: ask again later.
        case wait
        /// It started across a sleep or a lost network: start it again.
        case restart
        /// Send its first prompt.
        case prompt
    }

    public let terminalID: String
    /// When Shepherdr began getting it going, before closing old panes and making its workspace.
    public let began: Date
    /// When Herdr reported it started.
    public let ready: Date
    /// How many times it was started again before this start.
    public let restarts: Int

    public init(terminalID: String, began: Date, ready: Date, restarts: Int = 0) {
        self.terminalID = terminalID
        self.began = began
        self.ready = ready
        self.restarts = restarts
    }

    /// What to do before its first prompt. `disrupted` tells whether this Mac went to sleep or lost
    /// the network since `began`, and `typed` whether you typed to the agent since then.
    public func decision(disrupted: Bool, typed: Bool, at now: Date) -> Decision {
        if now >= ready, now.timeIntervalSince(ready) < Self.settling { return .wait }
        guard disrupted, !typed, restarts < Self.maxRestarts else { return .prompt }
        return .restart
    }
}
