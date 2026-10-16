import Foundation

/// Keeps holds about sessions that are still there: a session that closed, from Shepherdr or
/// elsewhere, no longer waits, and nothing waits for it.
public enum HoldUpkeep {
    /// How long a session must be missing from its machine's snapshots before holds forget it: one
    /// just started on another machine may not be in the last snapshot yet.
    public static let grace: TimeInterval = 30

    /// The sessions among `ids` that their machine, answering, has stopped reporting for at least
    /// `grace`. `missingSince` remembers when each was first missing. A machine that doesn't answer,
    /// or isn't known, says nothing about its sessions.
    public static func gone(_ ids: Set<Agent.ID>, machines: [MachineState], missingSince: inout [Agent.ID: Date],
                            now: Date = Date()) -> [Agent.ID] {
        missingSince = missingSince.filter { ids.contains($0.key) }
        var gone: [Agent.ID] = []
        for id in ids {
            guard let state = machines.first(where: { $0.id == id.machineID }), state.connection == .online,
                  let snapshot = state.snapshot else { continue }
            if snapshot.panes.contains(where: { $0.terminalID == id.terminalID }) || snapshot.agents.contains(where: { $0.id == id }) {
                missingSince[id] = nil
                continue
            }
            let since = missingSince[id] ?? now
            missingSince[id] = since
            if now.timeIntervalSince(since) >= grace { gone.append(id) }
        }
        return gone.sorted { ($0.machineID, $0.terminalID) < ($1.machineID, $1.terminalID) }
    }
}

/// A shell another session waits for, as Shepherdr has seen it. A shell has no agent to hand its
/// work back, so the session waits for the command it runs, such as a script: the hold ends once
/// that command is back at the shell's prompt.
public struct ShellRun: Equatable, Sendable {
    /// Whether it was running a command when last seen.
    public private(set) var isRunning = false
    private var ranCommand = false
    /// What it showed above its prompt line when first seen at its prompt. If that changes while it
    /// is at its prompt, a command ran and finished between two looks.
    private var printed: String?

    public init() {}

    /// Takes in a look at the shell: whether it runs a command, and if it doesn't, its last lines.
    /// Returns whether the command it waited for has finished.
    public mutating func see(running: Bool, output: String?) -> Bool {
        isRunning = running
        if running {
            ranCommand = true
            return false
        }
        if ranCommand { return true }
        // Typing at the prompt only changes its last line.
        guard let output else { return false }
        var lines = output.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        while lines.last?.isEmpty == true { lines.removeLast() }
        if !lines.isEmpty { lines.removeLast() }
        let above = lines.joined(separator: "\n")
        guard let printed else {
            self.printed = above
            return false
        }
        return above != printed
    }
}
