import Foundation
import Testing
@testable import ShepherdrCore

@Suite @MainActor struct ProjectRunsTests {
    private func id(_ terminal: String, on machine: String = "local") -> Agent.ID {
        Agent.ID(machineID: machine, terminalID: terminal)
    }

    private func row(_ terminal: String, on machine: String = "local") -> AgentRow {
        let agent = Agent(id: id(terminal, on: machine), name: "Claude Code", kind: "claude", state: .idle, reportedState: "idle",
                          workspaceID: "w-\(terminal)", workspaceName: terminal, tabID: "w1:t1", tabName: "1", paneID: "w1:p1",
                          directory: nil, project: nil, summary: nil, isLaunchPending: false)
        return AgentRow(agent: agent, machineName: machine, isStale: false)
    }

    private func withDefaults(_ body: @MainActor (UserDefaults) async throws -> Void) async throws {
        let suite = "ShepherdrTests.ProjectRuns.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try await body(defaults)
    }

    @Test func projectsWithTwoOrMoreItemsGatherWhereTheirFirstIs() {
        let projects = ["a": "app", "b": "api", "c": "app", "d": "web", "f": "app"]
        let items = ["a", "b", "c", "d", "e", "f"]
        let segments = ProjectRuns.segments(items) { projects[$0] }
        #expect(segments == [.project("app", ["a", "c", "f"]), .single("b"), .single("d"), .single("e")])
        #expect(ProjectRuns.gathered(items) { projects[$0] } == ["a", "c", "f", "b", "d", "e"])
        // A lone session of a project, and sessions without one, stay plain.
        #expect(ProjectRuns.segments(["b", "e", "d"]) { projects[$0] } == [.single("b"), .single("e"), .single("d")])
        #expect(ProjectRuns.segments([String]()) { projects[$0] }.isEmpty)
    }

    @Test func layoutGathersEachListAndNumbersSessionsAsTheyShow() async throws {
        try await withDefaults { defaults in
            let rows = ["a", "b", "c", "d", "e", "f"].map { row($0) }
            let projects = [id("a"): "app", id("b"): "api", id("c"): "app", id("d"): "api", id("e"): "app", id("f"): "app"]
            let order = SessionOrderStore(defaults: defaults)
            order.synchronize(with: rows.map(\.id))
            let group = order.createGroup(named: "Work", with: id("d"))
            order.moveToGroup(id("e"), group)
            order.moveToGroup(id("b"), group)
            // Top level: a, c, f and the group; in the group: d, e, b.
            #expect(order.orderedIDs == [id("a"), id("c"), id("d"), id("e"), id("b"), id("f")])
            let plain = order.layout(rows)
            #expect(plain.flatMap(\.rows).map(\.id) == order.orderedIDs)
            let gathered = order.layout(rows, projects: projects)
            // f joins a and c at the top; inside the group, b joins d. e is alone there.
            #expect(gathered.map(\.id) == [.session(id("a")), .session(id("c")), .session(id("f")), .group(group)])
            #expect(gathered.last?.rows.map(\.id) == [id("d"), id("b"), id("e")])
            #expect(order.ranked(rows, projects: projects).map(\.manualPriority) == Array(1...6))
            #expect(order.ranked(rows, projects: projects).map(\.id) == [id("a"), id("c"), id("f"), id("d"), id("b"), id("e")])
            // Gathering only shows: the saved order is untouched.
            #expect(order.orderedIDs == [id("a"), id("c"), id("d"), id("e"), id("b"), id("f")])
        }
    }

    @Test func sessionsMoveWithinTheirProjectAndOthersStepOverIt() async throws {
        try await withDefaults { defaults in
            let a = id("a"), b = id("b"), c = id("c"), d = id("d")
            let projects = [a: "app", c: "app"]
            let order = SessionOrderStore(defaults: defaults)
            order.synchronize(with: [a, b, c, d])
            let visible: Set<QueueItemID> = [.session(a), .session(b), .session(c), .session(d)]
            // Shown: app [a, c], b, d. c is second under its heading.
            #expect(!order.canMove(.session(a), .up, visible: visible, projects: projects))
            #expect(!order.canMove(.session(c), .down, visible: visible, projects: projects))
            order.move(.session(c), .first, visible: visible, projects: projects)
            #expect(order.orderedIDs == [c, a, b, d])
            // b steps over the whole project, and d past b.
            order.move(.session(b), .up, visible: visible, projects: projects)
            #expect(order.orderedIDs == [b, c, a, d])
            order.move(.session(d), .first, visible: visible, projects: projects)
            #expect(order.orderedIDs == [d, b, c, a])
            // The heading moves the project as a whole.
            let app = ProjectRunID(group: nil, project: "app")
            #expect(order.canMove(app, .up, visible: visible, projects: projects))
            order.move(app, .first, visible: visible, projects: projects)
            #expect(order.orderedIDs == [c, a, d, b])
            #expect(!order.canMove(app, .up, visible: visible, projects: projects))
            order.move(app, .last, visible: visible, projects: projects)
            #expect(order.orderedIDs == [d, b, c, a])
            // Without projects, moves are as before.
            order.move(.session(a), .first, visible: visible)
            #expect(order.orderedIDs == [a, d, b, c])
        }
    }

    @Test func aProjectWithOneVisibleSessionShowsNoHeadingAndMovesAsOne() async throws {
        try await withDefaults { defaults in
            let a = id("a"), b = id("b"), c = id("c"), d = id("d")
            let projects = [a: "app", c: "app"]
            let order = SessionOrderStore(defaults: defaults)
            order.synchronize(with: [a, b, c, d])
            // A filter hides c: a shows alone, without a heading.
            let filtered: Set<QueueItemID> = [.session(a), .session(b), .session(d)]
            let app = ProjectRunID(group: nil, project: "app")
            #expect(!order.canMove(app, .down, visible: filtered, projects: projects))
            order.move(.session(a), .down, visible: filtered, projects: projects)
            // c travels with a, as the project gathers them anyway.
            #expect(order.orderedIDs == [b, a, c, d])
            // A hidden session doesn't move.
            #expect(!order.canMove(.session(c), .up, visible: filtered, projects: projects))
        }
    }

    @Test func projectsGatherInsideGroupsToo() async throws {
        try await withDefaults { defaults in
            let a = id("a"), b = id("b"), c = id("c"), d = id("d")
            let projects = [a: "app", c: "app"]
            let order = SessionOrderStore(defaults: defaults)
            order.synchronize(with: [a, b, c, d])
            let group = order.createGroup(named: "Work", with: a)
            order.moveToGroup(b, group)
            order.moveToGroup(c, group)
            let visible: Set<QueueItemID> = [.group(group), .session(a), .session(b), .session(c), .session(d)]
            order.move(.session(b), .first, visible: visible, projects: projects)
            #expect(order.groups.first?.members == [b, a, c])
            let app = ProjectRunID(group: group, project: "app")
            order.move(app, .first, visible: visible, projects: projects)
            #expect(order.groups.first?.members == [a, c, b])
            // The same project at the top level is another heading.
            #expect(!order.canMove(ProjectRunID(group: nil, project: "app"), .up, visible: visible, projects: projects))
        }
    }

    @Test func dropsLandWhereTheyShow() async throws {
        try await withDefaults { defaults in
            let a = id("a"), b = id("b"), c = id("c"), d = id("d")
            let projects = [a: "app", c: "app"]
            let order = SessionOrderStore(defaults: defaults)
            order.synchronize(with: [a, b, c, d])
            // Shown: app [a, c], b, d. Dropped after the project's last session, d lands before b.
            order.place(.session(d), .after(.session(c)), projects: projects)
            #expect(order.orderedIDs == [a, c, d, b])
            order.insert(id("e"), .after(.session(a)), projects: projects)
            #expect(order.orderedIDs == [a, id("e"), c, d, b])
        }
    }

    @Test func theOptionAndCollapsedHeadingsSurviveRelaunch() async throws {
        try await withDefaults { defaults in
            let order = SessionOrderStore(defaults: defaults)
            #expect(!order.gathersProjects)
            order.gathersProjects = true
            let top = ProjectRunID(group: nil, project: "app")
            let grouped = ProjectRunID(group: "g", project: "app")
            order.setCollapsed(grouped, true)
            let reopened = SessionOrderStore(defaults: defaults)
            #expect(reopened.gathersProjects)
            #expect(reopened.isCollapsed(grouped))
            #expect(!reopened.isCollapsed(top))
            reopened.setCollapsed(grouped, false)
            #expect(!SessionOrderStore(defaults: defaults).isCollapsed(grouped))
        }
    }
}
