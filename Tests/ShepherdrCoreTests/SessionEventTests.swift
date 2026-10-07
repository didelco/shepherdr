import Foundation
import Testing
@testable import ShepherdrCore

struct SessionEventTests {
    private func row(_ terminal: String, _ state: AgentState, stale: Bool = false) -> AgentRow {
        let agent = Agent(id: .init(machineID: "local", terminalID: terminal), name: "Claude Code", kind: "claude",
                          state: state, reportedState: state.rawValue, workspaceID: "w1", workspaceName: terminal,
                          tabID: "w1:t1", tabName: "1", paneID: "w1:p1", directory: nil, project: nil,
                          summary: nil, isLaunchPending: false)
        return AgentRow(agent: agent, machineName: "Local", isStale: stale, lastSuccess: nil)
    }

    @Test func agentsThatStopWorkingAreReportedOnce() {
        var tracker = AgentStateTracker()
        // The first refresh only records where everyone stands.
        #expect(tracker.stoppedWorking([row("a", .done), row("b", .working), row("c", .working)]).isEmpty)
        let stopped = tracker.stoppedWorking([row("a", .done), row("b", .done), row("c", .blocked)])
        #expect(stopped.map(\.workspace) == ["b", "c"])
        #expect(tracker.stoppedWorking([row("a", .done), row("b", .done), row("c", .blocked)]).isEmpty)
        // Going idle is not news: someone was watching it finish.
        #expect(tracker.stoppedWorking([row("a", .working)]).isEmpty)
        #expect(tracker.stoppedWorking([row("a", .idle)]).isEmpty)
    }

    @Test func staleSessionsKeepTheirLastKnownState() {
        var tracker = AgentStateTracker()
        _ = tracker.stoppedWorking([row("a", .working)])
        #expect(tracker.stoppedWorking([row("a", .done, stale: true)]).isEmpty)
        // Back online: it was working when last seen and is done now.
        #expect(tracker.stoppedWorking([row("a", .done)]).map(\.workspace) == ["a"])
    }

    @Test func theLastMessagesOpeningParagraphIsItsSummary() {
        let claude = """
        ⏺ Bash(swift test)
          ⎿  Test run with 66 tests passed

        ⏺ All 66 tests pass. I fixed the
          flaky timeout in TransportTests and
          added a regression test.

          Next, the release notes.

        ✻ Baked for 2m 10s

        ────────────────────────
        ❯
        ────────────────────────
          ⏵⏵ accept edits on
        """
        #expect(AgentReply.lastParagraph(in: claude)
                == "All 66 tests pass. I fixed the flaky timeout in TransportTests and added a regression test.")
        #expect(AgentReply.lastParagraph(in: "• Done: exit code 0\n\n› ") == "Done: exit code 0")
        #expect(AgentReply.lastParagraph(in: "$ ls\nREADME.md\n") == nil)
        let long = AgentReply.lastParagraph(in: "✦ " + String(repeating: "word ", count: 100), limit: 40)
        #expect(long?.count == 40)
        #expect(long?.hasSuffix("…") == true)
    }

    @Test func referencesTellAgentsHowToPromptAPane() {
        #expect(PaneReference.promptCommand(paneID: "wE:p1") == #"herdr agent prompt wE:p1 "<message>""#)
        let remote = Machine(profileID: "moon", name: "Moonbase", target: "moon.local", session: "default", isEnabled: true)
        #expect(PaneReference.description(workspace: "planner", paneID: "w2:p1", machine: remote)
                == #"Herdr pane w2:p1 (planner on Moonbase); send it a prompt with: herdr agent prompt w2:p1 "<message>""#)
    }

    @Test func recentOutputIsReadAsPlainTextThroughTheMachine() async throws {
        let runner = RecordingRunner([output("⏺ Hello\n")])
        let client = CLIHerdrClient(runner: runner, executable: URL(fileURLWithPath: "/usr/bin/true"))
        let remote = Machine(profileID: "moon", name: "Moonbase", target: "moon.local", session: "default", isEnabled: true)
        #expect(try await client.recentOutput(paneID: "w2:p1", on: remote, lines: 60) == "⏺ Hello\n")
        #expect(await runner.recordedArguments()
                == [["--machine", "moon", "pane", "read", "w2:p1", "--source", "recent-unwrapped", "--lines", "60", "--format", "text"]])
    }
}
