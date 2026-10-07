import Foundation
import Testing
@testable import ShepherdrCore

struct PullRequestChecksTests {
    private func pull(_ link: String) -> SessionResource { SessionResource(url: URL(string: link)!)! }

    @Test func oneQueryAsksAboutEveryPullRequest() async {
        let answer = """
        {"data":{
          "p0":{"pullRequest":{"state":"OPEN","headRefOid":"abc","commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":[
            {"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"},
            {"__typename":"CheckRun","status":"IN_PROGRESS","conclusion":null},
            {"__typename":"StatusContext","state":"SUCCESS"}]}}}}]}}},
          "p1":{"pullRequest":{"state":"OPEN","headRefOid":"def","commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":[
            {"__typename":"CheckRun","status":"COMPLETED","conclusion":"FAILURE"},
            {"__typename":"CheckRun","status":"COMPLETED","conclusion":"SKIPPED"},
            {"__typename":"StatusContext","state":"ERROR"}]}}}}]}}},
          "p2":{"pullRequest":{"state":"MERGED","headRefOid":"123","commits":{"nodes":[{"commit":{"statusCheckRollup":null}}]}}},
          "p3":null},
         "errors":[{"message":"Could not resolve to a Repository"}]}
        """
        // gh fails when part of the query does, but still prints the rest.
        let runner = RecordingRunner([output(answer, stderr: "gh: Could not resolve to a Repository with the name 'a/b'.", code: 1)])
        let lookup = GitHubLookup(runner: runner, executable: URL(fileURLWithPath: "/usr/bin/true"))
        let pulls = ["https://github.com/theam/tam-os/pull/2175", "https://github.com/theam/tam-os/pull/2300",
                     "https://github.com/theam/shepherdr/pull/1", "https://github.com/a/b/pull/3"].map(pull)
        let checks = await lookup.checks(of: pulls)
        let running = checks?[pulls[0].key], failing = checks?[pulls[1].key], merged = checks?[pulls[2].key]
        #expect(running?.state == .running && running?.summary == "2 passed · 1 running" && running?.head == "abc")
        #expect(failing?.state == .failed && failing?.failed == 2 && failing?.passed == 1)
        #expect(merged?.isOpen == false && merged?.state == PullRequestChecks.State.none)
        #expect(checks?[pulls[3].key] == nil)
        let arguments = await runner.recordedArguments().first ?? []
        #expect(Array(arguments.prefix(3)) == ["api", "graphql", "-f"])
        let query = arguments.last ?? ""
        #expect(query.contains(#"p0: repository(owner: "theam", name: "tam-os") { pullRequest(number: 2175)"#))
        #expect(query.contains("p3: repository(owner: \"a\", name: \"b\")"))
    }

    @Test func finishingIsNoticedOnceAndPushesStartOver() {
        func checks(_ passed: Int, _ failed: Int, _ running: Int, head: String = "a", open: Bool = true) -> PullRequestChecks {
            PullRequestChecks(passed: passed, failed: failed, running: running, isOpen: open, head: head)
        }
        let running = checks(3, 0, 2)
        #expect(checks(5, 0, 0).justFinished(after: running))
        #expect(checks(4, 1, 0).justFinished(after: running))
        // A failure shows at once, but checks still running haven't finished.
        #expect(checks(3, 1, 1).state == .failed && !checks(3, 1, 1).justFinished(after: running))
        #expect(checks(4, 1, 0).justFinished(after: checks(3, 1, 1)))
        #expect(!checks(5, 0, 0).justFinished(after: checks(5, 0, 0)))  // Already done.
        #expect(!checks(5, 0, 0).justFinished(after: nil))  // First look.
        #expect(!checks(5, 0, 0, head: "b").justFinished(after: running))  // A new push.
        #expect(!checks(5, 0, 0, open: false).justFinished(after: running))  // Merged meanwhile.
        #expect(PullRequestChecks.combined([checks(5, 0, 0), running]) == .running)
        #expect(PullRequestChecks.combined([checks(5, 0, 0), checks(1, 1, 1)]) == .failed)
        #expect(PullRequestChecks.combined([checks(5, 0, 0), checks(0, 1, 0, open: false)]) == .passed)
        #expect(PullRequestChecks.combined([]) == nil)
    }

    @Test func nothingIsAskedWithoutTheCLIOrForOddNames() async {
        let runner = RecordingRunner([])
        #expect(await GitHubLookup(runner: runner, executable: nil).checks(of: [pull("https://github.com/a/b/pull/1")]) == nil)
        let odd = SessionResource(url: URL(string: "https://github.com/a%22%7D/b/pull/1")!)
        if let odd {
            #expect(await GitHubLookup(runner: runner, executable: URL(fileURLWithPath: "/usr/bin/true")).checks(of: [odd]) == nil)
        }
        #expect(await runner.recordedArguments().isEmpty)
    }
}
