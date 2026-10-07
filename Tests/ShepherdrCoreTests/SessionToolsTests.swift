import Foundation
import Testing
@testable import ShepherdrCore

struct SessionResourceTests {
    @Test func pullRequestsIssuesAndArtifactsAreRecognized() throws {
        func resource(_ link: String) -> SessionResource? { SessionResource(url: URL(string: link)!) }
        let pull = try #require(resource("https://github.com/theam/shepherdr/pull/12/files#diff-1"))
        #expect(pull.kind == .pullRequest && pull.name == "theam/shepherdr#12")
        #expect(pull.url.absoluteString == "https://github.com/theam/shepherdr/pull/12")
        #expect(resource("https://github.com/theam/shepherdr/issues/7")?.name == "theam/shepherdr#7")
        #expect(resource("https://gitlab.com/acme/tools/api/-/merge_requests/31")?.name == "acme/tools/api!31")
        #expect(resource("https://git.acme.dev/infra/-/issues/4")?.kind == .issue)
        #expect(resource("https://linear.app/acme/issue/ENG-42/fix-login")?.url.absoluteString == "https://linear.app/acme/issue/ENG-42")
        #expect(resource("https://acme.atlassian.net/browse/OPS-9")?.name == "OPS-9")
        let artifact = try #require(resource("https://claude.ai/code/artifact/3f450b55-1137-49cd-a8ae-0b909aa9e097?x=1"))
        #expect(artifact.kind == .artifact && artifact.name == "artifact 3f450b55")
        #expect(resource("https://claude.ai/public/artifacts/abc123")?.kind == .artifact)
        // Pages that are not one pull request, issue or artifact are not kept.
        #expect(resource("https://github.com/theam/shepherdr") == nil)
        #expect(resource("https://github.com/theam/shepherdr/pulls") == nil)
        #expect(resource("https://claude.ai/new") == nil)
        #expect(resource("https://example.com/-/issues/x") == nil)
    }

    @Test func resourcesAreFoundInTextAndOnScreenNewestFirst() {
        let text = "Opened https://github.com/theam/shepherdr/pull/12. See https://github.com/theam/shepherdr/pull/12 and https://herdr.dev/docs/."
        #expect(SessionResources.find(in: text).map(\.name) == ["theam/shepherdr#12"])
        // A link wrapped at the edge of a 30-column screen.
        let rows = ["Artifact: https://claude.ai/ar", "tifact/0f9e8a76 ready         "].map(Array.init)
        #expect(SessionResources.find(onScreen: rows).map(\.url.absoluteString) == ["https://claude.ai/artifact/0f9e8a76"])
        let known = SessionResources.find(in: "https://github.com/a/b/issues/1")
        let merged = SessionResources.merge(SessionResources.find(in: "https://github.com/a/b/issues/1 https://github.com/a/b/pull/2"), into: known)
        #expect(merged.map(\.name) == ["a/b#2", "a/b#1"])
    }
}

struct TerminalPathTests {
    private func path(_ line: String, at fragment: String) -> String? {
        let row = Array(line)
        let column = line.distance(from: line.startIndex, to: line.range(of: fragment)!.lowerBound)
        return TerminalPaths.path(in: row, column: column)
    }

    @Test func pathsAreReadWithoutTheirDecoration() {
        #expect(path("⏺ Update(docs/GUIDE.md)", at: "GUIDE") == "docs/GUIDE.md")
        #expect(path("  ⎿  App/Theme.swift:23:5 changed.", at: "Theme") == "App/Theme.swift")
        #expect(path("Saved to `~/notes/plan.md`.", at: "plan") == "~/notes/plan.md")
        #expect(path("open /Users/Shared/report.html", at: "report") == "/Users/Shared/report.html")
        #expect(path("See README.md, then run it", at: "README") == "README.md")
        #expect(path("versions 0.9.3 and later", at: "0.9") == nil)
        #expect(path("visit https://herdr.dev/docs", at: "herdr") == nil)
        #expect(path("plain words here", at: "words") == nil)
        // Wrapped at the right edge of a 30-column screen.
        let rows = ["  The report is in docs/r", "eport.html, as promised."].map { Array($0.padding(toLength: 25, withPad: " ", startingAt: 0)) }
        #expect(TerminalPaths.path(in: rows, row: 1, column: 2) == "docs/report.html")
        #expect(TerminalPaths.path(in: rows, row: 0, column: 23) == "docs/report.html")
    }
}

struct TerminalMenuTests {
    private let claude = [
        "╭──────────────────────────────────────────────╮",
        "│ Do you want to proceed?                      │",
        "│ ❯ 1. Yes                                     │",
        "│   2. Yes, and don't ask again for rm         │",
        "│      commands in this project                │",
        "│   3. No, and tell Claude what to do (esc)    │",
        "╰──────────────────────────────────────────────╯",
    ]

    @Test func clickingAnOptionMovesTheHighlightToIt() {
        #expect(TerminalMenus.moves(in: claude, clicked: 2) == 0)
        #expect(TerminalMenus.moves(in: claude, clicked: 3) == 1)
        #expect(TerminalMenus.moves(in: claude, clicked: 4) == 1) // The option's wrapped second line.
        #expect(TerminalMenus.moves(in: claude, clicked: 5) == 2)
        let codex = ["  Allow command?", "    1. Yes, proceed", "  › 2. Yes, and don't ask again", "    3. No, tell Codex  esc"]
        #expect(TerminalMenus.moves(in: codex, clicked: 1) == -1)
        #expect(TerminalMenus.moves(in: codex, clicked: 3) == 1)
    }

    @Test func textThatOnlyLooksLikeAMenuIsLeftAlone() {
        #expect(TerminalMenus.moves(in: claude, clicked: 1) == nil) // The question.
        #expect(TerminalMenus.moves(in: claude, clicked: 0) == nil)
        // A numbered list with no highlight, and a typed prompt that starts with a number.
        #expect(TerminalMenus.moves(in: ["1. Install", "2. Run", "3. Enjoy"], clicked: 1) == nil)
        #expect(TerminalMenus.moves(in: ["> ", "❯ 1. fix the tests"], clicked: 1) == nil)
    }
}

@Suite @MainActor struct SessionStateTests {
    @Test func stateIsRememberedPerSessionAndForgotten() throws {
        let suite = "ShepherdrTests.SessionState.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = Agent.ID(machineID: "local", terminalID: "term-a")
        let store = SessionStateStore(defaults: defaults)
        var state = SessionStateStore.State()
        state.tabs = [URL(string: "https://github.com/theam/shepherdr/pull/12")!, URL(fileURLWithPath: "/tmp/plan.md")]
        state.selectedTab = 1
        state.showsBrowser = true
        state.resources = SessionResources.find(in: "https://github.com/theam/shepherdr/pull/12")
        store.set(state, for: id)
        store.lastSelection = id
        let reopened = SessionStateStore(defaults: defaults)
        #expect(reopened.state(for: id) == state)
        #expect(reopened.lastSelection == id)
        reopened.forget(id)
        #expect(SessionStateStore(defaults: defaults).state(for: id) == SessionStateStore.State())
    }
}

@Suite @MainActor struct MarkdownRendererTests {
    @Test func markdownBecomesAStyledPage() {
        let page = MarkdownRenderer.page(markdown: "# Plan\n\n- [x] done\n\n| a | b |\n|---|---|\n| 1 | 2 |",
                                         file: URL(fileURLWithPath: "/tmp/a <b>.md"))
        #expect(page.contains("<h1>Plan</h1>"))
        #expect(page.contains("<table>"))
        #expect(page.contains("type=\"checkbox\""))
        #expect(page.contains("<title>a &lt;b&gt;.md</title>"))
    }

    @Test func localImagesAreEmbedded() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: folder.appendingPathComponent("dog.png"))
        let page = MarkdownRenderer.page(markdown: "![dog](dog.png) ![web](https://example.com/a.png) ![gone](gone.png)",
                                         file: folder.appendingPathComponent("plan.md"))
        #expect(page.contains("src=\"data:image/png;base64,iVBORw==\""))
        #expect(page.contains("src=\"https://example.com/a.png\""))
        #expect(page.contains("src=\"gone.png\""))
    }
}

struct WorkspaceCommandTests {
    @Test func renamingUsesHerdrsWorkspaceCommand() async throws {
        let runner = RecordingRunner([output("{\"id\":\"cli:workspace:rename\",\"result\":{}}")])
        let client = CLIHerdrClient(runner: runner, executable: URL(fileURLWithPath: "/usr/bin/true"))
        try await client.renameWorkspace("w3", to: "  coordinator ", on: .local)
        #expect(await runner.recordedArguments() == [["workspace", "rename", "w3", "coordinator"]])
        await #expect(throws: HerdrFailure.self) { try await client.renameWorkspace("w3", to: "  ", on: .local) }
    }
}
