import Foundation
import Testing
@testable import ShepherdrCore

struct BackgroundWorkTests {
    /// A pane as `ps` lists it: its login shell, Claude Code, a dev server it left running with the
    /// process npm started, a command that just began, and an MCP server.
    private let listing = #"""
      100     1 3-02:00:00 -zsh
      200   100 2-01:00:00 claude
      300   200      12:05 /bin/zsh -c source /Users/me/.claude/shell-snapshots/snapshot-zsh-1.sh 2>/dev/null || true && { \builtin unalias -- 'unsetenv'; } >/dev/null 2>&1 || true && eval 'npm run dev -- --port '\''5173'\''' \< /dev/null && pwd -P >| /tmp/claude-1-cwd
      301   300      12:04 node /Users/me/app/node_modules/.bin/vite
      302   301      12:04 sh -c esbuild --service
      400   200      00:02 /bin/zsh -c source /Users/me/.claude/shell-snapshots/snapshot-zsh-1.sh && eval 'git status' \< /dev/null
      500   200    1:00:00 node /Users/me/.npm/_npx/mcp-server/index.js
      600   200      45:00 bash -lc cargo watch -x test
    """#

    @Test func psOutputIsRead() {
        let processes = BackgroundWork.parse(listing)
        #expect(processes.count == 8)
        #expect(processes[0] == BackgroundWork.Process(pid: 100, parent: 1, seconds: 3 * 86_400 + 2 * 3_600, arguments: "-zsh"))
        #expect(processes[2].seconds == 12 * 60 + 5)
        #expect(BackgroundWork.seconds("05") == 5)
        #expect(BackgroundWork.seconds("1:02:03") == 3_723)
        #expect(BackgroundWork.seconds("x:10") == nil)
    }

    @Test func commandsLeftRunningAreShellsTheAgentStarted() {
        let now = Date()
        let found = BackgroundWork.commands(under: 100, in: BackgroundWork.parse(listing), now: now)
        // What npm started belongs to its command; a command younger than five seconds and the MCP server don't count.
        #expect(found == [BackgroundCommand(pid: 600, command: "cargo watch -x test", started: now - 2_700),
                          BackgroundCommand(pid: 300, command: "npm run dev -- --port '5173'", started: now - 725)])
        #expect(BackgroundWork.commands(under: 200, in: BackgroundWork.parse(listing)).count == 2)
        #expect(BackgroundWork.commands(under: 999, in: BackgroundWork.parse(listing)).isEmpty)
        // A shell the user started inside the pane's shell is not the agent's.
        let nested = BackgroundWork.parse("  100 1 10:00 -zsh\n  110 100 09:00 bash\n  120 110 08:00 sleep 100")
        #expect(BackgroundWork.commands(under: 100, in: nested).isEmpty)
    }

    @Test func theListingRunsHereAndOverSSH() async throws {
        // A shell started by something that isn't one: this test, standing in for an agent.
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sh")
        sleeper.arguments = ["-c", "sleep 30; :"]
        try sleeper.run()
        defer { sleeper.terminate() }
        try await Task.sleep(for: .milliseconds(200))
        let me = Int(ProcessInfo.processInfo.processIdentifier)
        let processes = try #require(await BackgroundWork.read(under: [me], on: .local))
        #expect(processes.contains { $0.pid == me })
        #expect(processes.allSatisfy { $0.pid == me || $0.parent != 1 })
        let found = BackgroundWork.commands(under: me, in: processes, minimumAge: 0)
        #expect(found.contains { $0.pid == Int(sleeper.processIdentifier) && $0.command == "sleep 30; :" })

        let remote = try #require(BackgroundWork.command(under: [12, 34], on: Fixture.remote))
        #expect(remote.executable.path == "/usr/bin/ssh")
        #expect(remote.arguments.contains("BatchMode=yes"))
        #expect(try #require(remote.arguments.last).hasSuffix("' sh 12 34"))
    }

    @MainActor @Test func theStoreAsksForEachPaneShellOnceAndWatchesOnlyIdleAgents() async {
        let client = MockHerdrClient()
        await client.setShellPID(100, for: "w1:p1")
        await client.setShellPID(700, for: "w2:p1")
        let listing = listing
        let reads = Reads()
        let store = BackgroundWorkStore(client: client) { shells, _ in
            await reads.add(shells)
            return BackgroundWork.parse(listing)
        }
        let done = row("w1:p1", .done), working = row("w2:p1", .working)
        await store.refresh([done, working], machines: [.local])
        #expect(store.commands[done.id]?.map(\.command) == ["cargo watch -x test", "npm run dev -- --port '5173'"])
        #expect(store.commands[working.id] == nil)
        await store.refresh([done, working], machines: [.local])
        #expect(await client.recordedShellQueries() == ["w1:p1"])
        #expect(await reads.all == [[100], [100]])
        // Back to work: nothing is shown while it works.
        await store.refresh([row("w1:p1", .working)], machines: [.local])
        #expect(store.commands.isEmpty)
    }

    private func row(_ pane: String, _ state: AgentState) -> AgentRow {
        let agent = Agent(id: .init(machineID: "local", terminalID: "t-\(pane)"), name: "Claude Code", kind: "claude",
                          state: state, reportedState: state.rawValue, workspaceID: "w", workspaceName: pane,
                          tabID: "t", tabName: "1", paneID: pane, directory: nil, project: nil, summary: nil, isLaunchPending: false)
        return AgentRow(agent: agent, machineName: "Local", isStale: false, lastSuccess: nil)
    }
}

private actor Reads {
    var all: [[Int]] = []
    func add(_ shells: [Int]) { all.append(shells) }
}
