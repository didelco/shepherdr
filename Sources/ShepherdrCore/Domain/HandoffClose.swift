import Foundation

/// A session you asked to hand its work back to the sessions waiting for it, and to close once it
/// has. Shepherdr asks its agent to run `shepherdr handoff` when the agent is free, and closes the
/// session as soon as that handoff reaches this Mac: from then on Shepherdr holds the message and
/// files, and delivers them whether or not the session still exists.
public struct HandoffClose: Equatable, Sendable {
    public enum Stage: Equatable, Sendable {
        /// Waiting for its agent to be free to read the request.
        case queued
        /// The request is in its agent's prompt; waiting for the handoff since then.
        case asked(Date)
    }

    /// What a letter means for the close.
    public enum Outcome: Equatable, Sendable {
        /// Its handoff is on this Mac, for sessions that wait for it: the session can close. The
        /// sessions listed get it once you approve, as handoffs that cross machines need.
        case handedOff(awaitingApproval: [Agent.ID])
        /// Its handoff went nowhere it was meant to: the session stays open.
        case strayed(String)
    }

    public let session: Agent.ID
    /// The sessions that waited for it when you asked.
    public let waiters: [Agent.ID]
    public var stage: Stage

    /// How long Shepherdr waits for the handoff after asking, while the agent isn't working on it.
    public static let patience: TimeInterval = 15 * 60

    public init(session: Agent.ID, waiters: [Agent.ID], stage: Stage = .queued) {
        self.session = session
        self.waiters = waiters
        self.stage = stage
    }

    /// What the actions a letter planned mean for the close: nil unless the letter is the session's handoff.
    public func outcome(of actions: [MailAction]) -> Outcome? {
        let handoffs = actions.compactMap { action -> MailItem? in
            guard case .keep(let item) = action, item.kind == .handoff, item.sender == session else { return nil }
            return item
        }
        guard !handoffs.isEmpty else { return nil }
        let delivered = handoffs.filter { item in
            item.recipient.map(waiters.contains) == true && (item.status == .queued || item.status == .needsApproval)
        }
        guard delivered.isEmpty else {
            return .handedOff(awaitingApproval: delivered.filter { $0.status == .needsApproval }.compactMap(\.recipient))
        }
        // Named another session, or found nobody waiting: the session's mail panel has it.
        return .strayed("Its handoff didn't go to the sessions waiting for it, so the session stays open. Its mail shows where it went.")
    }

    /// Whether to give up: the handoff hasn't come long after asking, and the agent isn't still at it.
    public func hasExpired(now: Date, agentIsWorking: Bool) -> Bool {
        guard case .asked(let since) = stage else { return false }
        return !agentIsWorking && now.timeIntervalSince(since) > Self.patience
    }

    /// The request typed into the agent's prompt. It names the sessions waiting, so the agent knows
    /// who reads its handoff.
    public static func prompt(waiters: [String]) -> String {
        let names = waiters.isEmpty ? "the session waiting for you"
            : (waiters.count == 1 ? "the session waiting for you, \(waiters[0])" : "the sessions waiting for you: \(waiters.joined(separator: ", "))")
        return """
        Shepherdr: the user asks you to wrap up and hand your work back to \(names). Run \
        `~/.shepherdr/bin/shepherdr handoff` now, without --to, so it goes to them. Write a message that stands \
        alone: what you did, the results, links, and what is left. Attach the files that matter with --file. \
        Shepherdr closes this session once your handoff arrives, so put everything in it and don't start new work.
        """
    }
}
