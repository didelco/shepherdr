import Foundation
import Testing
@testable import ShepherdrCore

struct SessionSearchTests {
    private func row(_ workspace: String, name: String = "claude", on machine: String = "Local",
                     in directory: String? = nil, doing summary: String? = nil) -> AgentRow {
        let agent = Agent(id: .init(machineID: machine, terminalID: "term-\(workspace)-\(machine)"), name: name, kind: "claude",
                          state: .idle, reportedState: "idle", workspaceID: "w-\(workspace)", workspaceName: workspace,
                          tabID: "w1:t1", tabName: "1", paneID: "w1:p1", directory: directory, project: nil,
                          summary: summary, isLaunchPending: false)
        return AgentRow(agent: agent, machineName: machine, isStale: false)
    }

    @Test func namesThatStartWithWhatYouTypeComeFirst() {
        let rows = [row("checkout-api", doing: "Fixing the login"), row("login"), row("web-login-page"),
                    row("billing", in: "/p/login-service"), row("Logistics"), row("catalog"), row("api")]
        let found = SessionSearch.ranked(rows, matching: "log")
        // A name's start first, then a word's start, any part of a name, and a match elsewhere.
        #expect(found.map(\.workspace) == ["login", "Logistics", "web-login-page", "catalog", "checkout-api", "billing"])
        #expect(SessionSearch.ranked(rows, matching: "LOGIN").first?.workspace == "login")
        #expect(SessionSearch.ranked(rows, matching: "nothing like it").isEmpty)
    }

    @Test func everyWordMustMatchSomewhere() {
        let rows = [row("api", on: "buildbox"), row("api", on: "Local"), row("web", on: "buildbox")]
        #expect(SessionSearch.ranked(rows, matching: "api build").map(\.machineName) == ["buildbox"])
        #expect(SessionSearch.ranked(rows, matching: "  ").count == 3)
    }

    @Test func anAtNarrowsToAMachine() {
        let rows = [row("api", on: "buildbox"), row("api", on: "Local"), row("web", on: "buildbox")]
        #expect(SessionSearch.ranked(rows, matching: "api@build").map(\.machineName) == ["buildbox"])
        #expect(SessionSearch.ranked(rows, matching: "@build").map(\.workspace) == ["api", "web"])
        // Nothing typed after it yet: no narrowing.
        #expect(SessionSearch.ranked(rows, matching: "api@").count == 2)
    }

    @Test func emptyQueriesKeepTheOrderGiven() {
        let rows = [row("b"), row("a"), row("c")]
        #expect(SessionSearch.ranked(rows, matching: "").map(\.workspace) == ["b", "a", "c"])
    }
}
