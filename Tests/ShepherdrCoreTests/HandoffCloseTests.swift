import Foundation
import Testing
@testable import ShepherdrCore

private let box = Machine(profileID: "3c9e10aa", name: "buildbox", target: "box", session: "agents", isEnabled: true)
private let machines: [Machine] = [.local, box]

private func session(_ terminal: String, on machine: Machine, workspace: String) -> AgentRow {
    let agent = Agent(id: .init(machineID: machine.id, terminalID: terminal), name: workspace, kind: "claude", state: .idle,
                      reportedState: "idle", workspaceID: "w-\(terminal)", workspaceName: workspace, tabID: "w1:t1", tabName: "1",
                      paneID: "w1:p1", directory: nil, project: nil, summary: nil, isLaunchPending: false)
    return AgentRow(agent: agent, machineName: machine.name, isStale: false)
}

/// A letter from the fixer's pane, as `shepherdr` writes it.
private func letter(_ kind: String, _ fields: String = "") throws -> Letter {
    let json = #"{"protocol":1,"id":"20261015T101502Z-7f3a9c","from":{"pane":"w4:p1","terminal":"term_fixer"},"kind":""#
        + kind + "\"" + fields + "}"
    return try Letter(id: "20261015T101502Z-7f3a9c", contents: ["letter.json": Data(json.utf8), "message.md": Data("Done.".utf8)])
}

struct HandoffCloseTests {
    private let fixer = session("term_fixer", on: box, workspace: "api")
    private let planner = session("term_planner", on: .local, workspace: "coordination")
    private let reviewer = session("term_reviewer", on: box, workspace: "review")

    /// What a letter from the fixer's machine plans, with these sessions waiting for the fixer.
    private func plan(_ letter: Letter, waiting waiters: [AgentRow], trusted: Bool = false) -> [MailAction] {
        let waits = Dictionary(uniqueKeysWithValues: waiters.map { ($0.id, [fixer.id]) })
        let context = MailContext(origin: box, isTrusted: trusted, rows: [fixer, planner, reviewer], machines: machines,
                                  macName: "Studio", waits: waits)
        return MailPlanner.plan(letter, folder: "/inbox/box/x", context: context)
    }

    @Test func aHandoffToTheSessionsWaitingClosesTheSession() throws {
        let close = HandoffClose(session: fixer.id, waiters: [planner.id, reviewer.id])
        let handoff = try letter("handoff", #","to":null,"body":"message.md","files":[]"#)
        // The reviewer is on the fixer's machine; the planner, on this Mac, gets it once you approve.
        #expect(close.outcome(of: plan(handoff, waiting: [planner, reviewer])) == .handedOff(awaitingApproval: [planner.id]))
        #expect(close.outcome(of: plan(handoff, waiting: [planner, reviewer], trusted: true)) == .handedOff(awaitingApproval: []))
        #expect(close.outcome(of: plan(handoff, waiting: [reviewer])) == .handedOff(awaitingApproval: []))
    }

    @Test func aHandoffThatGoesElsewhereKeepsTheSessionOpen() throws {
        let close = HandoffClose(session: fixer.id, waiters: [planner.id])
        let named = try letter("handoff", #","to":"review","body":"message.md","files":[]"#)
        guard case .strayed? = close.outcome(of: plan(named, waiting: [planner])) else {
            Issue.record("A handoff to another session should keep the session open")
            return
        }
        // Nobody waits for the fixer anymore: the handoff waits for a recipient in its mail.
        let unaddressed = try letter("handoff", #","to":null,"body":"message.md","files":[]"#)
        guard case .strayed? = close.outcome(of: plan(unaddressed, waiting: [])) else {
            Issue.record("A handoff nobody waits for should keep the session open")
            return
        }
    }

    @Test func otherLettersAndOtherSessionsLeaveItPending() throws {
        let close = HandoffClose(session: fixer.id, waiters: [planner.id])
        #expect(close.outcome(of: plan(try letter("notify"), waiting: [planner])) == nil)
        #expect(close.outcome(of: plan(try letter("pin", #","url":"https://github.com/theam/api/pull/41""#), waiting: [planner])) == nil)
        let reviewerClose = HandoffClose(session: reviewer.id, waiters: [planner.id])
        let handoff = try letter("handoff", #","to":null,"body":"message.md","files":[]"#)
        #expect(reviewerClose.outcome(of: plan(handoff, waiting: [planner])) == nil)
    }

    @Test func itGivesUpOnlyLongAfterAskingAnAgentThatStopped() {
        let asked = Date(timeIntervalSince1970: 1_000_000)
        let later = asked.addingTimeInterval(HandoffClose.patience + 1)
        #expect(!HandoffClose(session: fixer.id, waiters: [planner.id]).hasExpired(now: later, agentIsWorking: false))
        let close = HandoffClose(session: fixer.id, waiters: [planner.id], stage: .asked(asked))
        #expect(!close.hasExpired(now: asked.addingTimeInterval(60), agentIsWorking: false))
        #expect(!close.hasExpired(now: later, agentIsWorking: true))
        #expect(close.hasExpired(now: later, agentIsWorking: false))
    }

    @Test func theRequestNamesWhoWaitsAndTheCommand() {
        let one = HandoffClose.prompt(waiters: ["coordination"])
        #expect(one.contains("the session waiting for you, coordination"))
        #expect(one.contains("`~/.shepherdr/bin/shepherdr handoff`") && one.contains("without --to"))
        #expect(!one.contains("\n"))
        #expect(HandoffClose.prompt(waiters: ["coordination", "review"]).contains("the sessions waiting for you: coordination, review"))
    }
}
