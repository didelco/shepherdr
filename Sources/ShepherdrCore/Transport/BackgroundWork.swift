import Foundation

/// A command an agent left running after its turn, such as a watcher or a dev server.
public struct BackgroundCommand: Equatable, Sendable {
    public let pid: Int
    /// What it runs, as the agent wrote it, such as `npm run dev`.
    public let command: String
    public let started: Date

    public init(pid: Int, command: String, started: Date) {
        self.pid = pid
        self.command = command
        self.started = started
    }
}

/// Finds what agents leave running. Agents run each command in a shell of its own, so a shell
/// still alive under an agent that is not working is a command it left behind. Herdr only reports
/// a pane's foreground processes, so Shepherdr reads the process table itself: on this Mac
/// directly, and on other machines over SSH.
public enum BackgroundWork {
    struct Process: Equatable, Sendable {
        let pid: Int
        let parent: Int
        let seconds: Int
        let arguments: String
    }

    /// Shells younger than this are a turn's hooks and status lines finishing, not commands left running.
    static let minimumAge = 5

    /// The processes under the given pane shells, on this Mac or over SSH; nil when the machine doesn't answer.
    static func read(under shells: [Int], on machine: Machine) async -> [Process]? {
        guard !shells.isEmpty, let command = command(under: shells, on: machine),
              let output = try? await ProcessRunner().run(executable: command.executable, arguments: command.arguments, timeout: 20),
              output.exitCode == 0 else { return nil }
        return parse(String(decoding: output.stdout, as: UTF8.self))
    }

    /// Lists every process once and keeps those under the given shells, so only they cross SSH.
    static let script = """
    ps -ww -A -o pid=,ppid=,etime=,args= | awk -v roots="$*" '
      BEGIN { n = split(roots, list, " "); for (i = 1; i <= n; i++) keep[list[i]] = 1 }
      { id[NR] = $1; parent[NR] = $2; line[NR] = $0 }
      END {
        do {
          grown = 0
          for (i = 1; i <= NR; i++) if (!(id[i] in keep) && (parent[i] in keep)) { keep[id[i]] = 1; grown = 1 }
        } while (grown)
        for (i = 1; i <= NR; i++) if (id[i] in keep) print line[i]
      }'
    """

    static func command(under shells: [Int], on machine: Machine) -> (executable: URL, arguments: [String])? {
        machine.shell(script, arguments: shells.map(String.init))
    }

    /// Reads `ps -o pid=,ppid=,etime=,args=` lines.
    static func parse(_ output: String) -> [Process] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4, let pid = Int(fields[0]), let parent = Int(fields[1]),
                  let seconds = seconds(fields[2]) else { return nil }
            return Process(pid: pid, parent: parent, seconds: seconds, arguments: fields[3].trimmingCharacters(in: .whitespaces))
        }
    }

    /// Elapsed time as `ps` writes it: `[[dd-]hh:]mm:ss`.
    static func seconds(_ elapsed: Substring) -> Int? {
        var days = 0
        var clock = elapsed
        if let dash = elapsed.firstIndex(of: "-") {
            guard let value = Int(elapsed[..<dash]) else { return nil }
            days = value
            clock = elapsed[elapsed.index(after: dash)...]
        }
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard (1...3).contains(parts.count), parts.count == clock.split(separator: ":").count else { return nil }
        return days * 86_400 + parts.reduce(0) { $0 * 60 + $1 }
    }

    /// The commands left running under a pane's shell: shells started by something that isn't a
    /// shell, such as the agent. What runs inside each one is part of it.
    static func commands(under shell: Int, in processes: [Process], minimumAge: Int = minimumAge,
                         now: Date = Date()) -> [BackgroundCommand] {
        let byID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let children = Dictionary(grouping: processes, by: \.parent)
        var found: [BackgroundCommand] = []
        var pending = children[shell] ?? []
        while let process = pending.popLast() {
            if isShell(process), !(byID[process.parent].map(isShell) ?? false) {
                if process.seconds >= minimumAge {
                    found.append(BackgroundCommand(pid: process.pid, command: describe(process.arguments),
                                                   started: now.addingTimeInterval(-Double(process.seconds))))
                }
                continue
            }
            pending += children[process.pid] ?? []
        }
        return found.sorted { $0.started < $1.started }
    }

    static func isShell(_ process: Process) -> Bool {
        guard let program = process.arguments.split(separator: " ").first else { return false }
        let name = (String(program) as NSString).lastPathComponent
        return ["sh", "bash", "zsh", "dash", "fish", "ksh", "mksh", "tcsh", "csh"].contains(name.hasPrefix("-") ? String(name.dropFirst()) : name)
    }

    /// The command a shell runs, without what the agent wraps it in. Claude Code writes
    /// `… && eval '<command>' < /dev/null && pwd -P …`; others `sh -c <command>`.
    static func describe(_ arguments: String) -> String {
        var text = arguments.replacingOccurrences(of: "\\012", with: " ")
        if let start = text.range(of: "eval '") {
            var command = ""
            var index = start.upperBound
            while index < text.endIndex {
                if text[index...].hasPrefix("'\\''") {
                    command.append("'")
                    index = text.index(index, offsetBy: 4)
                } else if text[index] == "'" {
                    break
                } else {
                    command.append(text[index])
                    index = text.index(after: index)
                }
            }
            text = command
        } else if let flag = text.range(of: " -lc ") ?? text.range(of: " -c ") {
            text = String(text[flag.upperBound...])
        }
        let words = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return words.count > 120 ? String(words.prefix(119)) + "…" : words
    }
}
