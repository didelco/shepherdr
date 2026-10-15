import Foundation

/// The sessions a terminal can name, so a click goes straight to one: a pane ID such as `w5:p1`, a
/// terminal ID such as `term_65de5e979051a2`, or a session's name, as `shepherdr` prints them
/// ("Started fix-login (claude) on buildbox") and agents mention them. `name@machine` picks a machine.
public struct SessionDirectory: Sendable {
    /// A pane Herdr reports, with the names the queue shows for it.
    public struct Entry: Equatable, Sendable {
        public let id: Agent.ID
        public let paneID: String
        public let workspaceID: String
        /// Its agent's name, when Herdr gave it one, and its workspace's. Names too short or too
        /// generic to tell apart from ordinary text are left out.
        public let names: [String]

        public init(id: Agent.ID, paneID: String, workspaceID: String, names: [String]) {
            self.id = id
            self.paneID = paneID
            self.workspaceID = workspaceID
            var kept: [String] = []
            for name in names where SessionDirectory.isDistinctive(name) && !kept.contains(name) { kept.append(name) }
            self.names = kept
        }

        /// An agent without a name of its own goes by its program's, such as `Claude Code`, which
        /// other sessions share: only its workspace names it then.
        public init(agent: Agent) {
            let program = agent.program
            let generic = [program.label, program.name, agent.kind].contains {
                $0.caseInsensitiveCompare(agent.name) == .orderedSame
            }
            self.init(id: agent.id, paneID: agent.paneID, workspaceID: agent.workspaceID,
                      names: (generic ? [] : [agent.name]) + [agent.workspaceName])
        }

        /// A shell, which goes by its workspace's name.
        public init(pane: TerminalPane, machineID: String) {
            self.init(id: .init(machineID: machineID, terminalID: pane.terminalID), paneID: pane.paneID,
                      workspaceID: pane.workspaceID, names: [pane.workspaceName])
        }
    }

    public let entries: [Entry]
    public let machines: [Machine]

    public init(entries: [Entry], machines: [Machine]) {
        self.entries = entries
        self.machines = machines
    }

    /// The session other than `own` that the text at a column names, when exactly one fits. A pane
    /// ID belongs to a Herdr server: it means `own`'s machine, unless `@machine` or a `--machine`
    /// option on the same line names another. A name without `@machine` means a session on `own`'s
    /// machine first, and nothing when it is `own`'s or several sessions elsewhere share it.
    public func session(in row: [Character], column: Int, from own: Agent.ID) -> Agent.ID? {
        guard row.indices.contains(column), !row[column].isWhitespace else { return nil }
        if let identifier = identifier(in: row, at: column) {
            return resolve(identifier, in: row, from: own)
        }
        guard let mention = mention(in: row, at: column) else { return nil }
        let owners = entries.filter { $0.names.contains(mention.name) }
        let found: [Entry]
        switch mention.qualifier {
        case .machine(let machine):
            found = owners.filter { $0.id.machineID == machine.id }
        case .none:
            // Its own name is about itself, even where another session has the same name.
            if owners.contains(where: { $0.id == own }) { return nil }
            let here = owners.filter { $0.id.machineID == own.machineID }
            found = here.isEmpty ? owners : here
        }
        return Self.one(of: found, besides: own)
    }

    // MARK: Pane and terminal IDs

    private struct Identifier {
        let text: String
        let isPane: Bool
        let qualifier: Qualifier
    }

    private enum Qualifier {
        case none
        case machine(Machine)
    }

    /// The pane or terminal ID written across a column, with the machine named right after it.
    private func identifier(in row: [Character], at column: Int) -> Identifier? {
        func isIDCharacter(_ character: Character) -> Bool {
            character.isASCII && (character.isLetter || character.isNumber || character == "_" || character == ":")
        }
        guard isIDCharacter(row[column]) else { return nil }
        var start = column, end = column + 1
        while start > 0, isIDCharacter(row[start - 1]) { start -= 1 }
        while end < row.count, isIDCharacter(row[end]) { end += 1 }
        // A colon after an ID ends a phrase: "pane w5:p1: done".
        while end > start, row[end - 1] == ":" { end -= 1 }
        guard column < end, start == 0 || !Self.joins(row[start - 1]) else { return nil }
        let text = String(row[start..<end])
        let isPane = text.range(of: #"^w[0-9]+:p[0-9]+$"#, options: .regularExpression) != nil
        guard isPane || text.range(of: #"^term_[A-Za-z0-9]+$"#, options: .regularExpression) != nil,
              let qualifier = qualifier(in: row, after: end) else { return nil }
        return Identifier(text: text, isPane: isPane, qualifier: qualifier.qualifier)
    }

    private func resolve(_ identifier: Identifier, in row: [Character], from own: Agent.ID) -> Agent.ID? {
        let matching = entries.filter { identifier.isPane ? $0.paneID == identifier.text : $0.id.terminalID == identifier.text }
        var machine: Machine?
        if case .machine(let named) = identifier.qualifier { machine = named }
        if machine == nil, identifier.isPane, let option = Self.machineOption(in: row) {
            // Only this Mac's Herdr has the profiles Shepherdr knows machines by.
            guard own.machineID == Machine.local.id else { return nil }
            machine = machines.first { $0.profileID == option || $0.name.caseInsensitiveCompare(option) == .orderedSame }
            guard machine != nil else { return nil }
        }
        if let machine { return Self.one(of: matching.filter { $0.id.machineID == machine.id }, besides: own) }
        let here = matching.filter { $0.id.machineID == own.machineID }
        return Self.one(of: here.isEmpty ? matching : here, besides: own)
    }

    /// The machine a `--machine` option names, as in `herdr --machine buildbox pane list`.
    private static func machineOption(in row: [Character]) -> String? {
        let line = String(row)
        guard let option = line.range(of: "--machine") else { return nil }
        var rest = line[option.upperBound...]
        if rest.first == "=" { rest = rest.dropFirst() }
        rest = rest.drop { $0 == " " || $0 == "\"" || $0 == "'" }
        let value = rest.prefix { !$0.isWhitespace && $0 != "\"" && $0 != "'" }
        return value.isEmpty ? nil : String(value)
    }

    // MARK: Names

    private struct Mention {
        let name: String
        let qualifier: Qualifier
    }

    /// The longest session name written across a column, or across the `@machine` after it, as a
    /// word or phrase of its own: never part of a path, a file name or a longer name.
    private func mention(in row: [Character], at column: Int) -> Mention? {
        let longestMachine = machines.map(\.name.count).max() ?? 0
        var best: (mention: Mention, length: Int)?
        for name in Set(entries.flatMap(\.names)) {
            let characters = Array(name)
            guard best.map({ characters.count > $0.length }) ?? true else { continue }
            let earliest = max(0, column - characters.count - longestMachine - 1)
            for start in earliest...column where start + characters.count <= row.count {
                guard row[start] == characters[0], Array(row[start..<(start + characters.count)]) == characters,
                      start == 0 || !Self.joins(row[start - 1]),
                      let qualifier = qualifier(in: row, after: start + characters.count), column < qualifier.end else { continue }
                best = (Mention(name: name, qualifier: qualifier.qualifier), characters.count)
                break
            }
        }
        return best?.mention
    }

    /// What follows a name or ID ending at an index: nothing that continues it, or `@machine`.
    /// Nil when the text goes on, as `api` does in `api.ts`, `api-gateway` or `api@example.com`.
    private func qualifier(in row: [Character], after index: Int) -> (qualifier: Qualifier, end: Int)? {
        guard index < row.count, row[index] == "@" else { return Self.ends(row, at: index) ? (.none, index) : nil }
        // The longest machine name that fits, for names that start like another's.
        for machine in machines.sorted(by: { $0.name.count > $1.name.count }) where !machine.name.isEmpty {
            let stop = index + 1 + machine.name.count
            guard stop <= row.count,
                  String(row[(index + 1)..<stop]).caseInsensitiveCompare(machine.name) == .orderedSame,
                  Self.ends(row, at: stop) else { continue }
            return (.machine(machine), stop)
        }
        return nil
    }

    /// Whether text ends at an index: the line does, or what follows can't continue a word, a path
    /// or a file name. Sentence punctuation ends it when nothing joins it: "Started fix-login."
    private static func ends(_ row: [Character], at index: Int) -> Bool {
        guard index < row.count, joins(row[index]) else { return true }
        return ".:".contains(row[index]) && (index + 1 == row.count || !joins(row[index + 1]))
    }

    /// Characters that make a name part of something longer: a word, a path, a file name, an address.
    private static func joins(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || "_-./\\~@:#$%&=+*^".contains(character)
    }

    /// Names a session goes by that can't be taken for ordinary text or an ID: three characters or
    /// more, with a letter, and not a workspace ID such as `w3`, which Herdr shows for unnamed ones.
    static func isDistinctive(_ name: String) -> Bool {
        name.count >= 3 && name.contains(where: \.isLetter) && name.trimmingCharacters(in: .whitespaces) == name
            && name.range(of: #"^w[0-9]+$"#, options: .regularExpression) == nil
    }

    /// The one session among these, unless it is `own`. Panes of one workspace share its name: any of
    /// them leads there, so the first one does.
    private static func one(of entries: [Entry], besides own: Agent.ID) -> Agent.ID? {
        guard let first = entries.first, !entries.contains(where: { $0.id == own }),
              entries.allSatisfy({ $0.id.machineID == first.id.machineID && $0.workspaceID == first.workspaceID }) else { return nil }
        return first.id
    }
}

/// A click on a session named in a terminal, as a link only Shepherdr opens: never a browser.
public enum SessionLink {
    public static let scheme = "shepherdr-session"

    public static func url(for id: Agent.ID) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.path = "open"
        components.queryItems = [URLQueryItem(name: "machine", value: id.machineID),
                                 URLQueryItem(name: "terminal", value: id.terminalID)]
        return components.url!
    }

    /// The session a link opens, if it is one of these.
    public static func session(in url: URL) -> Agent.ID? {
        guard url.scheme == scheme, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let machine = items.first(where: { $0.name == "machine" })?.value, !machine.isEmpty,
              let terminal = items.first(where: { $0.name == "terminal" })?.value, !terminal.isEmpty else { return nil }
        return Agent.ID(machineID: machine, terminalID: terminal)
    }
}
