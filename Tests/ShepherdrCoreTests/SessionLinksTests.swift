import Foundation
import Testing
@testable import ShepherdrCore

struct SessionLinksTests {
    private let planner = Agent.ID(machineID: "local", terminalID: "planner")
    private let fixer = Agent.ID(machineID: "remote:box", terminalID: "fixer")
    private let reviewer = Agent.ID(machineID: "local", terminalID: "reviewer")

    private func resource(_ link: String) -> SessionResource { SessionResource(url: URL(string: link)!)! }

    private func item(_ kind: GitHubInboxItem.Kind, _ number: Int, linked: [Int] = []) -> GitHubInboxItem {
        let path = kind == .assignedIssue ? "issues" : "pull"
        return GitHubInboxItem(kind: kind, repository: InboxRepository(parsing: "theam/shepherdr")!, number: number,
                               title: "Item \(number)", url: URL(string: "https://github.com/theam/shepherdr/\(path)/\(number)")!,
                               author: "chema", updatedAt: Date(timeIntervalSince1970: 0),
                               linkedPullRequests: linked.map {
                                   LinkedPullRequest(number: $0, isOpen: true, isDraft: false,
                                                     url: URL(string: "https://github.com/theam/shepherdr/pull/\($0)")!)
                               })
    }

    @Test func sessionsAndPullRequestsLinkBothWays() {
        let links = SessionLinks([
            (planner, [resource("https://github.com/theam/shepherdr/issues/12"), resource("https://github.com/theam/shepherdr/pull/40")]),
            (fixer, [resource("https://github.com/Theam/Shepherdr/pull/40/files")]),
            (reviewer, [resource("https://github.com/theam/shepherdr/pull/41"), resource("https://claude.ai/artifact/3f450b55")]),
        ])
        #expect(links.sessions(for: "github.com/theam/shepherdr#40") == [planner, fixer])
        #expect(links.sessions(for: "GitHub.com/theam/shepherdr#12") == [planner])
        #expect(links.sessions(for: "github.com/theam/shepherdr#99").isEmpty)
        // An issue is worked on by the sessions of the pull requests that resolve it, too.
        #expect(links.sessions(for: item(.assignedIssue, 12, linked: [41])) == [planner, reviewer])
        #expect(links.sessions(for: item(.assignedIssue, 13, linked: [40])) == [planner, fixer])
        #expect(links.sessions(for: item(.reviewRequested, 41)) == [reviewer])
    }

    @Test func sessionsWorkInTheRepositoriesOfTheirFolders() {
        let shepherdr = InboxRepository(parsing: "theam/shepherdr")!, api = InboxRepository(parsing: "theam/api")!
        let links = SessionLinks([(planner, []), (fixer, []), (reviewer, [])],
                                 repositories: [planner: shepherdr, fixer: api, reviewer: shepherdr])
        #expect(links.repositories == [shepherdr, api])
        #expect(links.sessions(inRepository: "Theam/Shepherdr") == [planner, reviewer])
        #expect(links.sessions(inRepository: "theam/other").isEmpty)
    }

    @Test func pagesThatDontExistLinkNothing() {
        let links = SessionLinks([(planner, [resource("https://github.com/theam/shepherdr/pull/7").missing()])])
        #expect(links.sessions(for: "github.com/theam/shepherdr#7").isEmpty)
    }

    @Test func eachItemOffersWhatFitsItsSessions() {
        #expect(InboxAction(item: item(.assignedIssue, 1), sessions: []) == .implement)
        #expect(InboxAction(item: item(.reviewRequested, 2), sessions: []) == .review)
        #expect(InboxAction(item: item(.myPullRequest, 3), sessions: []) == .review)
        #expect(InboxAction(item: item(.assignedIssue, 1), sessions: [fixer]) == .open(fixer))
        #expect(InboxAction(item: item(.reviewRequested, 2), sessions: [fixer, planner]) == .choose([fixer, planner]))
    }

    @Test func numbersFindExactlyThatPullRequestOrIssue() {
        let twelve = resource("https://github.com/theam/shepherdr/pull/12").found(title: "Fix the login redirect")
        for word in ["theam/shepherdr#12", "Shepherdr#12", "#12", "shepherdr", "login", "theam/shep"] {
            #expect(SessionSearch.matches(twelve, word: word), "\(word)")
        }
        for word in ["theam/shepherdr#1", "#123", "theam/shepherdr#123", "other#12", "deploy"] {
            #expect(!SessionSearch.matches(twelve, word: word), "\(word)")
        }
    }
}
