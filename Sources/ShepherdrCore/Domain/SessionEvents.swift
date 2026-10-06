import Foundation

/// Notices agents that stopped working between two refreshes: they finished, or they need the user.
public struct AgentStateTracker: Sendable {
    private var states: [Agent.ID: AgentState] = [:]

    public init() {}

    /// Sessions whose agent was working at the previous refresh and is now done or blocked. Stale
    /// sessions keep their last known state until their machine answers again; the first refresh
    /// only records where every agent stands.
    public mutating func stoppedWorking(_ rows: [AgentRow]) -> [AgentRow] {
        var next: [Agent.ID: AgentState] = [:]
        var stopped: [AgentRow] = []
        for row in rows {
            let previous = states[row.id]
            if row.isStale {
                next[row.id] = previous
                continue
            }
            next[row.id] = row.agent.state
            if previous == .working, row.agent.state == .done || row.agent.state == .blocked { stopped.append(row) }
        }
        states = next
        return stopped
    }
}

/// What an agent last said, read from its terminal text.
public enum AgentReply {
    /// Agent TUIs start each message with a bullet: Claude Code ⏺, Codex •, Gemini ✦.
    private static let bullets: Set<Character> = ["⏺", "•", "✦"]

    /// The opening paragraph of the last message in `text`: the bulleted line and the indented lines
    /// that continue it, as one line of at most `limit` characters. Nil when there is none.
    public static func lastParagraph(in text: String, limit: Int = 220) -> String? {
        let lines = text.components(separatedBy: .newlines)
        guard let start = lines.lastIndex(where: { line in
            line.first.map(bullets.contains) == true && line.dropFirst().first == " "
        }) else { return nil }
        var parts = [String(lines[start].dropFirst(2))]
        for line in lines[(start + 1)...] {
            guard line.first?.isWhitespace == true, !line.trimmingCharacters(in: .whitespaces).isEmpty else { break }
            parts.append(line)
        }
        let paragraph = parts.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !paragraph.isEmpty else { return nil }
        return paragraph.count <= limit ? paragraph : String(paragraph.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// How agents address a session through Herdr, for pasting into another agent's prompt.
public enum PaneReference {
    /// The command an agent in the same Herdr session runs to send this one a prompt.
    public static func promptCommand(paneID: String) -> String {
        "herdr agent prompt \(paneID) \"<message>\""
    }

    public static func description(workspace: String, paneID: String, machine: Machine) -> String {
        let place = machine.isLocal ? "" : " on \(machine.name)"
        return "Herdr pane \(paneID) (\(workspace)\(place)); send it a prompt with: \(promptCommand(paneID: paneID))"
    }
}
