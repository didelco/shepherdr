import Testing
import Foundation
@testable import ShepherdrCore

@Suite struct DecodingTests {
    @Test func testDocumentedSnapshotAndDomainJoins() throws {
        let snapshot = try Fixture.snapshot()
        #expect(snapshot.version == "0.9.0")
        #expect(snapshot.protocolVersion == 22)
        #expect(snapshot.workspaces.count == 2)
        #expect(snapshot.agents.count == 4) // Ordinary shell pane is not an agent.
        let reviewer = snapshot.agents[0]
        #expect(reviewer.name == "API reviewer")
        // The agent comes from Herdr's label, not from the name its pane reports for display.
        #expect(reviewer.kind == "claude")
        #expect(reviewer.program.name == "Claude Code" && reviewer.program.glyph == "✻")
        #expect(reviewer.workspaceName == "Orchard")
        #expect(reviewer.tabName == "Development")
        #expect(reviewer.directory == "/srv/orchard/packages/api")
        #expect(reviewer.project == "orchard")
        #expect(reviewer.summary == "Permission to run tests")
        #expect(reviewer.state == .blocked) // Display-only state_labels cannot change semantics.
        #expect(snapshot.agents[1].directory == "/srv/orchard/web")
        #expect(snapshot.agents[2].directory == "/srv/orchard-review")
        #expect(snapshot.agents[2].name == "opencode")
        // Without a name of its own, a session goes by its agent's name.
        #expect(snapshot.agents[1].name == "Codex" && snapshot.agents[1].program.glyph == ">_")
    }

    @Test func eachAgentShowsItsOwnMark() {
        #expect(AgentProgram(label: " Claude ").name == "Claude Code")
        #expect(AgentProgram(label: "gemini").glyph == "✦")
        #expect(AgentProgram(label: "agy").name == "Antigravity")
        // Agents Herdr doesn't know keep the name they report.
        let custom = AgentProgram(label: "my-bot")
        #expect(custom.name == "my-bot" && custom.label == "my-bot" && custom.glyph == "◇")
        #expect(AgentProgram(label: "").name == "Unknown agent")
    }

    @Test func testEveryLifecycleStateAndFutureState() {
        for state in AgentState.allCases {
            #expect(AgentState(reportedValue: state.rawValue) == state)
        }
        #expect(AgentState(reportedValue: "future-paused") == .unknown)
        #expect(AgentState.blocked.priority < AgentState.working.priority)
    }

    @Test func testUnknownFieldsAndUnknownStatesAreForwardCompatible() throws {
        let text = String(decoding: try Fixture.data(), as: UTF8.self)
            .replacingOccurrences(of: "\"blocked\"", with: "\"future-paused\"")
            .replacingOccurrences(of: "\"protocol\": 22", with: "\"protocol\": 100")
        let snapshot = try HerdrJSON.snapshot(Data(text.utf8), machine: .local)
        #expect(snapshot.agents[0].state == .unknown)
        #expect(snapshot.agents[0].reportedState == "future-paused")
        #expect(snapshot.protocolVersion == 100) // JSON shape, not private protocol version, is the contract.
    }

    @Test func testEmptySnapshotIsDifferentFromMissingCollections() throws {
        let valid = #"{"result":{"type":"session_snapshot","snapshot":{"version":"test","protocol":22,"agents":[],"workspaces":[],"tabs":[],"panes":[]}}}"#
        #expect(try HerdrJSON.snapshot(Data(valid.utf8), machine: .local).agents.isEmpty)
        let invalid = valid.replacingOccurrences(of: "\"agents\":[],", with: "")
        #expect(throws: (any Error).self) { try HerdrJSON.snapshot(Data(invalid.utf8), machine: .local) }
        #expect(throws: (any Error).self) { try HerdrJSON.snapshot(Data("not json".utf8), machine: .local) }
    }

    @Test func testDuplicateIDsAreRejectedWithoutTrapping() throws {
        let text = String(decoding: try Fixture.data(), as: UTF8.self)
            .replacingOccurrences(of: "term-b", with: "term-a")
        #expect(throws: HerdrFailure.self) { try HerdrJSON.snapshot(Data(text.utf8), machine: .local) }
    }

    @Test func testMissingJoinUsesPublicIDs() throws {
        var json = try #require(JSONSerialization.jsonObject(with: Fixture.data()) as? [String: Any])
        var result = try #require(json["result"] as? [String: Any])
        var snapshot = try #require(result["snapshot"] as? [String: Any])
        snapshot["workspaces"] = []
        snapshot["tabs"] = []
        snapshot["panes"] = []
        result["snapshot"] = snapshot
        json["result"] = result
        let mapped = try HerdrJSON.snapshot(JSONSerialization.data(withJSONObject: json), machine: .local)
        #expect(mapped.agents[0].workspaceName == "w1")
        #expect(mapped.agents[0].tabName == "w1:t1")
    }

    @Test func testCatalogPreservesOpaqueIDsSessionsAndDisabledProfiles() throws {
        let machines = try HerdrJSON.machines(Fixture.data("machines"))
        #expect(machines[0].profileID == "opaque-remote-a")
        #expect(machines[0].session == "agents")
        #expect(!(machines[1].isEnabled))
        #expect(machines[1].target == "ssh://dev@lab:2222")
        #expect(machines[0].id != Machine.local.id)
    }

    @Test func testMachineScopedAgentIdentity() throws {
        let local = try Fixture.snapshot()
        let remote = try Fixture.snapshot(machine: Fixture.remote)
        #expect(local.agents[0].id != remote.agents[0].id)
        #expect(local.agents[0].id.terminalID == remote.agents[0].id.terminalID)
    }

    @Test func howFarBackHerdrShowsATerminal() throws {
        // As `herdr pane list` answers, trimmed to what matters.
        let list = Data("""
        {"id":"cli:pane:list","result":{"type":"pane_list","panes":[
          {"pane_id":"w1:p1","terminal_id":"term_a","focused":true,
           "scroll":{"max_offset_from_bottom":126,"offset_from_bottom":42,"viewport_rows":24}},
          {"pane_id":"w2:p1","terminal_id":"term_b"}]}}
        """.utf8)
        #expect(try HerdrJSON.linesBack(list, terminalID: "term_a") == 42)
        #expect(try HerdrJSON.linesBack(list, terminalID: "term_b") == nil)
        #expect(try HerdrJSON.linesBack(list, terminalID: "term_gone") == nil)
    }
}
