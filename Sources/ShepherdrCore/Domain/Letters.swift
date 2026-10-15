import Foundation

/// What an agent asked of Shepherdr through `shepherdr` on its machine: a letter it left in
/// `~/.shepherdr/outbox` there. Letters are data from another machine, so everything in them is
/// checked before Shepherdr acts on it, and nothing in them ever runs.
public struct Letter: Equatable, Sendable {
    /// The pane that wrote it, on the machine it came from. Nil when written outside Herdr.
    public struct Sender: Equatable, Sendable {
        public let paneID: String
        public let terminalID: String
    }

    public enum ChildMachine: Equatable, Sendable {
        /// The machine the letter came from.
        case here
        /// A machine its Herdr reaches, by Herdr profile: only the Mac's own letters name one.
        case profile(String)
    }

    /// A session `shepherdr spawn` started.
    public struct Spawned: Equatable, Sendable {
        public let machine: ChildMachine
        public let paneID: String
        public let terminalID: String
        public let name: String
        public let agent: String?
        public let wait: Bool
        /// The prompt is in the letter's message, for Shepherdr to send once the agent is ready.
        public let promptPending: Bool
    }

    /// A session on a machine only Shepherdr reaches, for the user to approve.
    public struct SpawnRequest: Equatable, Sendable {
        public let machine: String
        public let directory: String
        public let agent: String?
        public let name: String?
        public let wait: Bool
    }

    public enum Content: Equatable, Sendable {
        case spawned(Spawned)
        case spawnRequest(SpawnRequest)
        /// Work handed back, to a named session or to the sessions waiting for the sender.
        case handoff(to: String?)
        case wait([String])
        /// Stop waiting for these sessions; for all when empty.
        case resume([String])
        case pin(URL, title: String?)
        case open(URL)
        case notify
    }

    public let id: String
    public let sender: Sender?
    public let content: Content
    /// The message the agent wrote, if any.
    public let message: String?
    /// Attachments, as paths inside the letter such as `files/REPORT.md`.
    public let files: [String]

    /// The letter format this Shepherdr reads.
    public static let supportedProtocol = 1
    public static let maximumMessage = 262_144
    public static let maximumFiles = 20

    /// Letter IDs are a UTC time and a random suffix: `20261015T101502Z-7f3a9c`.
    public static func isValidID(_ id: String) -> Bool {
        id.range(of: #"^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{6}$"#, options: .regularExpression) != nil
    }

    /// An attachment's path inside a letter: `files/` and a name the CLI made safe.
    public static func isValidFile(_ path: String) -> Bool {
        path.range(of: #"^files/[A-Za-z0-9_-][A-Za-z0-9._-]{0,159}$"#, options: .regularExpression) != nil
    }
}

public struct LetterError: Error, Equatable, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

extension Letter {
    /// Reads a collected letter: its `letter.json` and the files that came with it.
    public init(id: String, contents: [String: Data]) throws {
        guard Self.isValidID(id) else { throw LetterError("Not a letter ID: \(id.prefix(40))") }
        guard let json = contents["letter.json"] else { throw LetterError("The letter has no letter.json.") }
        let dto: LetterDTO
        do { dto = try JSONDecoder().decode(LetterDTO.self, from: json) }
        catch { throw LetterError("The letter's JSON couldn't be read.") }
        guard dto.protocol <= Self.supportedProtocol else {
            throw LetterError("The letter uses a newer format (\(dto.protocol)). Update Shepherdr to read it.")
        }
        guard dto.id == id else { throw LetterError("The letter's ID doesn't match its folder.") }
        self.id = id

        if let pane = dto.from?.pane, let terminal = dto.from?.terminal {
            guard Self.isPaneID(pane), Self.isTerminalID(terminal) else { throw LetterError("The sender's pane isn't valid.") }
            sender = Sender(paneID: pane, terminalID: terminal)
        } else {
            sender = nil
        }

        if let data = contents["message.md"] {
            guard data.count <= Self.maximumMessage else { throw LetterError("The message is over 256 KB.") }
            message = String(decoding: data, as: UTF8.self)
        } else {
            message = nil
        }

        let listed = dto.files ?? []
        guard listed.count <= Self.maximumFiles, listed.allSatisfy(Self.isValidFile), Set(listed).count == listed.count else {
            throw LetterError("The letter's attachments aren't valid.")
        }
        guard listed.allSatisfy({ contents[$0] != nil }) else { throw LetterError("An attachment is missing from the letter.") }
        files = listed

        switch dto.kind {
        case "spawned":
            guard let child = dto.child, Self.isPaneID(child.pane), Self.isTerminalID(child.terminal) else {
                throw LetterError("The new session's pane isn't valid.")
            }
            let machine: ChildMachine
            if child.machine == "here" {
                machine = .here
            } else if child.machine.hasPrefix("profile:"), Self.isProfileID(String(child.machine.dropFirst(8))) {
                machine = .profile(String(child.machine.dropFirst(8)))
            } else {
                throw LetterError("The new session's machine isn't valid.")
            }
            let pending = dto.prompt == "pending"
            guard !pending || message != nil else { throw LetterError("The pending prompt is missing.") }
            content = .spawned(Spawned(machine: machine, paneID: child.pane, terminalID: child.terminal,
                                       name: try Self.text(dto.name, "name", limit: 64) ?? "",
                                       agent: try Self.agentKind(dto.agent), wait: dto.wait ?? true, promptPending: pending))
        case "spawn-request":
            guard let machine = try Self.text(dto.machine, "machine", limit: 200) else { throw LetterError("The request names no machine.") }
            let name = try Self.text(dto.name, "name", limit: 32)
            guard name.map(Self.isAgentName) ?? true else { throw LetterError("The requested name isn't valid.") }
            content = .spawnRequest(SpawnRequest(machine: machine, directory: try Self.text(dto.cwd, "folder", limit: 1_024) ?? "~",
                                                 agent: try Self.agentKind(dto.agent), name: name, wait: dto.wait ?? true))
        case "handoff":
            guard message != nil || !files.isEmpty else { throw LetterError("The handoff is empty.") }
            content = .handoff(to: try Self.text(dto.to, "recipient", limit: 200))
        case "wait":
            let names = try (dto.sessions ?? []).map { try Self.text($0, "session", limit: 200) ?? "" }.filter { !$0.isEmpty }
            guard !names.isEmpty else { throw LetterError("The letter names no session to wait for.") }
            content = .wait(names)
        case "resume":
            content = .resume(try (dto.sessions ?? []).map { try Self.text($0, "session", limit: 200) ?? "" }.filter { !$0.isEmpty })
        case "pin":
            content = .pin(try Self.link(dto.url), title: try Self.text(dto.title, "title", limit: 200))
        case "open":
            content = .open(try Self.link(dto.url))
        case "notify":
            guard message?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { throw LetterError("The notification is empty.") }
            content = .notify
        default:
            throw LetterError("Unknown kind of letter: \(dto.kind.prefix(40)).")
        }
    }

    /// The first line of its message, for a short summary.
    public var headline: String? {
        guard let line = message?.split(whereSeparator: \.isNewline).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        let text = line.trimmingCharacters(in: .whitespaces)
        return text.count > 160 ? String(text.prefix(159)) + "…" : text
    }

    static func isPaneID(_ value: String) -> Bool { value.range(of: #"^[A-Za-z0-9:_-]{1,64}$"#, options: .regularExpression) != nil }
    static func isTerminalID(_ value: String) -> Bool { value.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil }
    static func isProfileID(_ value: String) -> Bool { value.range(of: #"^[A-Za-z0-9._-]{1,128}$"#, options: .regularExpression) != nil }
    public static func isAgentName(_ value: String) -> Bool { value.range(of: #"^[a-z][a-z0-9_-]{0,31}$"#, options: .regularExpression) != nil }

    private static func agentKind(_ value: String?) throws -> String? {
        guard let value else { return nil }
        guard value.range(of: #"^[a-z0-9_-]{1,32}$"#, options: .regularExpression) != nil else { throw LetterError("The agent kind isn't valid.") }
        return value
    }

    /// Short text from the letter: no control characters, bounded, nil when absent or blank.
    private static func text(_ value: String?, _ what: String, limit: Int) throws -> String? {
        guard let value else { return nil }
        guard value.count <= limit, value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw LetterError("The letter's \(what) isn't valid.")
        }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func link(_ value: String?) throws -> URL {
        guard let value, value.count <= 2_048, let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host()?.isEmpty == false else {
            throw LetterError("The letter's link isn't an http or https address.")
        }
        return url
    }
}

/// `letter.json` as `shepherdr` writes it. Every field but the envelope is optional here, and
/// checked by kind above.
private struct LetterDTO: Decodable {
    struct From: Decodable { let pane: String?; let terminal: String? }
    struct Child: Decodable { let machine: String; let pane: String; let terminal: String; let workspace: String? }
    let `protocol`: Int
    let id: String
    let kind: String
    let from: From?
    let child: Child?
    let name: String?
    let agent: String?
    let wait: Bool?
    let prompt: String?
    let machine: String?
    let cwd: String?
    let to: String?
    let files: [String]?
    let sessions: [String]?
    let url: String?
    let title: String?
}
