import Foundation

/// A time of day, `09:30`, as Compass's settings and its page's strip write it.
public struct ClockTime: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    /// Minutes since midnight.
    public let minutes: Int

    public init(hour: Int, minute: Int = 0) {
        minutes = max(0, min(23 * 60 + 59, hour * 60 + minute))
    }

    /// `9:30` or `09:30`.
    public init?(_ text: String) {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]), (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        minutes = hour * 60 + minute
    }

    public var hour: Int { minutes / 60 }
    public var minute: Int { minutes % 60 }
    public var description: String { String(format: "%02d:%02d", hour, minute) }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.minutes < rhs.minutes }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let time = ClockTime(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a time of day: \(text)"))
        }
        self = time
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

public enum Weekday: String, Codable, CaseIterable, Sendable {
    case mon, tue, wed, thu, fri, sat, sun

    /// From `Calendar`'s weekday, where 1 is Sunday.
    public init(calendarWeekday: Int) {
        self = Self.allCases[(calendarWeekday + 5) % 7]
    }

    public static let workdays: [Weekday] = [.mon, .tue, .wed, .thu, .fri]
}

/// When Compass runs on its own: never, once a day, or every so often within hours of the day.
/// A run the Mac missed, asleep or with Shepherdr closed, happens once when it can, and only
/// on the same day; the runs it missed in between are not made up one by one.
public struct CompassSchedule: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable { case manual, daily, interval }

    public var kind: Kind
    /// The time of a daily run.
    public var at: ClockTime
    /// Minutes between runs, from `from` to `to`.
    public var every: Int
    public var from: ClockTime
    public var to: ClockTime
    public var days: [Weekday]

    public static let everyChoices = [15, 30, 60, 120, 180, 240]

    public init(kind: Kind, at: ClockTime = ClockTime(hour: 9), every: Int = 60, from: ClockTime = ClockTime(hour: 9),
                to: ClockTime = ClockTime(hour: 18), days: [Weekday] = Weekday.workdays) {
        self.kind = kind
        self.at = at
        self.every = Self.clamped(every)
        self.from = from
        self.to = to
        self.days = Weekday.allCases.filter(days.contains)
    }

    /// Every hour from 9 to 18, Monday to Friday.
    public static let standard = CompassSchedule(kind: .interval)

    private static func clamped(_ every: Int) -> Int { max(10, min(720, every)) }

    private enum CodingKeys: String, CodingKey { case kind, at, every, from, to, days }

    /// Agents edit this file too: anything missing or unreadable takes its default.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = Self.standard
        self.init(kind: (try? container.decode(Kind.self, forKey: .kind)) ?? standard.kind,
                  at: (try? container.decode(ClockTime.self, forKey: .at)) ?? standard.at,
                  every: (try? container.decode(Int.self, forKey: .every)) ?? standard.every,
                  from: (try? container.decode(ClockTime.self, forKey: .from)) ?? standard.from,
                  to: (try? container.decode(ClockTime.self, forKey: .to)) ?? standard.to,
                  days: (try? container.decode([String].self, forKey: .days))?.compactMap(Weekday.init(rawValue:)) ?? standard.days)
    }

    /// The times it runs on a weekday.
    public func times(on weekday: Weekday) -> [ClockTime] {
        guard days.contains(weekday) else { return [] }
        switch kind {
        case .manual: return []
        case .daily: return [at]
        case .interval:
            var times: [ClockTime] = []
            var minutes = from.minutes
            repeat {
                times.append(ClockTime(hour: 0, minute: minutes))
                minutes += Self.clamped(every)
            } while minutes <= to.minutes && minutes < 24 * 60
            return times
        }
    }

    /// The runs due on the day of `date`, in order.
    public func slots(onDayOf date: Date, calendar: Calendar) -> [Date] {
        let start = calendar.startOfDay(for: date)
        let weekday = Weekday(calendarWeekday: calendar.component(.weekday, from: start))
        return times(on: weekday).compactMap {
            calendar.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: start)
        }
    }

    /// The run to make now, if any: today's latest run time that has passed and that no run
    /// started since. Earlier runs it missed today are covered by this one.
    public func dueSlot(at now: Date, lastRun: Date?, calendar: Calendar) -> Date? {
        guard let slot = slots(onDayOf: now, calendar: calendar).last(where: { $0 <= now }) else { return nil }
        if let lastRun, lastRun >= slot { return nil }
        return slot
    }

    /// The next run after `now`, within the coming week.
    public func nextSlot(after now: Date, calendar: Calendar) -> Date? {
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            if let slot = slots(onDayOf: day, calendar: calendar).first(where: { $0 > now }) { return slot }
        }
        return nil
    }

    /// Whether a run time is the day's last.
    public func isLastSlot(_ slot: Date, calendar: Calendar) -> Bool {
        slots(onDayOf: slot, calendar: calendar).last == slot
    }

    /// `every hour · 09:00–18:00 · mon–fri`.
    public var summary: String {
        let when: String
        switch kind {
        case .manual: return "only when you run it"
        case .daily: when = "daily at \(at)"
        case .interval:
            let interval = every % 60 == 0 ? (every == 60 ? "every hour" : "every \(every / 60) hours") : "every \(every) min"
            when = "\(interval) · \(from)–\(to)"
        }
        return "\(when) · \(Self.describe(days))"
    }

    /// `mon–fri`, `every day`, `mon, wed, fri`.
    static func describe(_ days: [Weekday]) -> String {
        if days.count == 7 { return "every day" }
        if days.isEmpty { return "no days" }
        let indexes = days.compactMap { Weekday.allCases.firstIndex(of: $0) }
        if days.count > 2, indexes.last! - indexes.first! == days.count - 1 {
            return "\(days.first!.rawValue)–\(days.last!.rawValue)"
        }
        return days.map(\.rawValue).joined(separator: ", ")
    }
}

/// What Compass does, in `~/.shepherdr/compass/compass.json`. You change it in Settings, or
/// ask the Compass agent to.
public struct CompassConfig: Codable, Equatable, Sendable {
    public struct Strip: Codable, Equatable, Sendable {
        public var from: ClockTime
        public var to: ClockTime

        public init(from: ClockTime = ClockTime(hour: 8), to: ClockTime = ClockTime(hour: 19)) {
            self.from = from
            self.to = to
        }
    }

    /// Whether it runs on schedule. Off, it still runs when you ask.
    public var enabled: Bool
    /// The Herdr agent kind the Compass session runs.
    public var agent: String
    public var schedule: CompassSchedule
    /// The hours the page's day strip covers.
    public var strip: Strip
    /// A Git remote, ideally private, that keeps a copy of the folder.
    public var backup: String?

    public init(enabled: Bool = true, agent: String = "claude", schedule: CompassSchedule = .standard,
                strip: Strip = Strip(), backup: String? = nil) {
        self.enabled = enabled
        self.agent = NewSessionRequest.agentKinds.contains(agent) ? agent : "claude"
        self.schedule = schedule
        self.strip = strip
        self.backup = backup.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }

    private enum CodingKeys: String, CodingKey { case enabled, agent, schedule, strip, backup }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(enabled: (try? container.decode(Bool.self, forKey: .enabled)) ?? true,
                  agent: (try? container.decode(String.self, forKey: .agent)) ?? "claude",
                  schedule: (try? container.decode(CompassSchedule.self, forKey: .schedule)) ?? .standard,
                  strip: (try? container.decode(Strip.self, forKey: .strip)) ?? Strip(),
                  backup: try? container.decode(String.self, forKey: .backup))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(agent, forKey: .agent)
        try container.encode(schedule, forKey: .schedule)
        try container.encode(strip, forKey: .strip)
        try container.encodeIfPresent(backup, forKey: .backup)
    }
}

/// One time Compass updated its page: on schedule or because you asked.
public struct CompassRun: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// The day's first: a fresh agent builds the page from scratch.
        case first
        case update
        /// The day's last scheduled run.
        case last
    }

    public enum Trigger: String, Codable, Sendable { case scheduled, manual }

    public enum Outcome: String, Codable, Sendable {
        /// Due, waiting for the agent to be free.
        case waiting
        /// Sent to the agent, which is working on it.
        case running
        case updated
        /// The agent finished without changing the page.
        case unchanged
        case failed
    }

    public let id: String
    public let kind: Kind
    public let trigger: Trigger
    /// The scheduled time it covers; nil for a run you asked for.
    public let slot: Date?
    /// When it became due.
    public let created: Date
    /// The day it belongs to, `2026-10-15`.
    public let day: String
    public var sent: Date?
    public var finished: Date?
    public var outcome: Outcome
    /// The copy of the page this run left, relative to the Compass folder.
    public var snapshot: String?
    public var problem: String?

    public init(kind: Kind, trigger: Trigger, slot: Date?, created: Date, day: String) {
        id = "\(day)-\(Int(created.timeIntervalSince1970))"
        self.kind = kind
        self.trigger = trigger
        self.slot = slot
        self.created = created
        self.day = day
        outcome = .waiting
    }

    public var isOpen: Bool { outcome == .waiting || outcome == .running }

    /// What Shepherdr types into the agent to start the run.
    public func prompt(since: Date?, calendar: Calendar, page: String) -> String {
        let what = switch kind {
        case .first: "first of the day"
        case .update: "update"
        case .last: "last of the day"
        }
        let time = Compass.stamp(slot ?? created, calendar: calendar)
        var lines = ["Compass run · \(what) · \(time)\(trigger == .manual ? " · asked for now" : "")"]
        if kind != .first, let since {
            lines.append("Since \(Compass.time(since, calendar: calendar)), when the last run finished.")
        }
        lines.append("Follow prompt.md. Today's page is \(page); context/run.json has the details of this run.")
        return lines.joined(separator: "\n")
    }
}

/// Shepherdr's own notes about Compass, in `state.json`: kept out of the backup, since they
/// name this Mac's terminals.
public struct CompassState: Codable, Equatable, Sendable {
    /// The Compass agent's terminal in this Mac's Herdr.
    public var terminalID: String?
    /// The day the current agent started, so the next day starts a fresh one.
    public var agentDay: String?
    /// Newest last.
    public var runs: [CompassRun] = []
    /// When you last looked at today's page.
    public var lastViewed: Date?
    /// Fingerprints of the files Shepherdr last wrote, to tell them from files you changed.
    public var written: [String: String] = [:]

    public init() {}

    public static let keptRuns = 400

    private enum CodingKeys: String, CodingKey { case terminalID, agentDay, runs, lastViewed, written }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        terminalID = try? container.decode(String.self, forKey: .terminalID)
        agentDay = try? container.decode(String.self, forKey: .agentDay)
        runs = (try? container.decode([CompassRun].self, forKey: .runs)) ?? []
        lastViewed = try? container.decode(Date.self, forKey: .lastViewed)
        written = (try? container.decode([String: String].self, forKey: .written)) ?? [:]
    }
}

/// Dates as Compass's files and prompts write them, in this Mac's time zone.
public enum Compass {
    /// `2026-10-15`.
    public static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// `14:00`.
    public static func time(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// `Thu 2026-10-15 14:00`.
    public static func stamp(_ date: Date, calendar: Calendar) -> String {
        let weekday = Weekday(calendarWeekday: calendar.component(.weekday, from: date)).rawValue.capitalized
        return "\(weekday) \(day(date, calendar: calendar)) \(time(date, calendar: calendar))"
    }

    /// The date a day's name stands for, at its start.
    public static func date(ofDay day: String, calendar: Calendar) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Whether a string names a day the way Compass files do.
    public static func isDay(_ text: String) -> Bool {
        text.count == 10 && text.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil
    }

    /// ISO 8601 with this Mac's offset, as the context files write dates.
    public static func iso(_ date: Date, calendar: Calendar) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// The kind of a run that becomes due now: the day's first while none ran today, the last
    /// when it covers the day's last scheduled time.
    public static func kind(for slot: Date?, at now: Date, runs: [CompassRun], schedule: CompassSchedule,
                            calendar: Calendar) -> CompassRun.Kind {
        let today = day(now, calendar: calendar)
        if !runs.contains(where: { $0.day == today && $0.outcome != .failed }) { return .first }
        if let slot, schedule.isLastSlot(slot, calendar: calendar) { return .last }
        return .update
    }
}

/// What a button or link on the Compass page asks Shepherdr to do, read from its
/// `data-shepherdr` attributes and checked before anything happens. Every action waits for you:
/// a new session opens New Session filled in, text lands in an editor for you to send.
public enum CompassAction: Equatable, Sendable {
    public struct Spawn: Equatable, Sendable {
        public let machine: String?
        public let directory: String?
        public let agent: String?
        public let name: String?
        public let prompt: String?
    }

    /// Opens New Session with a folder, an agent and a prompt, for you to start.
    case spawn(Spawn, item: String?)
    /// Puts text in the Compass agent's prompt editor.
    case ask(String)
    /// Opens a session by its agent or workspace name, `@machine` when needed.
    case session(String)
    /// Puts text in another session's prompt editor and opens it.
    case prompt(session: String, text: String)
    /// Marks a part of the page done, or not done.
    case done(item: String)

    public static let promptLimit = 262_144

    /// Reads an action from the attributes of the element clicked, all strings. Nil when it
    /// isn't one Shepherdr knows or a value doesn't hold up.
    public init?(_ fields: [String: String]) {
        func value(_ key: String, limit: Int = 1_024) -> String? {
            guard let raw = fields[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty, raw.count <= limit,
                  raw.rangeOfCharacter(from: Self.lineControls) == nil else { return nil }
            return raw
        }
        func text(_ key: String) -> String? {
            guard let raw = fields[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
                  raw.utf8.count <= Self.promptLimit, !raw.contains("\u{0}") else { return nil }
            return raw
        }
        /// A field that is there but doesn't hold up refuses the whole action.
        func refuses(_ key: String, limit: Int = 1_024) -> Bool {
            guard let raw = fields[key], !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            return value(key, limit: limit) == nil
        }
        let item = fields["item"].flatMap { Self.isItemID($0) ? $0 : nil }
        switch fields["shepherdr"] {
        case "spawn":
            if refuses("machine", limit: 64) || refuses("cwd") || refuses("kind") || refuses("name") { return nil }
            let agent = value("kind").map { $0.lowercased() }
            if let agent, agent != "shell", !NewSessionRequest.agentKinds.contains(agent) { return nil }
            let name = value("name")
            if let name, !Self.isAgentName(name) { return nil }
            if fields["prompt"] != nil, text("prompt") == nil { return nil }
            self = .spawn(Spawn(machine: value("machine", limit: 64), directory: value("cwd"), agent: agent,
                                name: name, prompt: text("prompt")), item: item)
        case "ask":
            guard let prompt = text("prompt") else { return nil }
            self = .ask(prompt)
        case "session":
            guard let session = value("session", limit: 100) else { return nil }
            self = .session(session)
        case "prompt":
            guard let session = value("session", limit: 100), let prompt = text("prompt") else { return nil }
            self = .prompt(session: session, text: prompt)
        case "done":
            guard let item else { return nil }
            self = .done(item: item)
        default:
            return nil
        }
    }

    /// Characters that never belong in a one-line value: everything but tabs among the controls.
    private static let lineControls = CharacterSet.controlCharacters.subtracting(CharacterSet(charactersIn: "\t"))

    /// A Herdr agent name: a lowercase letter, then up to 31 lowercase letters, digits, `-` or `_`.
    public static func isAgentName(_ name: String) -> Bool {
        name.range(of: #"^[a-z][a-z0-9_-]{0,31}$"#, options: .regularExpression) != nil
    }

    /// The part of the page an action is about: `data-item` on it or an element around it.
    public static func isItemID(_ id: String) -> Bool {
        id.range(of: #"^[A-Za-z0-9._:-]{1,64}$"#, options: .regularExpression) != nil
    }
}

/// What the Compass agent knows of your sessions, in `context/sessions.json`: what the queue
/// shows, never what a terminal printed.
public struct CompassSessions: Encodable, Sendable {
    public struct Session: Encodable, Equatable, Sendable {
        public let priority: Int
        public let name: String
        public let workspace: String
        public let machine: String
        public let state: String
        public let agent: String
        public let title: String
        public let folder: String?
        public let group: String?
        /// Sessions this one waits for, by name.
        public let waitsFor: [String]
        public let pullRequests: [Link]
        public let issues: [Link]
        public let links: [Link]
        public let stale: Bool

        public init(priority: Int, name: String, workspace: String, machine: String, state: String, agent: String,
                    title: String, folder: String?, group: String?, waitsFor: [String], pullRequests: [Link],
                    issues: [Link], links: [Link], stale: Bool) {
            self.priority = priority
            self.name = name
            self.workspace = workspace
            self.machine = machine
            self.state = state
            self.agent = agent
            self.title = title
            self.folder = folder
            self.group = group
            self.waitsFor = waitsFor
            self.pullRequests = pullRequests
            self.issues = issues
            self.links = links
            self.stale = stale
        }

        enum CodingKeys: String, CodingKey {
            case priority, name, workspace, machine, state, agent, title, folder, group, stale
            case waitsFor = "waits_for", pullRequests = "pull_requests", issues, links
        }
    }

    public struct Link: Encodable, Equatable, Sendable {
        public let url: String
        public let title: String?
        /// Pull requests: `passed`, `failed`, `running`; merged or closed ones say so.
        public let checks: String?
        public let state: String?

        public init(url: String, title: String?, checks: String? = nil, state: String? = nil) {
            self.url = url
            self.title = title
            self.checks = checks
            self.state = state
        }
    }

    public struct MachineInfo: Encodable, Equatable, Sendable {
        public let name: String
        public let online: Bool
        public let here: Bool

        public init(name: String, online: Bool, here: Bool) {
            self.name = name
            self.online = online
            self.here = here
        }
    }

    public let generated: String
    public let machines: [MachineInfo]
    public let sessions: [Session]

    public init(generated: String, machines: [MachineInfo], sessions: [Session]) {
        self.generated = generated
        self.machines = machines
        self.sessions = sessions
    }

    /// Pretty JSON with sorted keys, for agents and people to read.
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)) ?? Data("{}".utf8)
    }
}
